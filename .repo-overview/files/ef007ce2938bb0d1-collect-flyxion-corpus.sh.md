**collect-flyxion-corpus.sh**

*Purpose:*  
Collects all TeX source files listed in a Flyxion inventory into a single Git‑aware working tree, preserving provenance from the original inventory. It reads an inventory TSV (default `flyxion-inventory/inventory.tsv`), optionally downloads missing files via GitHub API (`gh` command), and organizes sources under `sources/OWNER/REPOSITORY/`. The script generates metadata manifest files (`collection-manifest.tsv`, `root-candidates.tsv`) and a README summarizing collection statistics.

*Principal Ideas / Behavior:*  
- Parses inventory TSV to extract repository, path, title, document class, word count, content hash, and URL.  
- Optionally downloads missing source files from GitHub using the provided URL reference (`ref` variable).  
- Copies sources into `DEST/sources`, updating metadata manifest with status (copied/unchanged/missing/conflict) and root candidates list for potential documents containing a document class.  
- Initializes a Git repository if requested, and commits changes when instructed.  
- Handles conflicts by keeping existing files rather than overwriting unless the `--force` flag is set.

*Important Dependencies / Outputs:*  
- Requires GNU core utilities (`awk`, `sed`, `sha256sum`, `cmp`, `cp`, `mkdir`).  
- Needs the GitHub CLI (`gh`) for downloading missing files.  
- Generates output files: `collection-manifest.tsv`, `root-candidates.tsv`, `collection-errors.log`, and a README summarizing collection statistics.

*Completeness Assessment:*  
The script appears **complete** as it includes all necessary logic to read, filter, download (when enabled), copy, and metadata generation steps. It handles edge cases such as missing cache files, unchanged files, conflicts, and provides informative output for each collected item. No obvious gaps or missing functionality are evident based on the provided code structure.
