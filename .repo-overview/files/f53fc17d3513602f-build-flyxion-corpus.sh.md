**Repository Path:** build-flyxion-corpus.sh

This script orchestrates the compilation, PDF-to-text extraction, and analysis of a research/software corpus. Its purpose is to run these processes in sequence, allowing for customization via command-line arguments such as specifying the corpus directory, build output directory, number of parallel jobs, timeout duration, and forcing certain operations.

**Principal Ideas/Behavior:**
- Orchestrates three main steps: compilation, text extraction, and analysis.
- Utilizes environment variables and positional parameters to configure behavior dynamically.
- Ensures robustness with `set -Euo pipefail` for error handling and pipeline integrity.
- Provides usage instructions via the `-h` or `--help` flag.

**Important Dependencies/Outputs:**
- Depends on three other scripts:
  1. `compile-flyxion-corpus.sh`
  2. `extract-flyxion-text.sh`
  3. `analyze-flyxion-build.sh`
- Outputs are primarily the results of the analysis step, as indicated by the final command execution.

**Completeness Assessment:**
- The script appears complete with all necessary components and usage instructions.
- No signs of being generated, duplicated, or problematic based on the provided content.
