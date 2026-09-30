# admissible-lm (v0)

Hand-rolled character-level MLP language model (no autodiff engine --
forward and backward are both written out by hand in src/model.rs, in the
Bengio-2003 / makemore-MLP shape: concatenated context embeddings -> tanh
hidden layer -> softmax over vocab) with an admissibility-gated training
loop in src/train.rs.

## What the gate does

Every step samples a batch and a coarse-grained half-subsample of that
batch, computes the gradient for each, and checks:

1. Are loss and both gradients finite? If not -> Rejected(DivergentLoss).
2. Does the coarse-grained gradient direction agree with the full-batch
   direction (cosine similarity above --threshold)? If not ->
   Rejected(NoisyGradient).
3. Otherwise -> Admitted, and the update is applied.

This is the same continuation test initialize.sh runs on images (does
structure survive a coarse-graining round trip), applied here to a
gradient direction instead of a PNG.

Every decision is logged to a Ledger (src/ledger.rs) -- same shape as
entheai's RepairLedger/StopReason -- so rejected steps are visible, not
silently skipped the way plain gradient clipping would be. After 5
consecutive rejects, the model is restored from its last checkpoint
(logged as Repaired) rather than continuing to update from a state the
gate has stopped trusting.

v0 scope, deliberately: this is a single computed admissibility check,
not the full J(a|h) = E + λR + μΔ_dep − νM objective from
diagnostic-coordinates-repair -- same "don't refactor against a moving
target" decision already made for entheai's RepairLedger.

## Usage

    cargo build --release
    ./target/release/admissible_lm \
        --corpus /path/to/a/directory/of/txt/tex/md/files \
        --block-size 8 --emb-dim 16 --hidden-dim 128 \
        --steps 5000 --batch-size 32 --lr 0.05 \
        --threshold 0.2 --seed 1337 --sample-len 400

--corpus points at a *directory* (non-recursive): every .txt/.tex/.md
file directly inside it is concatenated. Point it at a folder of your
essays/paracosm corpus, or a subset of it -- vocab size and load time
scale with what's in that folder.

--exceptions prints every non-Admitted ledger entry (Rejected/Repaired),
not just the summary counts.

## What's untested / next

- --threshold and --lr are unvalidated starting points, same epistemic
  status as Psi's coefficients in initialize.sh -- calibrate against a
  real run before trusting the numbers.
- Only tested so far on a ~500-character synthetic corpus (smoke test,
  not a real training run) -- confirms the mechanics work, says nothing
  about whether the gate's threshold is well-calibrated at real corpus
  scale.
- No branch (2) or (3) of the refusal taxonomy from
  diagnostic-coordinates-repair (no comparison class / unclear
  obstruction locus) -- only branch (1), matching entheai's current
  scope.
