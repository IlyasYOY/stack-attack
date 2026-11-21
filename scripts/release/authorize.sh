#!/usr/bin/env bash
set -euo pipefail
[[ "$GITHUB_EVENT_NAME" == workflow_dispatch && "$GITHUB_REF" == refs/heads/main ]]
[[ "$GITHUB_REPOSITORY" == IlyasYOY/stack-attack ]]
for actor in "$GITHUB_ACTOR" "$GITHUB_TRIGGERING_ACTOR"; do
  if [[ "$actor" != "$GITHUB_REPOSITORY_OWNER" ]]; then
    jq -e --arg login "$actor" 'type == "array" and any(.[]; . == $login)' \
      <<< "$RELEASE_MAINTAINERS" >/dev/null
  fi
done
