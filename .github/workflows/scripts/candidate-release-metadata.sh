#!/usr/bin/env bash

release_api_lookup() {
  local endpoint="$1" output="$2" response result=0 status
  response="$(mktemp)"
  gh api --include "$endpoint" >"$response" || result=$?
  status="$(head -n 1 "$response" | awk '{print $2}')"
  if [[ "$status" == 404 ]]; then
    rm -f "$response"
    return 4
  fi
  if [[ "$result" -ne 0 || "$status" != 200 ]]; then
    echo "::error::Could not verify release metadata at $endpoint (HTTP ${status:-unknown})." >&2
    rm -f "$response"
    return 1
  fi
  sed '1,/^\r\{0,1\}$/d' "$response" >"$output"
  rm -f "$response"
  if ! jq -e 'type == "object"' "$output" >/dev/null; then
    echo "::error::Invalid release metadata at $endpoint." >&2
    return 1
  fi
}

candidate_release_metadata() {
  local tag="$1" output="$2" latest result=0
  release_api_lookup "repos/$GITHUB_REPOSITORY/releases/tags/$tag" "$output" || return $?
  if ! jq -e --arg tag "$tag" '.tag_name == $tag and .draft == false and .prerelease == true' "$output" >/dev/null; then
    echo "::error::Release $tag must already be a non-draft prerelease; refusing metadata mismatch." >&2
    return 1
  fi
  latest="$(mktemp)"
  release_api_lookup "repos/$GITHUB_REPOSITORY/releases/latest" "$latest" || result=$?
  if [[ "$result" == 0 ]]; then
    if ! jq -e --arg tag "$tag" '(.tag_name | type == "string" and length > 0) and .tag_name != $tag' "$latest" >/dev/null; then
      echo "::error::Release $tag is latest or latest metadata is invalid; refusing candidate reuse." >&2
      rm -f "$latest"
      return 1
    fi
  elif [[ "$result" != 4 ]]; then
    rm -f "$latest"
    return 1
  fi
  rm -f "$latest"
}
