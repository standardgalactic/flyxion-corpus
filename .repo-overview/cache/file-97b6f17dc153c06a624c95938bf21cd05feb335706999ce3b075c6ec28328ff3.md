**File Summary: extract-flyxion-text.sh**

This script is designed to convert compiled corpus PDF files into readable UTF-8 text while preserving the original file paths. Its primary purpose is to process a directory of PDFs (`$BUILD/pdfs`) and generate corresponding text files in a separate `text` directory.

**Principal Ideas/Behavior:**
- Accepts command-line options to specify the build directory, enable layout processing, or force recreation of text files.
- Validates that required utilities (`pdftotext`, `find`, `sha256sum`) are installed.
- Checks for the existence of the PDF directory; otherwise, it exits with an error.
- Creates a manifest file (`$MANIFEST`) to record metadata about each processed PDF, including status (success/failure/cached), path, text file location, word count, line count, and SHA-256 hash of the text content.
- Iterates over all PDF files found in the specified directory, converting them to text if they are newer than their text counterparts or if the `--force` flag is used. Errors during conversion are logged to `text-errors.log`.

**Important Dependencies/Outputs:**
- Depends on external tools: `pdftotext`, `find`, and `sha256sum`.
- Outputs a manifest file (`$MANIFEST`) summarizing processing status, word count, line count, and hash for each PDF.
- Generates text files in the `text` directory with names derived from the original PDFs (e.g., `example.pdf` becomes `example.txt`).

**Completeness Assessment:**
The script appears to be complete as it includes necessary error handling, validation checks, and a clear workflow for processing PDFs into text while maintaining metadata. It does not appear to be generated, duplicated, or problematic based on the provided content.
