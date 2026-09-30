mod data;
mod ledger;
mod mat;
mod model;
mod train;

use data::Corpus;
use model::Model;
use rand::{Rng, SeedableRng};
use std::collections::HashMap;
use std::path::PathBuf;
use train::TrainConfig;

struct Args {
    corpus: PathBuf,
    block_size: usize,
    emb_dim: usize,
    hidden_dim: usize,
    steps: usize,
    batch_size: usize,
    lr: f32,
    threshold: f32,
    seed: u64,
    sample_len: usize,
    min_freq: usize,
    save_path: PathBuf,
    save_every: usize,
    resume: Option<PathBuf>,
    show_exceptions: bool,
    dump_corpus: bool,
}

fn parse_args() -> Args {
    let raw: Vec<String> = std::env::args().collect();
    let mut kv: HashMap<String, String> = HashMap::new();
    let mut i = 1;
    let mut show_exceptions = false;
    let mut dump_corpus = false;
    while i < raw.len() {
        let key = &raw[i];
        if key == "--exceptions" {
            show_exceptions = true;
            i += 1;
            continue;
        }
        if key == "--dump-corpus" {
            dump_corpus = true;
            i += 1;
            continue;
        }
        if let Some(stripped) = key.strip_prefix("--") {
            if i + 1 < raw.len() {
                kv.insert(stripped.to_string(), raw[i + 1].clone());
                i += 2;
                continue;
            }
        }
        i += 1;
    }

    let get = |k: &str, default: &str| kv.get(k).cloned().unwrap_or_else(|| default.to_string());

    Args {
        corpus: PathBuf::from(get("corpus", "./corpus")),
        block_size: get("block-size", "8").parse().unwrap(),
        emb_dim: get("emb-dim", "16").parse().unwrap(),
        hidden_dim: get("hidden-dim", "128").parse().unwrap(),
        steps: get("steps", "2000").parse().unwrap(),
        batch_size: get("batch-size", "32").parse().unwrap(),
        lr: get("lr", "0.05").parse().unwrap(),
        threshold: get("threshold", "0.2").parse().unwrap(),
        seed: get("seed", "1337").parse().unwrap(),
        sample_len: get("sample-len", "300").parse().unwrap(),
        min_freq: get("min-freq", "5").parse().unwrap(),
        save_path: PathBuf::from(get("save-path", "model.bin")),
        save_every: get("save-every", "500").parse().unwrap(),
        resume: kv.get("resume").map(PathBuf::from),
        show_exceptions,
        dump_corpus,
    }
}

fn sample(model: &Model, seed_ctx: &[usize], n: usize, temperature: f32, rng: &mut impl Rng) -> Vec<usize> {
    let mut ctx: Vec<usize> = seed_ctx.to_vec();
    let mut generated = Vec::with_capacity(n);
    for _ in 0..n {
        let probs = model.probs_for(&ctx);
        let adj: Vec<f32> = probs.data.iter().map(|&p| (p.max(1e-9)).powf(1.0 / temperature)).collect();
        let sum: f32 = adj.iter().sum();
        let r: f32 = rng.gen_range(0.0..sum);
        let mut acc = 0.0;
        let mut chosen = 0usize;
        for (i, &v) in adj.iter().enumerate() {
            acc += v;
            if acc >= r {
                chosen = i;
                break;
            }
        }
        generated.push(chosen);
        ctx.remove(0);
        ctx.push(chosen);
    }
    generated
}

fn main() {
    let args = parse_args();

    let corpus = Corpus::load_dir(&args.corpus, args.min_freq).unwrap_or_else(|e| {
        eprintln!("failed to load corpus dir {:?}: {e}", args.corpus);
        std::process::exit(1);
    });
    eprintln!("vocab size: {}", corpus.vocab_size());

    if args.dump_corpus {
        // Print the whole corpus rendered back through the tokenizer
        // (as the model would actually see it, post-LaTeX-stripping and
        // post-<unk>-folding) and exit -- for checking corpus/tokenizer
        // quality before committing to a long training run.
        println!("{}", corpus.render(&corpus.tokens));
        return;
    }

    if corpus.tokens.len() <= args.block_size {
        eprintln!("corpus too small for block_size {} ({} tokens)", args.block_size, corpus.tokens.len());
        std::process::exit(1);
    }

    let mut model = match &args.resume {
        Some(path) => {
            eprintln!("resuming from {}", path.display());
            let m = Model::load(path).unwrap_or_else(|e| {
                eprintln!("failed to load {:?}: {e}", path);
                std::process::exit(1);
            });
            if m.vocab_size != corpus.vocab_size() || m.block_size != args.block_size {
                eprintln!(
                    "WARNING: resumed model shape (vocab={}, block={}) doesn't match this corpus/args (vocab={}, block={}) -- \
                     this corpus was likely tokenized with a different --min-freq or --block-size than the checkpoint was trained with. \
                     Proceeding anyway will likely produce garbage.",
                    m.vocab_size, m.block_size, corpus.vocab_size(), args.block_size
                );
            }
            m
        }
        None => Model::new(corpus.vocab_size(), args.block_size, args.emb_dim, args.hidden_dim, args.seed),
    };

    let cfg = TrainConfig {
        steps: args.steps,
        batch_size: args.batch_size,
        block_size: args.block_size,
        lr: args.lr,
        admissibility_threshold: args.threshold,
        checkpoint_every: 50,
        repair_after_consecutive_rejects: 5,
        seed: args.seed,
        save_path: Some(args.save_path.clone()),
        save_every: args.save_every,
    };

    let ledger = train::train(&mut model, &corpus.tokens, &cfg);

    match model.save(&args.save_path) {
        Ok(()) => eprintln!("final model saved to {}", args.save_path.display()),
        Err(e) => eprintln!("WARNING: failed to save final model: {e}"),
    }

    println!("\n=== training summary ===");
    println!("{}", ledger.summary());
    if args.show_exceptions {
        println!("\n=== non-admitted steps ===");
        ledger.print_exceptions();
    }

    let mut rng = rand::rngs::StdRng::seed_from_u64(args.seed + 1);
    let seed_start = rng.gen_range(0..(corpus.tokens.len() - args.block_size));
    let seed_ctx = corpus.tokens[seed_start..seed_start + args.block_size].to_vec();
    let generated_ids = sample(&model, &seed_ctx, args.sample_len, 0.8, &mut rng);

    println!("\n=== sample ===");
    println!("[seed: {}]{}", corpus.render(&seed_ctx), corpus.render(&generated_ids));
}
