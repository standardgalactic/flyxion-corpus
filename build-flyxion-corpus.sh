#!/usr/bin/env bash
# Run compilation, PDF-to-text extraction, and analysis in sequence.
set -Euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CORPUS="."
BUILD="build"
JOBS=2
TIME_LIMIT=180
FORCE_ARGS=()

while (($#)); do
  case "$1" in
    --corpus) CORPUS=$2; shift 2 ;;
    --build) BUILD=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --timeout) TIME_LIMIT=$2; shift 2 ;;
    --force) FORCE_ARGS+=(--force); shift ;;
    -h|--help)
      printf 'Usage: %s [--corpus DIR] [--build DIR] [--jobs N] [--timeout SEC] [--force]\n' "$0"
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

"$SCRIPT_DIR/compile-flyxion-corpus.sh" --corpus "$CORPUS" --build "$BUILD" --jobs "$JOBS" --timeout "$TIME_LIMIT" "${FORCE_ARGS[@]}" || exit $?
"$SCRIPT_DIR/extract-flyxion-text.sh" --build "$BUILD" "${FORCE_ARGS[@]}" || exit $?
"$SCRIPT_DIR/analyze-flyxion-build.sh" --build "$BUILD"
