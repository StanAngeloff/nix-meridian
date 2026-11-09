#!/usr/bin/env bash
gh api graphql -f query='query{viewer{login}}'
gh api graphql -f query='mutation{addComment(input:{subjectId:"x",body:"y"}){clientMutationId}}'
git push origin main
