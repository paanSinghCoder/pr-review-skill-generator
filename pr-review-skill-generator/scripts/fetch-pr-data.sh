#!/usr/bin/env bash
# fetch-pr-data.sh — fetch merged-PR review data for the pr-review-skill-generator.
#
# Requires: gh (GitHub CLI), authenticated. No other dependencies (no jq needed).
#
# Usage:
#   fetch-pr-data.sh [--repo owner/name] [--count N] [--out DIR]
#
#   --repo   Repository to mine (default: the repo of the current directory)
#   --count  Number of most recent merged PRs to fetch (default: 100)
#   --out    Output directory (default: ./.pr-skill-workdir)
#
# Output layout:
#   $OUT/repo.txt              — owner/name that was mined
#   $OUT/index.json            — list of fetched PRs (number, title, author, mergedAt, url)
#   $OUT/numbers.txt           — PR numbers, one per line, newest first
#   $OUT/prs/<N>.meta.json     — PR metadata: body, files, commits, reviews, issue comments
#   $OUT/prs/<N>.threads.json  — inline review threads: resolution status, path, diff hunks
#   $OUT/failed.txt            — PR numbers that failed to fetch (only if any failed)
#
# The script is resumable: PRs already present in $OUT/prs/ are skipped on re-run.

set -uo pipefail

REPO=""
COUNT=100
OUT=".pr-skill-workdir"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --out)   OUT="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | cut -c 3-; exit 0 ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
done

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || {
    echo "error: not inside a GitHub repo and no --repo given." >&2
    exit 1
  }
fi
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

mkdir -p "$OUT/prs"
echo "$REPO" > "$OUT/repo.txt"
rm -f "$OUT/failed.txt"

echo "Listing last $COUNT merged PRs of $REPO ..."
gh pr list --repo "$REPO" --state merged --limit "$COUNT" \
  --json number,title,author,mergedAt,url > "$OUT/index.json" || {
  echo "error: could not list PRs for $REPO" >&2
  exit 1
}
gh pr list --repo "$REPO" --state merged --limit "$COUNT" \
  --json number --jq '.[].number' > "$OUT/numbers.txt"

TOTAL=$(wc -l < "$OUT/numbers.txt" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
  echo "error: no merged PRs found in $REPO" >&2
  exit 1
fi
echo "Found $TOTAL merged PRs. Fetching details ..."

THREADS_QUERY='query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:100){
        nodes{
          isResolved isOutdated path line
          comments(first:50){nodes{author{login} body createdAt diffHunk}}
        }
      }
    }
  }
}'

i=0
while IFS= read -r n; do
  i=$((i + 1))
  meta="$OUT/prs/$n.meta.json"
  threads="$OUT/prs/$n.threads.json"

  if [[ -s "$meta" && -s "$threads" ]]; then
    echo "[$i/$TOTAL] PR #$n — already fetched, skipping"
    continue
  fi
  echo "[$i/$TOTAL] PR #$n"

  if ! gh pr view "$n" --repo "$REPO" \
      --json number,title,body,author,mergedAt,baseRefName,files,commits,reviews,comments,labels \
      > "$meta.tmp" 2>/dev/null; then
    echo "  warning: failed to fetch metadata for #$n, skipping" >&2
    rm -f "$meta.tmp"
    echo "$n" >> "$OUT/failed.txt"
    continue
  fi
  mv "$meta.tmp" "$meta"

  if ! gh api graphql -f query="$THREADS_QUERY" \
      -f owner="$OWNER" -f repo="$NAME" -F number="$n" \
      --jq '.data.repository.pullRequest.reviewThreads.nodes' \
      > "$threads.tmp" 2>/dev/null; then
    echo "  warning: failed to fetch review threads for #$n, skipping" >&2
    rm -f "$threads.tmp" "$meta"
    echo "$n" >> "$OUT/failed.txt"
    continue
  fi
  mv "$threads.tmp" "$threads"

  sleep 0.2  # stay well clear of API rate limits
done < "$OUT/numbers.txt"

FETCHED=$(ls "$OUT/prs" | grep -c '\.meta\.json$' || true)
echo ""
echo "Done. $FETCHED PRs fetched into $OUT/"
if [[ -s "$OUT/failed.txt" ]]; then
  echo "warning: $(wc -l < "$OUT/failed.txt" | tr -d ' ') PRs failed — see $OUT/failed.txt" >&2
fi
