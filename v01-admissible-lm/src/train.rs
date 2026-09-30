use crate::ledger::{Ledger, RejectReason, StepDecision};
use crate::model::{grads_finite, Grads, Model};
use rand::seq::SliceRandom;
use rand::SeedableRng;

pub struct TrainConfig {
    pub steps: usize,
    pub batch_size: usize,
    pub lr: f32,
    pub admissibility_threshold: f32, // min cosine(full, coarse) to admit a step
    pub checkpoint_every: usize,      // admitted steps between checkpoints
    pub repair_after_consecutive_rejects: usize,
    pub seed: u64,
}

pub fn train(
    model: &mut Model,
    examples: &[(Vec<usize>, usize)],
    cfg: &TrainConfig,
) -> Ledger {
    let mut rng = rand::rngs::StdRng::seed_from_u64(cfg.seed);
    let mut ledger = Ledger::new();

    let mut checkpoint = model.clone();
    let mut checkpoint_step = 0usize;
    let mut consecutive_rejects = 0usize;
    let mut admitted_since_checkpoint = 0usize;

    for step in 0..cfg.steps {
        let full_batch: Vec<(Vec<usize>, usize)> = (0..cfg.batch_size)
            .map(|_| examples.choose(&mut rng).unwrap().clone())
            .collect();

        // Coarse-graining: subsample the batch to half size. If the
        // gradient direction this batch implies doesn't survive that
        // coarse-graining, the step is treated the way initialize.sh
        // treats an image whose structure doesn't survive
        // downsample/upsample -- not admissible as a representative
        // direction to commit to the weights.
        let half = (cfg.batch_size / 2).max(1);
        let coarse_batch: Vec<(Vec<usize>, usize)> = full_batch
            .choose_multiple(&mut rng, half)
            .cloned()
            .collect();

        let (loss, grad_full) = model.batch_grad(&full_batch);
        let (_loss_coarse, grad_coarse) = model.batch_grad(&coarse_batch);

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
    }

    ledger
}
