#!/usr/bin/env bash
# Summarize compilation, text extraction, and exact normalized-text duplicates.
set -Euo pipefail

BUILD="build"
while (($#)); do
  case "$1" in
    --build) BUILD=$2; shift 2 ;;
    -h|--help) printf 'Usage: %s [--build DIR]\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

COMPILE="$BUILD/compile-manifest.tsv"
TEXT="$BUILD/text-manifest.tsv"
SUMMARY="$BUILD/analysis-summary.txt"
DUPLICATES="$BUILD/text-duplicates.tsv"
[[ -f "$COMPILE" ]] || { printf 'Missing %s\n' "$COMPILE" >&2; exit 1; }

{
  printf 'Flyxion corpus build analysis\n\n'
  awk -F '\t' 'NR>1 {n++; c[$1]++; pages+=$5; seconds+=$6} END {
    print "Root documents attempted:",n+0
    for(s in c) print "  " s ":",c[s]
    print "Compiled pages:",pages+0
    print "Aggregate compile seconds:",seconds+0
  }' "$COMPILE"
  if [[ -f "$TEXT" ]]; then
    printf '\n'
    awk -F '\t' 'NR>1 {n++; c[$1]++; words+=$4; lines+=$5} END {
      print "PDFs processed:",n+0
      for(s in c) print "  " s ":",c[s]
      print "Extracted words:",words+0
      print "Extracted lines:",lines+0
    }' "$TEXT"
  fi
} > "$SUMMARY"

printf 'text_hash\toccurrences\ttext_files\n' > "$DUPLICATES"
if [[ -f "$TEXT" ]]; then
  awk -F '\t' 'NR>1 && $6!="" {count[$6]++; files[$6]=files[$6] (files[$6]?" | ":"") $3}
    END {for(h in count) if(count[h]>1) print h "\t" count[h] "\t" files[h]}' "$TEXT" \
    | sort -t $'\t' -k2,2nr >> "$DUPLICATES"
fi

cat "$SUMMARY"
printf '\nDuplicate groups: %s\n' "$(( $(wc -l < "$DUPLICATES") - 1 ))"

