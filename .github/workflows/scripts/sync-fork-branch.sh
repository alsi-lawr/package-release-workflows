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

retry_delays=(1 2 4 8 16)
max_attempts=6
sync_succeeded=false
last_gh_diagnostic=""
gh_diagnostic_file="$(mktemp)"
trap 'rm -f "$gh_diagnostic_file"' EXIT

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  : >"$gh_diagnostic_file"

  if fork_head_sha="$(gh api "$fork_api/git/ref/heads/$branch" \
    --jq '.object.sha' 2>"$gh_diagnostic_file")"; then
    if [ "$fork_head_sha" = "$upstream_head_sha" ]; then
      echo "Reusable branch '$branch' already exists and is synchronized." >&2
      sync_succeeded=true
    elif gh api --method PATCH "$fork_api/git/refs/heads/$branch" \
      -f sha="$upstream_head_sha" \
      -F force=true >/dev/null 2>"$gh_diagnostic_file"; then
      echo "Reusable branch '$branch' was reset to '$SYNC_UPSTREAM_REPO@$upstream_default_branch'."
      sync_succeeded=true
    else
      last_gh_diagnostic="$(cat "$gh_diagnostic_file")"
    fi
  elif grep -Fq '(HTTP 404)' "$gh_diagnostic_file"; then
    if gh api --method POST "$fork_api/git/refs" \
      -f ref="refs/heads/$branch" \
      -f sha="$upstream_head_sha" >/dev/null 2>"$gh_diagnostic_file"; then
      echo "Created reusable branch '$branch' from '$SYNC_UPSTREAM_REPO@$upstream_default_branch'."
      sync_succeeded=true
    else
      last_gh_diagnostic="$(cat "$gh_diagnostic_file")"
    fi
  else
    last_gh_diagnostic="$(cat "$gh_diagnostic_file")"
  fi

  if [ "$sync_succeeded" = true ]; then
    break
  fi

  if [ "$attempt" -lt "$max_attempts" ]; then
    retry_delay="${retry_delays[$((attempt - 1))]}"
    echo "::warning::Unable to synchronize '$branch' on attempt $attempt; retrying in ${retry_delay}s." >&2
    sleep "$retry_delay"
  fi
done

if [ "$sync_succeeded" != true ]; then
  if [ -n "$last_gh_diagnostic" ]; then
    printf '%s\n' "$last_gh_diagnostic" >&2
  fi

  echo "::error::Unable to synchronize reusable branch '$branch' after $max_attempts attempts." >&2
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "branch=$branch"
    echo "upstream_default_branch=$upstream_default_branch"
  } >>"$GITHUB_OUTPUT"
fi

echo "$branch"
echo "$upstream_default_branch"
