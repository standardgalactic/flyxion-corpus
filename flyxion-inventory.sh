#!/usr/bin/env bash
# Deliberately omit `set -e`: one malformed or inaccessible file must not abort
# an inventory that may span thousands of repositories.
set -Euo pipefail

# Inventory TeX works attributed to Flyxion across a chosen list of GitHub repos.
# Requires: gh, jq, awk, sed, perl, sha256sum

OWNER="standardgalactic"
REPO_FILE="repos.txt"
OUT_DIR="flyxion-inventory"
NAME_RE='Flyxion'
SEARCH_LIMIT=1000
SEARCH_DELAY=7
SEARCH_RETRIES=6

usage() {
  printf '%s\n' \
    "Usage: $0 [--owner USER] [--repos FILE] [--out DIR] [--name REGEX] [--search-delay SECONDS]" \
    "" \
    "repos.txt accepts one repository per line, as either NAME or OWNER/NAME." \
    "Blank lines and lines beginning with # are ignored." \
    "Use --make-contribution-repo-list for repos with recognized commit contributions." \
    "Use --make-owned-repo-list for every repository owned by USER." \
    "" \
    "Examples:" \
    "  $0 --make-contribution-repo-list" \
    "  $0 --repos repos.txt" \
    "  $0 --repos repos.txt --name 'Flyxion|Nate Guimond'"
}

MAKE_OWNED_REPO_LIST=0
MAKE_CONTRIBUTION_REPO_LIST=0
while (($#)); do
  case "$1" in
    --owner) OWNER=$2; shift 2 ;;
    --repos) REPO_FILE=$2; shift 2 ;;
    --out) OUT_DIR=$2; shift 2 ;;
    --name) NAME_RE=$2; shift 2 ;;
    --search-delay) SEARCH_DELAY=$2; shift 2 ;;
    --make-contribution-repo-list) MAKE_CONTRIBUTION_REPO_LIST=1; shift ;;
    --make-owned-repo-list|--make-repo-list) MAKE_OWNED_REPO_LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for cmd in gh jq awk sed perl sha256sum; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 1; }
done
gh auth status >/dev/null

if ((MAKE_OWNED_REPO_LIST)); then
  gh repo list "$OWNER" --limit 100000 --json nameWithOwner --jq '.[].nameWithOwner' > "$REPO_FILE"
  printf 'Wrote %s repositories to %s\n' "$(wc -l < "$REPO_FILE")" "$REPO_FILE"
  exit 0
fi

if ((MAKE_CONTRIBUTION_REPO_LIST)); then
  # GitHub caps commitContributionsByRepository at 100 repositories for one
  # ContributionsCollection. Query one calendar month at a time to reduce loss,
  # then merge and deduplicate the results. A warning is emitted whenever a
  # month reaches the cap.
  query='query($login:String!,$from:DateTime!,$to:DateTime!){user(login:$login){contributionsCollection(from:$from,to:$to){commitContributionsByRepository(maxRepositories:100){repository{nameWithOwner}}}}}'
  created=$(gh api graphql -f query='query($login:String!){user(login:$login){createdAt}}' -F login="$OWNER" --jq '.data.user.createdAt')
  cursor=$(date -u -d "${created%%T*}" +%Y-%m-01)
  current=$(date -u +%Y-%m-01)
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT

  while [[ "$cursor" < "$current" || "$cursor" == "$current" ]]; do
    next=$(date -u -d "$cursor +1 month" +%Y-%m-01)
    from="${cursor}T00:00:00Z"
    to=$(date -u -d "$next -1 second" +%Y-%m-%dT%H:%M:%SZ)
    printf 'Reading commit contributions for %s ...\n' "${cursor:0:7}" >&2
    response=$(gh api graphql -f query="$query" -F login="$OWNER" -F from="$from" -F to="$to")
    count=$(jq '.data.user.contributionsCollection.commitContributionsByRepository | length' <<< "$response")
    jq -r '.data.user.contributionsCollection.commitContributionsByRepository[].repository.nameWithOwner' <<< "$response" >> "$tmp"
    if ((count == 100)); then
      printf 'Warning: %s reached GitHub’s 100-repository cap; some repositories may be absent.\n' "${cursor:0:7}" >&2
    fi
    cursor=$next
  done

  sort -fu "$tmp" > "$REPO_FILE"
  printf 'Wrote %s contributed-to repositories to %s\n' "$(wc -l < "$REPO_FILE")" "$REPO_FILE"
  exit 0
fi

[[ -f "$REPO_FILE" ]] || {
  printf 'Repository list not found: %s\nRun %s --make-contribution-repo-list first.\n' "$REPO_FILE" "$0" >&2
  exit 1
}

mkdir -p "$OUT_DIR/cache" "$OUT_DIR/search-cache"
RAW="$OUT_DIR/inventory.raw.tsv"
FINAL="$OUT_DIR/inventory.tsv"
TITLES="$OUT_DIR/unique-titles.tsv"
SUMMARY="$OUT_DIR/summary.txt"
ERRORS="$OUT_DIR/errors.log"
: > "$RAW"
: > "$ERRORS"
printf 'classification\trepository\tpath\ttitle\tdocumentclass\tword_count\tcontent_hash\turl\treasons\n' > "$FINAL"

classify() {
  local path_lc=$1 body_lc=$2 title=$3 docclass=$4
  local class="standalone" reasons=""

  if [[ "$path_lc" =~ (^|/)(build|build_artifacts|out|output|dist|tmp|cache)(/|$) ]] ||
     [[ "$path_lc" =~ \.(aux|log|toc|out|fdb_latexmk|fls)($|\.) ]]; then
    class="build-artifact"; reasons="build/output path or extension"
  elif [[ "$path_lc" =~ (^|/)(chapters?|sections?|appendices?)(/|$) ]] ||
       [[ "$path_lc" =~ (^|/)(ch|chapter|sec|section)[_-]?[0-9ivxlc]+[^/]*\.tex$ ]] ||
       { [[ -z "$title" && -z "$docclass" ]] && [[ "$body_lc" =~ \\chapter\{|\\section\{ ]]; }; then
    class="chapter"; reasons="chapter/section path or fragment without document title"
  elif [[ "$path_lc" =~ (draft|unfinished|wip|working|notes?|scratch|placeholder|template|outline|todo) ]] ||
       [[ "$body_lc" =~ (placeholder|work[[:space:]-]in[[:space:]-]progress|unfinished|internal[[:space:]]working[[:space:]]document|not[[:space:]]for[[:space:]]distribution) ]]; then
    class="draft"; reasons="draft/placeholder language or path"
  elif [[ -z "$title" && -z "$docclass" ]]; then
    class="fragment"; reasons="no title and no documentclass"
  elif [[ -z "$title" ]]; then
    class="untitled-document"; reasons="documentclass present but no title found"
  elif [[ ! "$body_lc" =~ \\author\{[^}]*flyxion ]] && [[ "$body_lc" =~ (bibitem|cite|bibliography) ]]; then
    class="citation-only"; reasons="name appears in citation but not author field"
  fi
  # The newline matters: `read` returns failure at EOF without a delimiter,
  # which formerly caused the script to exit on its first classified file.
  printf '%s\t%s\n' "$class" "$reasons"
}

extract_title() {
  perl -0777 -ne '
    if (/\\title\s*\{((?:[^{}]+|\{[^{}]*\})*)\}/s) {
      $t=$1; $t=~s/\\\\/ /g; $t=~s/\\(?:textbf|textit|emph|large|Large|LARGE)\s*\{//g;
      $t=~s/[{}]//g; $t=~s/\\[a-zA-Z@]+\*?(?:\[[^]]*\])?//g; $t=~s/\s+/ /g;
      $t=~s/^\s+|\s+$//g; print $t;
    }' "$1"
}

search_repository() {
  local repo=$1 cache_file=$2 attempt=1 err_file
  err_file=$(mktemp)

  if [[ -s "$cache_file" ]] && jq -e 'type == "array"' "$cache_file" >/dev/null 2>&1; then
    cat "$cache_file"
    rm -f "$err_file"
    return 0
  fi

  while ((attempt <= SEARCH_RETRIES)); do
    # Authenticated code search is tightly rate-limited. Seven seconds keeps
    # ordinary runs below ten searches per minute; retries cover secondary
    # limits and transient network/API failures.
    if ((SEARCH_DELAY > 0)); then
      printf '  Waiting %ss for code-search quota ...\n' "$SEARCH_DELAY" >&2
      sleep "$SEARCH_DELAY"
    fi

    if gh search code "$NAME_RE" --repo "$repo" --extension tex \
        --limit "$SEARCH_LIMIT" --json path,url > "$cache_file.tmp" 2>"$err_file" &&
       jq -e 'type == "array"' "$cache_file.tmp" >/dev/null 2>&1; then
      mv "$cache_file.tmp" "$cache_file"
      cat "$cache_file"
      rm -f "$err_file"
      return 0
    fi

    rm -f "$cache_file.tmp"
    printf 'Search attempt %s/%s failed for %s: %s\n' \
      "$attempt" "$SEARCH_RETRIES" "$repo" "$(tr '\n' ' ' < "$err_file")" >> "$ERRORS"
    printf '  Search failed; retrying (%s/%s) ...\n' "$attempt" "$SEARCH_RETRIES" >&2
    sleep $((attempt * 10))
    ((attempt+=1))
  done

  rm -f "$err_file"
  return 1
}

repo_total=$(sed 's/#.*//; /^[[:space:]]*$/d' "$REPO_FILE" | wc -l)
repo_index=0
while IFS= read -r repo || [[ -n "$repo" ]]; do
  repo=${repo%%#*}
  repo=$(printf '%s' "$repo" | xargs)
  [[ -n "$repo" ]] || continue
  [[ "$repo" == */* ]] || repo="$OWNER/$repo"
  ((repo_index+=1))
  printf '[%s/%s] Searching %s ...\n' "$repo_index" "$repo_total" "$repo" >&2

  search_key=$(printf '%s\n%s\n%s\n' "$repo" "$NAME_RE" "$SEARCH_LIMIT" | sha256sum | awk '{print $1}')
  search_cache="$OUT_DIR/search-cache/$search_key.json"
  if ! results=$(search_repository "$repo" "$search_cache"); then
    printf 'Search permanently failed after %s attempts: %s\n' "$SEARCH_RETRIES" "$repo" >> "$ERRORS"
    continue
  fi

  match_count=$(jq 'length' <<< "$results" 2>>"$ERRORS" || printf '0')
  printf '  Found %s matching TeX files\n' "$match_count" >&2

  jq -r '.[] | [.path,.url] | @tsv' <<< "$results" |
  while IFS=$'\t' read -r path url; do
    printf '  Processing %s\n' "$path" >&2
    key=$(printf '%s/%s' "$repo" "$path" | sha256sum | awk '{print $1}')
    file="$OUT_DIR/cache/$key.tex"
    if [[ ! -s "$file" ]]; then
      if ! gh api -H 'Accept: application/vnd.github.raw+json' "repos/$repo/contents/$path" > "$file" 2>>"$ERRORS"; then
        printf 'Fetch failed: %s/%s\n' "$repo" "$path" >> "$ERRORS"
        continue
      fi
    fi

    title=$(extract_title "$file")
    docclass=$(perl -ne 'if (/\\documentclass(?:\[[^]]*\])?\{([^}]+)\}/) { print $1; exit }' "$file")
    body_lc=$(tr '[:upper:]' '[:lower:]' < "$file")
    path_lc=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
    classification="unclassified"
    reasons="classifier failure"
    if IFS=$'\t' read -r classification reasons < <(classify "$path_lc" "$body_lc" "$title" "$docclass"); then
      :
    else
      printf 'Classifier failed: %s/%s\n' "$repo" "$path" >> "$ERRORS"
    fi
    words=$(sed 's/%.*$//' "$file" | sed 's/\\[A-Za-z@]*\*\?\(\[[^]]*\]\)\?//g; s/[{}$]//g' | wc -w)
    hash=$(sed 's/%.*$//' "$file" | tr -d '[:space:]' | sha256sum | awk '{print $1}')
    clean_title=$(printf '%s' "$title" | tr '\t\r\n' '   ')
    clean_reasons=$(printf '%s' "$reasons" | tr '\t\r\n' '   ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$classification" "$repo" "$path" "$clean_title" "$docclass" "$words" "$hash" "$url" "$clean_reasons" >> "$RAW"
  done
done < "$REPO_FILE"

sort -t $'\t' -k1,1 -k2,2 -k3,3 "$RAW" >> "$FINAL"

awk -F '\t' 'BEGIN { OFS="\t"; print "normalized_title","display_title","classification","occurrences","example" }
  {
    key=tolower($4); gsub(/[^[:alnum:]]+/," ",key); gsub(/^ +| +$/,"",key)
    if (key=="") next
    count[key]++; if (!(key in title)) { title[key]=$4; class[key]=$1; example[key]=$2 "/" $3 }
  }
  END { for (key in count) print key,title[key],class[key],count[key],example[key] }
' "$RAW" | sort -t $'\t' -k3,3 -k2,2 > "$TITLES"

{
  printf 'Flyxion TeX inventory\n\n'
  printf 'Candidate files: %s\n' "$(wc -l < "$RAW")"
  printf 'Unique nonempty normalized titles: %s\n\n' "$(( $(wc -l < "$TITLES") - 1 ))"
  printf 'Classification counts:\n'
  cut -f1 "$RAW" | sort | uniq -c | sort -nr
  printf '\nReview standalone, untitled-document, and draft rows manually before treating them as unique works.\n'
  printf 'GitHub code search returns at most %s matches per repository/query.\n' "$SEARCH_LIMIT"
} > "$SUMMARY"

printf 'Done. Review:\n  %s\n  %s\n  %s\n' "$FINAL" "$TITLES" "$SUMMARY"

