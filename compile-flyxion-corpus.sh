#!/usr/bin/env bash
# Compile every likely root TeX document in a Flyxion corpus with LuaLaTeX.
# Results, logs, and work files mirror the original corpus paths.
set -Euo pipefail

CORPUS="."
BUILD="build"
JOBS=2
TIME_LIMIT=180
FORCE=0
WORKER=0

usage() {
  printf '%s\n' \
    "Usage: $0 [--corpus DIR] [--build DIR] [--jobs N] [--timeout SEC] [--force]" \
    "" \
    "Discovers *.tex files beneath CORPUS/sources that contain \\documentclass." \
    "Successful PDFs are written beneath BUILD/pdfs; logs beneath BUILD/logs." \
    "Existing PDFs newer than their TeX root are recorded as cached unless --force is used."
}

while (($#)); do
  case "$1" in
    --corpus) CORPUS=$2; shift 2 ;;
    --build) BUILD=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --timeout) TIME_LIMIT=$2; shift 2 ;;
    --force) FORCE=1; shift ;;
    --worker) WORKER=1; CORPUS=$2; BUILD=$3; TIME_LIMIT=$4; FORCE=$5; shift 5; break ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

compile_one() {
  local source=$1 rel stem source_dir source_name work_dir pdf log status pages started elapsed tmp_log
  rel=${source#"$CORPUS"/}
  stem=${rel%.tex}
  source_dir=$(dirname "$source")
  source_name=$(basename "$source")
  work_dir="$BUILD/work/$stem"
  pdf="$BUILD/pdfs/$stem.pdf"
  log="$BUILD/logs/$stem.log"
  mkdir -p "$work_dir" "$(dirname "$pdf")" "$(dirname "$log")"
  started=$(date +%s)
  status="failed"
  pages=0

  if [[ -s "$pdf" && "$pdf" -nt "$source" && "$FORCE" -eq 0 ]]; then
    status="cached"
  else
    tmp_log="$log.tmp.$$"
    : > "$tmp_log"
    (
      cd "$source_dir" || exit 1
      timeout --signal=TERM --kill-after=15 "$TIME_LIMIT" \
        lualatex -interaction=nonstopmode -halt-on-error -file-line-error \
        -output-directory="$(realpath "$work_dir")" "$source_name" &&
      timeout --signal=TERM --kill-after=15 "$TIME_LIMIT" \
        lualatex -interaction=nonstopmode -halt-on-error -file-line-error \
        -output-directory="$(realpath "$work_dir")" "$source_name"
    ) > "$tmp_log" 2>&1
    code=$?
    mv "$tmp_log" "$log"
    built="$work_dir/${source_name%.tex}.pdf"
    if ((code == 0)) && [[ -s "$built" ]]; then
      cp -p "$built" "$pdf"
      status="success"
    elif ((code == 124 || code == 137)); then
      status="timeout"
      rm -f "$pdf"
    else
      rm -f "$pdf"
    fi
  fi

  if [[ -s "$pdf" ]] && command -v pdfinfo >/dev/null; then
    pages=$(pdfinfo "$pdf" 2>/dev/null | awk '/^Pages:/ {print $2; exit}')
    pages=${pages:-0}
  fi
  elapsed=$(( $(date +%s) - started ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$rel" "$pdf" "$log" "$pages" "$elapsed" \
    | flock "$BUILD/compile-manifest.lock" tee -a "$BUILD/compile-manifest.tsv" >/dev/null
  printf '%-7s %s\n' "$status" "$rel" >&2
}

if ((WORKER)); then
  compile_one "$1"
  exit 0
fi

for cmd in rg lualatex timeout realpath flock; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 1; }
done
[[ -d "$CORPUS/sources" ]] || { printf 'Sources directory not found: %s/sources\n' "$CORPUS" >&2; exit 1; }
CORPUS=$(realpath "$CORPUS")
mkdir -p "$BUILD"
BUILD=$(realpath "$BUILD")
printf 'status\tsource\tpdf\tlog\tpages\telapsed_seconds\n' > "$BUILD/compile-manifest.tsv"

export SCRIPT_PATH="$(realpath "$0")"
export CORPUS BUILD TIME_LIMIT FORCE
rg -l -0 '\\documentclass(?:\[[^]]*\])?\{' "$CORPUS/sources" -g '*.tex' |
  xargs -0 -r -n 1 -P "$JOBS" bash "$SCRIPT_PATH" --worker "$CORPUS" "$BUILD" "$TIME_LIMIT" "$FORCE"

rm -f "$BUILD/compile-manifest.lock"
awk -F '\t' 'NR>1 {count[$1]++} END {for (s in count) print count[s],s}' \
  "$BUILD/compile-manifest.tsv" | sort -nr
