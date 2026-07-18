#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${SYNC_VERSION:?Missing SYNC_VERSION}"
: "${SYNC_UPSTREAM_REPO:?Missing SYNC_UPSTREAM_REPO}"
: "${SYNC_FORK_OWNER:?Missing SYNC_FORK_OWNER}"
: "${SYNC_FORK_REPO:?Missing SYNC_FORK_REPO}"
: "${SYNC_BRANCH_PREFIX:?Missing SYNC_BRANCH_PREFIX}"

branch="${SYNC_BRANCH_PREFIX}${SYNC_VERSION}"
upstream_api="repos/$SYNC_UPSTREAM_REPO"
fork_api="repos/$SYNC_FORK_OWNER/$SYNC_FORK_REPO"

upstream_default_branch="$(gh api "$upstream_api" --jq '.default_branch')"
if [ -z "$upstream_default_branch" ]; then
  echo "::error::Unable to read default branch for $SYNC_UPSTREAM_REPO." >&2
  exit 1
fi

default_ref="heads/$upstream_default_branch"
upstream_head_sha="$(gh api "$upstream_api/git/ref/$default_ref" --jq '.object.sha')"
if [ -z "$upstream_head_sha" ]; then
  echo "::error::Unable to resolve upstream SHA for $SYNC_UPSTREAM_REPO@$upstream_default_branch." >&2
  exit 1
fi

if gh api "$fork_api/git/ref/heads/$branch" >/dev/null 2>&1; then
  fork_head_sha="$(gh api "$fork_api/git/ref/heads/$branch" --jq '.object.sha')"
  if [ "$fork_head_sha" = "$upstream_head_sha" ]; then
    echo "Reusable branch '$branch' already exists and is synchronized." >&2
  else
    gh api --method PATCH "$fork_api/git/refs/heads/$branch" \
      -f sha="$upstream_head_sha" \
      -f force=true >/dev/null
    echo "Reusable branch '$branch' was reset to '$SYNC_UPSTREAM_REPO@$upstream_default_branch'."
  fi
else
  gh api --method POST "$fork_api/git/refs" \
    -f ref="refs/heads/$branch" \
    -f sha="$upstream_head_sha" >/dev/null
  echo "Created reusable branch '$branch' from '$SYNC_UPSTREAM_REPO@$upstream_default_branch'."
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "branch=$branch"
    echo "upstream_default_branch=$upstream_default_branch"
  } >>"$GITHUB_OUTPUT"
fi

echo "$branch"
echo "$upstream_default_branch"
