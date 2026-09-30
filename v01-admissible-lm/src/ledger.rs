//! Same shape as entheai's `repair_stop.rs` (RepairLedger / StopReason),
//! adapted to a training step instead of an agent action: every step is
//! logged as Admitted, Rejected (with a reason), or Repaired (restored
//! from the last admitted checkpoint) -- never silently discarded the
//! way plain gradient clipping / skip-on-NaN would.
//!
//! v0 scope, deliberately not the full J(a|h) = E + λR + μΔ_dep − νM
//! objective: a single computed admissibility check (does the
//! coarse-grained gradient direction agree with the full-batch
//! direction) plus a finiteness check, same "hold at single-scalar
//! margin until Γ is frozen" decision already made for entheai.

#[derive(Clone, Debug)]
pub enum RejectReason {
    /// Loss or a gradient tensor contained a non-finite value.
    DivergentLoss,
    /// Cosine similarity between the full-batch gradient and the
    /// coarse-grained (subsampled) gradient fell below the admissibility
    /// threshold -- the step's direction doesn't persist under
    /// coarse-graining, the same continuation test initialize.sh runs
    /// on images, applied here to a gradient direction instead of a PNG.
    NoisyGradient { cosine: f32, threshold: f32 },
}

#[derive(Clone, Debug)]
pub enum StepDecision {
    Admitted { step: usize, loss: f32, cosine: f32 },
    Rejected { step: usize, reason: RejectReason },
    Repaired { step: usize, restored_from_step: usize },
}

#[derive(Default)]
pub struct Ledger {
    pub entries: Vec<StepDecision>,
}

impl Ledger {
    pub fn new() -> Self {
        Ledger { entries: Vec::new() }
    }

    pub fn record(&mut self, decision: StepDecision) {
        self.entries.push(decision);
    }

    pub fn summary(&self) -> String {
        let mut admitted = 0usize;
        let mut rejected_divergent = 0usize;
        let mut rejected_noisy = 0usize;
        let mut repaired = 0usize;

        for e in &self.entries {
            match e {
                StepDecision::Admitted { .. } => admitted += 1,
                StepDecision::Rejected { reason: RejectReason::DivergentLoss, .. } => {
                    rejected_divergent += 1
                }
                StepDecision::Rejected { reason: RejectReason::NoisyGradient { .. }, .. } => {
                    rejected_noisy += 1
                }
                StepDecision::Repaired { .. } => repaired += 1,
            }
        }

        format!(
            "admitted={admitted} rejected(divergent)={rejected_divergent} rejected(noisy)={rejected_noisy} repaired={repaired} total={}",
            self.entries.len()
        )
    }

    /// Print every non-Admitted entry -- the interesting ones -- so a
    /// run's full decision trail is inspectable, not just the summary.
    pub fn print_exceptions(&self) {
        for e in &self.entries {
            match e {
                StepDecision::Admitted { .. } => {}
                other => println!("{other:?}"),
            }
        }
    }
}
