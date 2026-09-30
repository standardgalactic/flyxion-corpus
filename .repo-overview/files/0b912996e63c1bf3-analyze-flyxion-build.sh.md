**File Summary: analyze-flyxion-build.sh**

This script is a Bash utility for analyzing the build process of a Flyxion corpus. Its primary purpose is to summarize compilation statistics and text extraction results from generated manifest files.

- **Principal Ideas/Behavior**: 
  - Accepts optional arguments (`--build`) to specify the build directory.
  - Checks for required files: `compile-manifest.tsv`, `text-manifest.tsv`, and generates an analysis summary in `analysis-summary.txt`.
  - Computes and prints statistics such as the number of root documents, compiled pages, and total compile seconds from `compile-manifest.tsv`.
  - If `text-manifest.tsv` exists, it extracts additional metrics like PDFs processed, extracted words, and lines.
  - Identifies duplicate normalized text entries by hashing text files and listing occurrences in `text-duplicates.tsv`.

- **Important Dependencies/Outputs**:
  - Requires the presence of `compile-manifest.tsv` to proceed; otherwise, it exits with an error.
  - Generates outputs: `analysis-summary.txt`, `text-duplicates.tsv`.
  - Prints the number of duplicate text groups based on the contents of `text-duplicates.tsv`.

- **Completeness Assessment**: The script appears complete for its intended functionality, containing necessary checks and output generation. No signs of being generated, duplicated, or problematic are evident.
