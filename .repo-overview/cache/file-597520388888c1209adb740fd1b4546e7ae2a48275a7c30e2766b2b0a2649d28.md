**Summary of `admissible-lm/src/data.rs`:**

This Rust module provides utilities for processing and loading text data from files (`.txt`, `.tex`, or `.md`) located in a specified directory. Its primary purpose is to prepare the corpus for training language models by:

- **Collecting Files:** Recursively gathering all non-hidden, non-system directories (`target` or `node_modules`) containing plain text files using `collect_files_recursive`.
  
- **Stripping LaTeX:** Removing LaTeX-specific content (comments, math environments, certain commands) with `strip_latex`, which simplifies the input by eliminating markup that would otherwise interfere with word-level tokenization.

- **Tokenizing Text:** Converting cleaned text into a list of tokens using `tokenize_words`, where punctuation and special characters are treated as separate tokens except for hyphens in compound words.

- **Building Corpus Structure:** Creating a `Corpus` struct that holds vocabulary, a string-to-ID mapping (`stoi`), tokenized sequences, and an unknown token ID. The corpus is initialized from concatenated text files with `load_dir`, filtering out infrequent words based on `min_freq`.

Key components include:
- **Dependencies:** Uses standard library modules like `std::collections::HashMap`, `std::fs`, and `std::path`.
- **Outputs:** Provides methods to retrieve vocabulary size, render token sequences back into readable text, and generate (context, target) pairs for training data.
- **Completeness:** The module appears complete with all necessary functions and dependencies defined inline. No external crates are required beyond the standard library.

Overall, this repository component is designed to handle preprocessing steps essential for preparing natural language datasets in a research or software context without relying on third-party libraries.
