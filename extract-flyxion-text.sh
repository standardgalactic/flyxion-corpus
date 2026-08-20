#!/usr/bin/env bash
# Convert compiled corpus PDFs to readable UTF-8 text while preserving paths.
set -Euo pipefail

BUILD="build"
LAYOUT=0
FORCE=0

while (($#)); do
  case "$1" in
    --build) BUILD=$2; shift 2 ;;
    --layout) LAYOUT=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) printf 'Usage: %s [--build DIR] [--layout] [--force]\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

for cmd in pdftotext find sha256sum; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 1; }
done
[[ -d "$BUILD/pdfs" ]] || { printf 'PDF directory not found: %s/pdfs\n' "$BUILD" >&2; exit 1; }
mkdir -p "$BUILD/text"
MANIFEST="$BUILD/text-manifest.tsv"
printf 'status\tpdf\ttext\twords\tlines\ttext_hash\n' > "$MANIFEST"

while IFS= read -r -d '' pdf; do
  rel=${pdf#"$BUILD/pdfs"/}
  text="$BUILD/text/${rel%.pdf}.txt"
  mkdir -p "$(dirname "$text")"
  status="failed"
  if [[ -s "$text" && "$text" -nt "$pdf" && "$FORCE" -eq 0 ]]; then
    status="cached"
  else
    args=(-enc UTF-8 -nopgbrk)
    ((LAYOUT)) && args+=(-layout)
    if pdftotext "${args[@]}" "$pdf" "$text.tmp" 2>>"$BUILD/text-errors.log"; then
      mv "$text.tmp" "$text"
      status="success"
    else
      rm -f "$text.tmp"
    fi
  fi
  if [[ -f "$text" ]]; then
    words=$(wc -w < "$text")
    lines=$(wc -l < "$text")
    hash=$(tr -s '[:space:]' ' ' < "$text" | sha256sum | awk '{print $1}')
  else
    words=0; lines=0; hash=""
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$pdf" "$text" "$words" "$lines" "$hash" >> "$MANIFEST"
  printf '%-7s %s\n' "$status" "$rel" >&2
done < <(find "$BUILD/pdfs" -type f -name '*.pdf' -print0)

awk -F '\t' 'NR>1 {count[$1]++; words+=$4} END {for(s in count) print count[s],s; print words,"extracted words"}' "$MANIFEST"

