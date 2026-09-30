use crate::ledger::{Ledger, RejectReason, StepDecision};
use crate::model::{grads_finite, Grads, Model};
use rand::Rng;
use rand::SeedableRng;
use std::path::PathBuf;

pub struct TrainConfig {
    pub steps: usize,
    pub batch_size: usize,
    pub block_size: usize,
    pub lr: f32,
    pub admissibility_threshold: f32, // min cosine(full, coarse) to admit a step
    pub checkpoint_every: usize,      // admitted steps between in-memory repair checkpoints
    pub repair_after_consecutive_rejects: usize,
    pub seed: u64,
    // Disk persistence -- separate concern from the in-memory repair
    // checkpoint above. save_every is in raw step count (not admitted
    // count), so a long run is guaranteed to periodically land on disk
    // regardless of how strict the admissibility gate is being.
    pub save_path: Option<PathBuf>,
    pub save_every: usize,
}

/// Draws one (context, target) pair directly from the raw token stream
/// at a random position -- no upfront materialization of every position
/// in the corpus. This is the fix for the previous version, which built
/// a `(Vec<usize>, usize)` for literally every token position in the
/// whole corpus before training even started: on a multi-million-token
/// word-level corpus that's millions of small heap allocations done
/// synchronously with no progress output, which is what looked like a
/// hang (and plausibly was enough memory/CPU pressure to crash).
fn sample_example(tokens: &[usize], block_size: usize, rng: &mut impl Rng) -> (Vec<usize>, usize) {
    let i = rng.gen_range(0..(tokens.len() - block_size));
    let ctx = tokens[i..i + block_size].to_vec();
    let target = tokens[i + block_size];
    (ctx, target)
}

pub fn train(model: &mut Model, tokens: &[usize], cfg: &TrainConfig) -> Ledger {
    let mut rng = rand::rngs::StdRng::seed_from_u64(cfg.seed);
    let mut ledger = Ledger::new();

    let mut checkpoint = model.clone();
    let mut checkpoint_step = 0usize;
    let mut consecutive_rejects = 0usize;
    let mut admitted_since_checkpoint = 0usize;

    for step in 0..cfg.steps {
        let full_batch: Vec<(Vec<usize>, usize)> = (0..cfg.batch_size)
            .map(|_| sample_example(tokens, cfg.block_size, &mut rng))
            .collect();

        // Coarse-graining: an independently-drawn half-size batch, not a
        // subset of full_batch -- a subset shares the same underlying
        // draws and is structurally biased toward agreeing with the
        // full batch regardless of whether the direction is meaningful.
        // An independent draw is a fairer continuation test, closer in
        // spirit to initialize.sh's downsample/upsample round trip.
        let half = (cfg.batch_size / 2).max(1);
        let coarse_batch: Vec<(Vec<usize>, usize)> = (0..half)
            .map(|_| sample_example(tokens, cfg.block_size, &mut rng))
            .collect();

        // full_batch and coarse_batch gradients are independent of each
        // other (both read-only against the current model weights), so
        // compute them concurrently rather than sequentially.
        let (loss_result, coarse_result) = rayon::join(
            || model.batch_grad(&full_batch),
            || model.batch_grad(&coarse_batch),
        );
        let (loss, grad_full) = loss_result;
        let (_loss_coarse, grad_coarse) = coarse_result;

        if !loss.is_finite() || !grads_finite(&grad_full) || !grads_finite(&grad_coarse) {
            ledger.record(StepDecision::Rejected { step, reason: RejectReason::DivergentLoss });
            consecutive_rejects += 1;
        } else {
            let cosine = Grads::cosine_similarity(&grad_full, &grad_coarse);

            if cosine < cfg.admissibility_threshold {
                ledger.record(StepDecision::Rejected {
                    step,
                    reason: RejectReason::NoisyGradient { cosine, threshold: cfg.admissibility_threshold },
                });
                consecutive_rejects += 1;
            } else {
                model.apply_update(&grad_full, cfg.lr);
                ledger.record(StepDecision::Admitted { step, loss, cosine });
                consecutive_rejects = 0;
                admitted_since_checkpoint += 1;

                if admitted_since_checkpoint >= cfg.checkpoint_every {
                    checkpoint = model.clone();
                    checkpoint_step = step;
                    admitted_since_checkpoint = 0;
                }
            }
        }

        if consecutive_rejects >= cfg.repair_after_consecutive_rejects {
            *model = checkpoint.clone();
            ledger.record(StepDecision::Repaired { step, restored_from_step: checkpoint_step });
            consecutive_rejects = 0;
        }

        if step % 200 == 0 {
            eprintln!("step {step}: {}", ledger.summary());
        }

        if let Some(path) = &cfg.save_path {
            if cfg.save_every > 0 && (step + 1) % cfg.save_every == 0 {
                match model.save(path) {
                    Ok(()) => eprintln!("checkpoint saved to {} at step {step}", path.display()),
                    Err(e) => eprintln!("WARNING: failed to save checkpoint at step {step}: {e}"),
                }
            }
        }
    }

    ledger
}
