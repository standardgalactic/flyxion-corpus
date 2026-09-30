#!/usr/bin/env bash
set -uo pipefail

INPUT="${1:-matched-txt-mp3.tsv}"
OUTDIR="${2:-transcripts}"

mkdir -p "$OUTDIR"

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: input file not found: $INPUT" >&2
    exit 1
fi

total=0
downloaded=0
skipped=0
failed=0

# Columns:
# repo    directory    basename    txt    mp3
#
# Skip the header, then read the exact repository and TXT path
# produced by the previous scan.
tail -n +2 "$INPUT" |
while IFS=$'\t' read -r repo directory basename txt mp3; do
    [[ -n "$repo" && -n "$txt" ]] || continue

    ((total++))

    # repo is something like:
    #   standardgalactic/alphabet
    #
    # Strip the owner so the local tree begins with the repo name.
    reponame="${repo#*/}"

    outfile="$OUTDIR/$reponame/$txt"

    mkdir -p "$(dirname "$outfile")"

    # Makes the script resumable.
    if [[ -s "$outfile" ]]; then
        echo "SKIP: $outfile" >&2
        ((skipped++))
        continue
    fi

    echo "Downloading $repo/$txt ..." >&2

    # Ask GitHub for the file contents directly.
    #
    # --method GET plus the contents endpoint avoids cloning entire
    # repositories just to retrieve one text file.
    if gh api \
        -H 'Accept: application/vnd.github.raw+json' \
        "repos/$repo/contents/$txt" \
        > "$outfile" 2>/dev/null
    then
        ((downloaded++))
    else
        echo "  WARNING: could not download $repo/$txt" >&2
        rm -f "$outfile"
        ((failed++))
    fi
done

echo >&2
echo "Finished." >&2
echo "Output directory: $OUTDIR" >&2

# Count what actually exists rather than relying on counters inside
# the pipeline subshell.
echo -n "TXT files present: " >&2
find "$OUTDIR" -type f -name '*.txt' | wc -l >&2
