#!/usr/bin/env bash
set -euo pipefail

OWNER="${1:-standardgalactic}"
OUT="${2:-matched-txt-mp3.tsv}"

printf 'repo\tdirectory\tbasename\ttxt\tmp3\n' > "$OUT"

gh api --paginate \
  -H 'Accept: application/vnd.github+json' \
  "/users/$OWNER/repos?per_page=100&type=owner&sort=full_name" \
  --jq '.[] | select(.fork == false) | [.full_name, .default_branch] | @tsv' |
while IFS=$'\t' read -r repo branch; do
    [[ -n "$branch" ]] || continue

    echo "Scanning $repo ..." >&2

    tree=$(
        gh api \
            "repos/$repo/git/trees/$branch?recursive=1" \
            --paginate \
            --jq '.tree[] | select(.type == "blob") | .path' \
            2>/dev/null
    ) || {
        echo "  WARNING: could not read $repo" >&2
        continue
    }

    # Make a lookup set of every path in the repository.
    declare -A paths=()
    while IFS= read -r path; do
        paths["$path"]=1
    done <<< "$tree"

    while IFS= read -r txt; do
        [[ "$txt" == *.txt ]] || continue

        stem="${txt%.txt}"
        mp3="${stem}.mp3"

        if [[ -n "${paths[$mp3]+x}" ]]; then
            dir="${txt%/*}"
            [[ "$dir" == "$txt" ]] && dir="."

            base="${stem##*/}"

            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$repo" "$dir" "$base" "$txt" "$mp3" >> "$OUT"
        fi
    done <<< "$tree"

    unset paths
done

echo >&2
echo "Results: $OUT" >&2
echo -n "Matched pairs: " >&2
tail -n +2 "$OUT" | wc -l >&2
