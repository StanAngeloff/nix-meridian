#!/usr/bin/env bash
#
# A read-only script in the shape of a PR comment fetcher: a usage heredoc, REST reads with no fields,
# a paginating function and one GraphQL query whose document spans lines and whose variables are dynamic.
# The `--jq` programs and the heredoc carry backticks and quotes the tokenizer has to get past.

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	cat <<'EOF'
Usage:
  pending-comments.sh [<pr-number>]

Prints every comment as JSON. A `pending_*` entry is an "unsubmitted" draft.
EOF
	exit 0
fi

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

if [[ -n "${1:-}" ]]; then
	PR_NUMBER="$1"
else
	PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null) || {
		echo "Error: no pull request for this branch." >&2
		exit 1
	}
fi

fetch_paginated() {
	local endpoint="$1"
	local page=1
	local results="[]"
	while true; do
		local response
		response=$(gh api "${endpoint}?per_page=100&page=${page}" 2>/dev/null) || break
		results=$(echo "$results" "$response" | jq -s '.[0] + .[1]')
		[[ "$(echo "$response" | jq 'length')" -lt 100 ]] && break
		page=$((page + 1))
	done
	echo "$results"
}

comments=$(fetch_paginated "repos/${REPO}/pulls/${PR_NUMBER}/comments")

# Draft threads come over GraphQL, because REST leaves `line` null on them.
pending=$(gh api graphql -f query='
    query($owner:String!,$name:String!,$number:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$number){
          reviews(states:[PENDING],first:1){
            nodes { comments(first:100){ nodes { databaseId body path line } } }
          }
        }
      }
    }' \
	-f owner="${REPO%%/*}" -f name="${REPO##*/}" -F number="$PR_NUMBER" \
	--jq '.data.repository.pullRequest.reviews.nodes[0].comments.nodes[]
    | {source: "pending_review_comment", id: .databaseId, body: .body}' | jq -s '.')

echo "$comments" "$pending" | jq -s 'add'
