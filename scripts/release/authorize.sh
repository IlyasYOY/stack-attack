#!/usr/bin/env bash
set -euo pipefail
[[ "$GITHUB_REF" == refs/heads/main ]]
[[ "$GITHUB_REPOSITORY" == IlyasYOY/stack-attack ]]
if [[ "$GITHUB_EVENT_NAME" == push ]]; then
  # The caller gates this same-revision workflow on successful main checks.
  [[ "$GITHUB_WORKFLOW_REF" == "$GITHUB_REPOSITORY/.github/workflows/check.yml@refs/heads/main" ]]
  exit
fi
[[ "$GITHUB_EVENT_NAME" == workflow_dispatch ]]
for actor in "$GITHUB_ACTOR" "$GITHUB_TRIGGERING_ACTOR"; do
  if [[ "$actor" != "$GITHUB_REPOSITORY_OWNER" ]]; then
    jq -e --arg login "$actor" 'type == "array" and any(.[]; . == $login)' \
      <<< "$RELEASE_MAINTAINERS" >/dev/null
  fi
done
