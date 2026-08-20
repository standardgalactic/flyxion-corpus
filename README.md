# Flyxion TeX Corpus

This repository consolidates the distributed TeX writings of Flyxion into one provenance-preserving corpus. It exists to make a large body of essays, papers, books, monographs, drafts, chapters, and technical documents easier to inventory, compile, search, compare, and analyze without erasing where each file originally came from.

The corpus was assembled from files attributed to Flyxion across repositories in the GitHub contribution history of `standardgalactic`. Original ownership, repository names, and internal paths are retained beneath:

```text
sources/OWNER/REPOSITORY/original/path/document.tex
```

The inventory identified 967 candidate TeX files, of which 965 are currently tracked here. A file is not necessarily a unique or finished work: the corpus includes drafts, alternate versions, processed copies, modular chapters, and repeated documents. The metadata preserves these distinctions rather than silently choosing a canonical edition.

## Purpose

The repository serves four related purposes. It preserves a recoverable snapshot of the distributed sources; records enough provenance to trace every collected file back to its source repository; provides a repeatable LuaLaTeX compilation pipeline; and produces readable text and machine-readable manifests for corpus analysis.

It is not a curated collected works edition. Inclusion means that a file matched the inventory procedure, not that it is complete, canonical, endorsed for publication, or independently compilable.

## Repository structure

```text
.
├── sources/                         Collected TeX sources, preserving provenance
├── metadata/
│   ├── source-inventory.tsv         Original inventory used for collection
│   ├── collection-manifest.tsv      Collection status and source locations
│   ├── root-candidates.tsv          Likely independently compilable documents
│   └── collection-errors.log        Collection-stage errors
├── flyxion-inventory/               Inventory reports and local scan state
├── flyxion-inventory.sh             Discover and classify attributed TeX files
├── collect-flyxion-corpus.sh        Assemble the provenance-preserving corpus
├── compile-flyxion-corpus.sh        Compile likely root documents with LuaLaTeX
├── extract-flyxion-text.sh          Extract readable UTF-8 text from PDFs
├── analyze-flyxion-build.sh         Summarize builds and detect text duplicates
└── build-flyxion-corpus.sh           Run compilation, extraction, and analysis
```

The inventory cache and search cache are local working data and should remain ignored by Git. Generated compilation artifacts belong under `build/`, which should also remain untracked.

## Requirements

The scripts assume a Unix-like environment with Bash and common GNU utilities. The principal external commands are:

```text
gh  jq  perl  ripgrep  sha256sum  flock  timeout
lualatex  pdfinfo  pdftotext
```

LuaLaTeX documents may require additional TeX packages, fonts, bibliography tools, images, style files, or included sources that are not present in this corpus.

## Compile, extract, and analyze

The wrapper runs the complete build pipeline:

```bash
chmod +x ./*flyxion*.sh
./build-flyxion-corpus.sh --jobs 2 --timeout 180
```

It discovers likely root documents by finding TeX files beneath `sources/` that contain `\documentclass`. Each root is compiled twice with LuaLaTeX in an isolated working directory. A failed or timed-out document is recorded without stopping the rest of the corpus.

Successful PDFs are converted to flowing UTF-8 text, after which the analysis stage reports compilation outcomes, page totals, extracted word counts, and exact normalized-text duplicate groups.

Generated output mirrors the original source paths:

```text
build/
├── pdfs/                    Compiled PDFs
├── text/                    Readable extracted text
├── logs/                    LuaLaTeX logs
├── work/                    Auxiliary compilation files
├── compile-manifest.tsv     Per-document compilation results
├── text-manifest.tsv        Per-PDF extraction results
├── text-duplicates.tsv      Exact normalized-text duplicate groups
└── analysis-summary.txt     Corpus-level build summary
```

For example:

```text
sources/standardgalactic/alphabet/science/example.tex
build/pdfs/sources/standardgalactic/alphabet/science/example.pdf
build/text/sources/standardgalactic/alphabet/science/example.txt
build/logs/sources/standardgalactic/alphabet/science/example.log
```

Existing PDFs newer than their root TeX files are reused. To rebuild and re-extract everything:

```bash
./build-flyxion-corpus.sh --jobs 2 --timeout 180 --force
```

The stages can also be run separately:

```bash
./compile-flyxion-corpus.sh --jobs 2 --timeout 180
./extract-flyxion-text.sh
./analyze-flyxion-build.sh
```

For extracted text that retains more of the PDF's visual spacing:

```bash
./extract-flyxion-text.sh --layout --force
```

## Rebuild the inventory

The existing corpus can be used without rerunning discovery. To regenerate the repository list from recognized GitHub commit contributions and rescan it:

```bash
./flyxion-inventory.sh --make-contribution-repo-list
./flyxion-inventory.sh --repos repos.txt
```

GitHub code search is rate-limited. The inventory script throttles requests, retries transient failures, and caches completed repository searches so an interrupted scan can resume.

To reconstruct the corpus from the resulting inventory:

```bash
./collect-flyxion-corpus.sh
```

If an inventory cache entry is missing, collection can retrieve it from GitHub:

```bash
./collect-flyxion-corpus.sh --download-missing
```

## Compilation limitations

The initial inventory searched for TeX files containing the name `Flyxion`. A modular root document may depend on chapters, bibliographies, figures, fonts, or custom packages that do not contain that name and were therefore never collected. Consequently, compilation failure often indicates a missing dependency rather than a malformed or unfinished work.

The build logs are evidence for subsequent repair, not a quality ranking. They make it possible to distinguish missing files, unavailable packages, font problems, syntax failures, and timeouts before deciding whether a document should be repaired, supplemented from its source repository, or left as an archival fragment.

## Provenance

Every collected path remains associated with its original repository and source URL in `metadata/collection-manifest.tsv`. Consolidation does not replace the original Git histories; it creates a searchable working corpus whose contents can be traced back to them.

