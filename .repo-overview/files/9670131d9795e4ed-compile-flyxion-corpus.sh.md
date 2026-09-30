**File Summary: compile-flyxion-corpus.sh**

- **Purpose:** Automates the compilation of all likely root TeX documents (`*.tex`) within a Flyxion corpus using LuaLaTeX. It generates PDFs, logs, and work files in directories mirroring the original corpus structure.

- **Principal Ideas/Behavior:** 
  - Scans the `sources` directory under the specified `CORPUS` for files containing `\documentclass`. 
  - Compiles each TeX file to a PDF using LuaLaTeX with error handling.
  - Records compilation status (success, cached, timeout) along with elapsed time and page count in a manifest file.
  - Supports parallel processing via job count (`JOBS`) and respects timeouts (`TIME_LIMIT`).
  - Optionally runs as a worker process when invoked directly.

- **Important Dependencies:** 
  - `rg` (ripgrep), `lualatex`, `timeout`, `realpath`, `flock`, and `pdfinfo` must be available in the environment.
  - Requires a directory structure with a `sources` folder containing TeX files under the specified `CORPUS`.

- **Outputs:** 
  - Compiles PDFs to `$BUILD/pdfs/`.
  - Writes log files to `$BUILD/logs/`.
  - Generates a manifest (`compile-manifest.tsv`) summarizing compilation status, source paths, and elapsed times.

- **Completeness Assessment:** The script appears complete for its intended functionality, including error handling, parallel execution support, and dependency checks. No obvious gaps or missing critical components are evident.
