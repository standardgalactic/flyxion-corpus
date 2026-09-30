#!/usr/bin/env bash
set -Eeuo pipefail

# Build a cached Markdown overview of a repository with local Ollama models.
# granite4.1:3b summarizes individual source files; granite4.1:8b performs
# directory-level and repository-level synthesis.

SMALL_MODEL="${SMALL_MODEL:-granite4.1:3b}"
LARGE_MODEL="${LARGE_MODEL:-granite4.1:8b}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
OUTPUT_DIR="${OUTPUT_DIR:-.repo-overview}"
MAX_FILE_CHARS="${MAX_FILE_CHARS:-16000}"
MAX_DIRECTORY_CHARS="${MAX_DIRECTORY_CHARS:-60000}"
MAX_REPOSITORY_CHARS="${MAX_REPOSITORY_CHARS:-100000}"
FORCE=0

usage() {
  printf '%s\n' \
    "Usage: $0 [--force] [--output DIR]" \
    "" \
    "Environment overrides:" \
    "  SMALL_MODEL=$SMALL_MODEL" \
    "  LARGE_MODEL=$LARGE_MODEL" \
    "  OLLAMA_URL=$OLLAMA_URL" \
    "  MAX_FILE_CHARS=$MAX_FILE_CHARS" \
    "  MAX_DIRECTORY_CHARS=$MAX_DIRECTORY_CHARS" \
    "  MAX_REPOSITORY_CHARS=$MAX_REPOSITORY_CHARS"
}

while (($#)); do
  case "$1" in
    --force) FORCE=1; shift ;;
    --output) OUTPUT_DIR="${2:?--output requires a directory}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for command_name in git curl jq sha256sum find sort sed awk mktemp; do
  command -v "$command_name" >/dev/null || {
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
cd "$ROOT"

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;;
esac

CACHE_DIR="$OUTPUT_DIR/cache"
FILE_DIR="$OUTPUT_DIR/files"
PROJECT_DIR="$OUTPUT_DIR/projects"
mkdir -p "$CACHE_DIR" "$FILE_DIR" "$PROJECT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

clean_text() {
  # Remove ANSI/terminal control sequences and non-printing carriage returns.
  LC_ALL=C sed -E \
    -e $'s/\x1B\[[0-?]*[ -/]*[@-~]//g' \
    -e $'s/\x1B\][^\x07]*\x07//g' \
    -e $'s/\x1B\][^\x1B]*\x1B\\\\//g' \
    -e 's/\r$//' |
    LC_ALL=C tr -cd '\11\12\15\40-\176\200-\377'
}

ollama_generate() {
  local model="$1" prompt_file="$2" destination="$3"
  local payload="$TMP_DIR/payload.json"
  jq -n \
    --arg model "$model" \
    --rawfile prompt "$prompt_file" \
    '{model:$model, prompt:$prompt, stream:false,
      options:{temperature:0.15, num_ctx:32768, num_predict:1600}}' > "$payload"

  curl --fail --silent --show-error \
    --connect-timeout 10 --max-time 1800 \
    -H 'Content-Type: application/json' \
    --data-binary "@$payload" "$OLLAMA_URL/api/generate" |
    jq -er '.response' | clean_text > "$destination"

  [[ -s "$destination" ]] || {
    printf 'Ollama returned an empty response for %s\n' "$prompt_file" >&2
    return 1
  }
}

printf 'Checking Ollama and models...\n'
model_list="$(curl --fail --silent --show-error --connect-timeout 5 "$OLLAMA_URL/api/tags")"
for required_model in "$SMALL_MODEL" "$LARGE_MODEL"; do
  jq -e --arg model "$required_model" \
    '.models[]? | select(.name == $model or (.name | startswith($model + ":")))' \
    >/dev/null <<<"$model_list" || {
      printf 'Ollama model is not installed: %s\n' "$required_model" >&2
      exit 1
    }
done

is_supported() {
  case "${1,,}" in
    *.md|*.markdown|*.txt|*.tex|*.bib|*.lean|*.rs|*.toml|*.yaml|*.yml|*.json|*.jsonl|\
    *.sh|*.bash|*.py|*.js|*.ts|*.tsx|*.jsx|*.html|*.css|*.scss|*.sql|*.csv|*.tsv|\
    *.c|*.h|*.cpp|*.hpp|*.go|*.java|*.rb|*.php|*.lua|*.xml|*.ini|*.cfg|*.conf|\
    */README|README|*/LICENSE|LICENSE|*/Makefile|Makefile|*/Dockerfile|Dockerfile|\
    *.pdf) return 0 ;;
    *) return 1 ;;
  esac
}

extract_text() {
  local path="$1"
  if [[ "${path,,}" == *.pdf ]]; then
    if command -v pdftotext >/dev/null; then
      pdftotext -layout -- "$path" - 2>/dev/null | clean_text
    else
      printf '[PDF omitted because pdftotext is unavailable: %s]\n' "$path"
    fi
  else
    clean_text < "$path"
  fi
}

# Use Git's view of the repository so .gitignore is authoritative. This includes
# tracked and relevant untracked files, but excludes caches, builds, and file-list.txt.
git ls-files -co --exclude-standard -z > "$TMP_DIR/all-files.z"
: > "$TMP_DIR/files.z"
while IFS= read -r -d '' path; do
  [[ -f "$path" ]] || continue
  [[ "$path" == "${OUTPUT_DIR#"$ROOT"/}"/* ]] && continue
  is_supported "$path" && printf '%s\0' "$path" >> "$TMP_DIR/files.z"
done < "$TMP_DIR/all-files.z"

file_count="$(awk 'BEGIN{RS="\0"} NF{n++} END{print n+0}' "$TMP_DIR/files.z")"
printf 'Summarizing %s supported files with %s...\n' "$file_count" "$SMALL_MODEL"

: > "$TMP_DIR/manifest.tsv"
current=0
while IFS= read -r -d '' path; do
  current=$((current + 1))
  content_file="$TMP_DIR/content.txt"
  extract_text "$path" | head -c "$MAX_FILE_CHARS" > "$content_file"
  content_hash="$(sha256sum "$content_file" | awk '{print $1}')"
  cache_key="$(printf '%s\0%s\0%s\0v2' "$SMALL_MODEL" "$path" "$content_hash" | sha256sum | awk '{print $1}')"
  cached="$CACHE_DIR/file-$cache_key.md"

  if ((FORCE)) || [[ ! -s "$cached" ]]; then
    prompt="$TMP_DIR/prompt.txt"
    {
      printf 'You are inventorying a research and software repository.\n'
      printf 'Summarize the file faithfully and compactly. State its purpose, principal ideas or behavior, important dependencies or outputs, and whether it appears complete, generated, duplicated, or problematic. Do not invent facts. Use a short Markdown heading followed by prose, not a checklist.\n\n'
      printf 'Repository path: %s\n\n' "$path"
      printf '%s\n' '--- BEGIN FILE ---'
      cat "$content_file"
      printf '\n%s\n' '--- END FILE ---'
    } > "$prompt"
    printf '[%s/%s] %s\n' "$current" "$file_count" "$path"
    ollama_generate "$SMALL_MODEL" "$prompt" "$cached"
  else
    printf '[%s/%s] cached: %s\n' "$current" "$file_count" "$path"
  fi

  output_name="$(printf '%s' "$path" | sha256sum | awk '{print substr($1,1,16)}')-$(basename "$path").md"
  cp -- "$cached" "$FILE_DIR/$output_name"
  printf '%s\t%s\t%s\n' "$path" "$output_name" "$content_hash" >> "$TMP_DIR/manifest.tsv"
done < "$TMP_DIR/files.z"

{
  printf '# Flyxion Corpus Inventory\n\n'
  printf 'Generated with `%s` for file summaries and `%s` for synthesis.\n\n' "$SMALL_MODEL" "$LARGE_MODEL"
  printf '| Source | Summary | Content hash |\n|---|---|---|\n'
  while IFS=$'\t' read -r path output_name content_hash; do
    safe_path="${path//|/\\|}"
    printf '| `%s` | [%s](files/%s) | `%s` |\n' \
      "$safe_path" "$(basename "$path")" "$output_name" "${content_hash:0:12}"
  done < "$TMP_DIR/manifest.tsv"
} > "$OUTPUT_DIR/INVENTORY.md"

# Group file summaries by the first path component, treating root files as one project.
cut -f1 "$TMP_DIR/manifest.tsv" | awk '
  index($0,"/"){split($0,a,"/"); print a[1]; next}
  {print "_root"}
' | sort -u > "$TMP_DIR/projects.txt"

printf 'Synthesizing project overviews with %s...\n' "$LARGE_MODEL"
: > "$TMP_DIR/project-manifest.tsv"
while IFS= read -r project; do
  bundle="$TMP_DIR/project-bundle.md"
  : > "$bundle"
  while IFS=$'\t' read -r path output_name _hash; do
    if { [[ "$project" == _root ]] && [[ "$path" != */* ]]; } || [[ "$path" == "$project/"* ]]; then
      printf '\n## %s\n\n' "$path" >> "$bundle"
      cat "$FILE_DIR/$output_name" >> "$bundle"
    fi
  done < "$TMP_DIR/manifest.tsv"
  head -c "$MAX_DIRECTORY_CHARS" "$bundle" > "$TMP_DIR/project-input.md"
  project_hash="$(sha256sum "$TMP_DIR/project-input.md" | awk '{print $1}')"
  cache_key="$(printf '%s\0%s\0%s\0v2' "$LARGE_MODEL" "$project" "$project_hash" | sha256sum | awk '{print $1}')"
  cached="$CACHE_DIR/project-$cache_key.md"
  if ((FORCE)) || [[ ! -s "$cached" ]]; then
    {
      printf 'Synthesize these file summaries into a coherent overview of the repository project named "%s". Explain what it is, how its pieces relate, its main research or engineering contributions, and visible incompleteness or duplication. Preserve uncertainty. Write polished Markdown prose with useful headings and no generic filler.\n\n' "$project"
      cat "$TMP_DIR/project-input.md"
    } > "$TMP_DIR/project-prompt.txt"
    printf 'Project: %s\n' "$project"
    ollama_generate "$LARGE_MODEL" "$TMP_DIR/project-prompt.txt" "$cached"
  fi
  project_file="$(printf '%s' "$project" | sed 's/[^A-Za-z0-9._-]/-/g').md"
  cp -- "$cached" "$PROJECT_DIR/$project_file"
  printf '%s\t%s\n' "$project" "$project_file" >> "$TMP_DIR/project-manifest.tsv"
done < "$TMP_DIR/projects.txt"

repo_bundle="$TMP_DIR/repository-bundle.md"
{
  printf '# Project-level evidence\n'
  while IFS=$'\t' read -r project project_file; do
    printf '\n## %s\n\n' "$project"
    cat "$PROJECT_DIR/$project_file"
  done < "$TMP_DIR/project-manifest.tsv"
  printf '\n# Repository statistics\n\n'
  printf 'Supported files summarized: %s\n' "$file_count"
  printf 'Current Git branch: %s\n' "$(git branch --show-current 2>/dev/null || true)"
  printf 'Latest commit: %s\n' "$(git log -1 --format='%h %cs %s' 2>/dev/null || printf 'No commits')"
} > "$repo_bundle"
head -c "$MAX_REPOSITORY_CHARS" "$repo_bundle" > "$TMP_DIR/repository-input.md"

{
  printf 'Create the definitive overview of this repository from the project-level evidence below. Explain the repository purpose, architecture, corpus-building workflow, major conceptual themes, model or software experiments, and current state. Distinguish source material from generated artifacts. Note real risks such as stale duplicates or incomplete outputs only when supported by the evidence. End with a concise section called "Current assessment". Write Markdown prose rather than a long checklist.\n\n'
  cat "$TMP_DIR/repository-input.md"
} > "$TMP_DIR/repository-prompt.txt"

repo_hash="$(sha256sum "$TMP_DIR/repository-prompt.txt" | awk '{print $1}')"
repo_cache="$CACHE_DIR/repository-$(printf '%s\0%s\0v2' "$LARGE_MODEL" "$repo_hash" | sha256sum | awk '{print $1}').md"
if ((FORCE)) || [[ ! -s "$repo_cache" ]]; then
  printf 'Writing repository overview...\n'
  ollama_generate "$LARGE_MODEL" "$TMP_DIR/repository-prompt.txt" "$repo_cache"
fi

{
  cat "$repo_cache"
  printf '\n\n---\n\n'
  printf 'Generated locally from %s files using `%s` and `%s`. ' "$file_count" "$SMALL_MODEL" "$LARGE_MODEL"
  printf 'See [the inventory](INVENTORY.md) for source-to-summary provenance.\n'
} > "$OUTPUT_DIR/REPOSITORY-OVERVIEW.md"

printf '\nDone: %s\n' "$OUTPUT_DIR/REPOSITORY-OVERVIEW.md"
printf 'Inventory: %s\n' "$OUTPUT_DIR/INVENTORY.md"

