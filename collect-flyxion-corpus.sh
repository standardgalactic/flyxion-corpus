#!/usr/bin/env bash
# Collect every TeX source listed by flyxion-inventory.sh into one provenance-
# preserving Git working tree. Reuses the inventory cache; downloads only when
# explicitly requested.
set -Euo pipefail

INVENTORY="flyxion-inventory/inventory.tsv"
CACHE_DIR="flyxion-inventory/cache"
DEST="flyxion-corpus"
DOWNLOAD_MISSING=0
FORCE=0
INIT_GIT=1
COMMIT=0

usage() {
  printf '%s\n' \
    "Usage: $0 [options]" \
    "" \
    "  --inventory FILE       Inventory TSV (default: $INVENTORY)" \
    "  --cache DIR            Inventory content cache (default: $CACHE_DIR)" \
    "  --dest DIR             Corpus directory (default: $DEST)" \
    "  --download-missing     Fetch files absent from the local cache" \
    "  --force                Replace differing destination files" \
    "  --no-git               Do not initialize a Git repository" \
    "  --commit               Stage and commit the collected corpus" \
    "  -h, --help             Show this help"
}

while (($#)); do
  case "$1" in
    --inventory) INVENTORY=$2; shift 2 ;;
    --cache) CACHE_DIR=$2; shift 2 ;;
    --dest) DEST=$2; shift 2 ;;
    --download-missing) DOWNLOAD_MISSING=1; shift ;;
    --force) FORCE=1; shift ;;
    --no-git) INIT_GIT=0; shift ;;
    --commit) COMMIT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for cmd in awk sed sha256sum cmp cp mkdir; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 1; }
done
[[ -f "$INVENTORY" ]] || { printf 'Inventory not found: %s\n' "$INVENTORY" >&2; exit 1; }

if ((DOWNLOAD_MISSING)); then
  command -v gh >/dev/null || { printf 'Missing command: gh\n' >&2; exit 1; }
  gh auth status >/dev/null || exit 1
fi
if ((INIT_GIT || COMMIT)); then
  command -v git >/dev/null || { printf 'Missing command: git\n' >&2; exit 1; }
fi

mkdir -p "$DEST/sources" "$DEST/metadata"
MANIFEST="$DEST/metadata/collection-manifest.tsv"
ROOTS="$DEST/metadata/root-candidates.tsv"
ERRORS="$DEST/metadata/collection-errors.log"
printf 'status\tclassification\trepository\toriginal_path\tcorpus_path\ttitle\tdocumentclass\tword_count\tcontent_hash\tsource_url\n' > "$MANIFEST"
printf 'repository\toriginal_path\tcorpus_path\ttitle\tdocumentclass\tclassification\tword_count\n' > "$ROOTS"
: > "$ERRORS"

total=$(awk -F '\t' 'NR>1{n++}END{print n+0}' "$INVENTORY")
index=0 copied=0 unchanged=0 missing=0 conflicts=0 failed=0

while IFS=$'\034' read -r classification repo path title docclass words content_hash url reasons; do
  [[ -n "$repo" && -n "$path" ]] || continue
  ((index+=1))
  printf '[%s/%s] %s/%s\n' "$index" "$total" "$repo" "$path" >&2

  cache_key=$(printf '%s/%s' "$repo" "$path" | sha256sum | awk '{print $1}')
  source_file="$CACHE_DIR/$cache_key.tex"
  corpus_rel="sources/$repo/$path"
  destination="$DEST/$corpus_rel"
  status=""

  if [[ ! -s "$source_file" ]] && ((DOWNLOAD_MISSING)); then
    mkdir -p "$CACHE_DIR"
    ref=$(printf '%s' "$url" | sed -n 's#^https://github.com/[^/]*/[^/]*/blob/\([^/]*\)/.*#\1#p')
    tmp="$source_file.tmp"
    if [[ -n "$ref" ]]; then
      gh api --method GET -H 'Accept: application/vnd.github.raw+json' \
        "repos/$repo/contents/$path" -f ref="$ref" > "$tmp" 2>>"$ERRORS"
    else
      gh api -H 'Accept: application/vnd.github.raw+json' \
        "repos/$repo/contents/$path" > "$tmp" 2>>"$ERRORS"
    fi
    if [[ -s "$tmp" ]]; then
      mv "$tmp" "$source_file"
    else
      rm -f "$tmp"
    fi
  fi

  if [[ ! -s "$source_file" ]]; then
    status="missing-cache"
    ((missing+=1))
    printf 'Missing cached source: %s/%s\n' "$repo" "$path" >> "$ERRORS"
  else
    mkdir -p "$(dirname "$destination")"
    if [[ ! -e "$destination" ]]; then
      cp -p "$source_file" "$destination"
      status="copied"
      ((copied+=1))
    elif cmp -s "$source_file" "$destination"; then
      status="unchanged"
      ((unchanged+=1))
    elif ((FORCE)); then
      cp -p "$source_file" "$destination"
      status="replaced"
      ((copied+=1))
    else
      status="conflict-kept"
      ((conflicts+=1))
      printf 'Destination differs; kept existing file: %s\n' "$destination" >> "$ERRORS"
    fi
  fi

  clean_title=$(printf '%s' "$title" | tr '\t\r\n' '   ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$status" "$classification" "$repo" "$path" "$corpus_rel" "$clean_title" \
    "$docclass" "$words" "$content_hash" "$url" >> "$MANIFEST"

  if [[ -n "$docclass" && "$classification" != "chapter" && "$classification" != "fragment" && "$classification" != "citation-only" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$path" "$corpus_rel" "$clean_title" "$docclass" "$classification" "$words" >> "$ROOTS"
  fi
done < <(awk -F '\t' -v OFS='\034' 'NR>1 {print $1,$2,$3,$4,$5,$6,$7,$8,$9}' "$INVENTORY")

cp "$INVENTORY" "$DEST/metadata/source-inventory.tsv"

{
  printf '# Flyxion TeX Corpus\n\n'
  printf 'This working tree was assembled from `%s`. Original repository and path provenance is preserved beneath `sources/OWNER/REPOSITORY/`.\n\n' "$(basename "$INVENTORY")"
  printf 'Collected files: %s  \n' "$copied"
  printf 'Already identical: %s  \n' "$unchanged"
  printf 'Missing from cache: %s  \n' "$missing"
  printf 'Conflicts retained: %s  \n\n' "$conflicts"
  printf 'Compilation has not been attempted. `metadata/root-candidates.tsv` lists likely root documents containing a document class. Modular documents may still require files that did not contain the searched author name and therefore were not part of the original inventory.\n'
} > "$DEST/README.md"

if ((INIT_GIT)) && [[ ! -d "$DEST/.git" ]]; then
  git -C "$DEST" init -b main >/dev/null
fi

if ((COMMIT)); then
  git -C "$DEST" add README.md metadata sources
  if ! git -C "$DEST" diff --cached --quiet; then
    git -C "$DEST" commit -m "Assemble Flyxion TeX corpus from provenance inventory"
  else
    printf 'Nothing new to commit.\n' >&2
  fi
fi

printf 'Corpus ready: %s\nCopied/replaced: %s\nUnchanged: %s\nMissing: %s\nConflicts kept: %s\n' \
  "$DEST" "$copied" "$unchanged" "$missing" "$conflicts"

