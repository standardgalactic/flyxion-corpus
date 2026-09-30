## admissible-lm (v0)

**Purpose:**  
A hand-rolled character-level Multi-Layer Perceptron (MLP) language model designed to generate text without relying on an autodiff engine. It follows the architecture described in Bengio-2003 and makemore-MLP, using concatenated context embeddings, a tanh hidden layer, and softmax over the vocabulary.

**Principal Ideas/Behavior:**  
The model includes an admissibility-gated training loop that evaluates each gradient step for:
1. Finite loss and gradients (Reject if divergent).
2. Agreement between coarse-grained and full-batch gradients via cosine similarity threshold (Reject if noisy).
3. Admits the step otherwise, applying the update.

If five consecutive steps are rejected, the model is restored from its last checkpoint (logged as Repaired).

**Important Dependencies/Outputs:**  
- Requires a directory of text files (.txt/.tex/.md) for the corpus.
- Outputs generated text based on the trained model parameters.
- Logs decisions to a Ledger (src/ledger.rs), tracking reasons for rejection or repair.

**Completeness Assessment:**  
The repository appears complete for its current scope, which is limited to implementing the admissibility check as described. It does not include full optimization techniques from diagnostic-coordinates-repair and has only been tested on a synthetic corpus.

**Potential Issues:**  
- Starting values for `--threshold` and `--lr` are unvalidated; calibration needed for real datasets.
- Only tested on a small synthetic corpus, confirming mechanics but not real-world calibration of the gate's threshold.
