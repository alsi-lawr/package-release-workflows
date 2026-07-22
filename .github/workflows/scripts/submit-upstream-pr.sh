#!/usr/bin/env bash
set -euo pipefail
: "${GH_TOKEN:?Missing GH_TOKEN}"
: "${VERSION:?Missing VERSION}"
: "${RELEASE_REPOSITORY:?Missing RELEASE_REPOSITORY}"
: "${UPSTREAM_REPOSITORY:?Missing UPSTREAM_REPOSITORY}"
: "${FORK_OWNER:?Missing FORK_OWNER}"
: "${FORK_REPOSITORY:?Missing FORK_REPOSITORY}"
: "${FORK_BRANCH:?Missing FORK_BRANCH}"
: "${CHANNEL:?Missing CHANNEL}"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "::error::VERSION must be a strict X.Y.Z release version without a v prefix; received '$VERSION'." >&2; exit 1
fi
if ! release_json="$(gh release view "v${VERSION}" --repo "$RELEASE_REPOSITORY" --json isDraft,url)"; then
  echo "::error::Cannot submit the ${CHANNEL} PR because GitHub release v${VERSION} is missing from $RELEASE_REPOSITORY." >&2; exit 1
fi
if [ "$(jq -er '.isDraft' <<<"$release_json")" != false ]; then
  echo "::error::Cannot submit the ${CHANNEL} PR because GitHub release v${VERSION} is still a draft." >&2; exit 1
fi
release_url="$(jq -er '.url' <<<"$release_json")"
upstream_default_branch="$(gh api "repos/$UPSTREAM_REPOSITORY" --jq '.default_branch')"
if [ -z "$upstream_default_branch" ]; then echo "::error::Unable to resolve the default branch for $UPSTREAM_REPOSITORY." >&2; exit 1; fi
fork_api="repos/$FORK_OWNER/$FORK_REPOSITORY"
fork_ref="heads/$FORK_BRANCH"
if ! fork_head_sha="$(gh api "$fork_api/git/ref/$fork_ref" --jq '.object.sha')"; then
  echo "::error::Cannot submit the ${CHANNEL} PR because expected fork branch $FORK_OWNER:$FORK_BRANCH is missing from $FORK_REPOSITORY." >&2; exit 1
fi
head="$FORK_OWNER:$FORK_BRANCH"
existing_prs="$(gh api --method GET "repos/$UPSTREAM_REPOSITORY/pulls" \
  -f state=all \
  -f head="$head" \
  -f per_page=100 \
  --paginate \
  --slurp)"
existing_pr="$(jq -r 'map(.[]) | .[0] | if . == null then empty else [.html_url, .state, (.merged_at != null)] | @tsv end' <<<"$existing_prs")"
if [ -n "$existing_pr" ]; then
  IFS=$'\t' read -r existing_url existing_state existing_merged <<<"$existing_pr"
  if [ "$existing_merged" = true ]; then
    existing_state="$existing_state (merged)"
  fi
  echo "::notice::Existing ${CHANNEL} PR for $head: $existing_url ($existing_state)"
  exit 0
fi

if ! comparison="$(gh api "repos/$UPSTREAM_REPOSITORY/compare/${upstream_default_branch}...${FORK_OWNER}:${FORK_BRANCH}")"; then
  echo "::error::Cannot compare expected ${CHANNEL} fork branch $FORK_OWNER:$FORK_BRANCH with $UPSTREAM_REPOSITORY:$upstream_default_branch." >&2; exit 1
fi
ahead_by="$(jq -er '.ahead_by' <<<"$comparison")"
if [ "$ahead_by" -le 0 ]; then
  echo "::error::Cannot submit the ${CHANNEL} PR because expected fork branch $FORK_OWNER:$FORK_BRANCH has no changes ahead of $UPSTREAM_REPOSITORY:$upstream_default_branch." >&2; exit 1
fi
if [ -n "${NIX_PACKAGE:-}" ]; then
  if [[ ! "$NIX_PACKAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]+$ ]]; then
    echo "::error::Nix package attribute '$NIX_PACKAGE' cannot be mapped safely into pkgs/by-name." >&2
    exit 1
  fi

  package_prefix="$(printf '%.2s' "$NIX_PACKAGE" | tr '[:upper:]' '[:lower:]')"
  package_path="pkgs/by-name/${package_prefix}/${NIX_PACKAGE}/package.nix"
  if package_lookup="$(gh api "repos/$UPSTREAM_REPOSITORY/contents/$package_path?ref=$upstream_default_branch" 2>&1)"; then
    change_kind=update
  elif grep -Fq 'HTTP 404' <<<"$package_lookup"; then
    change_kind=add
  else
    echo "::error::Cannot determine whether nixpkgs package '$NIX_PACKAGE' exists on $UPSTREAM_REPOSITORY:$upstream_default_branch." >&2
    exit 1
  fi

  PR_TITLE="nixpkgs: ${change_kind} ${NIX_PACKAGE} to v${VERSION}"
  PR_BODY="Automated nixpkgs ${change_kind} for ${NIX_PACKAGE} v${VERSION}."
else
  : "${PR_TITLE:?Missing PR_TITLE}"
  : "${PR_BODY:?Missing PR_BODY}"
fi

created_pr="$(gh pr create --repo "$UPSTREAM_REPOSITORY" --base "$upstream_default_branch" --head "$head" --title "$PR_TITLE" --body "$PR_BODY")"
echo "::notice::Submitted ${CHANNEL} PR for $head at $created_pr (release: $release_url; fork head: $fork_head_sha; commits ahead: $ahead_by)."
