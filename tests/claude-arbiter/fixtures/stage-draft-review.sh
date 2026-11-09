#!/usr/bin/env bash
# A writing script whose first GraphQL call is a query: the engine stops there and reports nothing after it,
# so the mutations below are what the second look must still find.

set -euo pipefail

pr_id=$(gh api graphql -f query='query($number:Int!){ repository(owner:"o",name:"r"){ pullRequest(number:$number){ id } } }' \
	-F number="$1" --jq '.data.repository.pullRequest.id')

review_id=$(gh api graphql -f query='
  mutation($pr:ID!){ addPullRequestReview(input:{pullRequestId:$pr}){ pullRequestReview { id } } }' \
	-f pr="$pr_id" --jq '.data.addPullRequestReview.pullRequestReview.id')

gh api graphql -f query='
  mutation($review:ID!,$body:String!){ addPullRequestReviewThread(input:{pullRequestReviewId:$review,body:$body,path:"a",line:1}){ thread { id } } }' \
	-f review="$review_id" -f body="$2"
