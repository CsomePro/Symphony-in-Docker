#!/usr/bin/env bash
set -Eeuo pipefail

LINEAR_API_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"
WORKFLOW_FILE="${WORKFLOW_FILE:-/config/WORKFLOW.docker.md}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is not set" >&2
  exit 1
fi

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

project_slug="$(
  sed -nE 's/^[[:space:]]*project_slug:[[:space:]]*"?([^"#]+)"?.*/\1/p' "$WORKFLOW_FILE" \
    | head -n 1 \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
)"

if ! grep -Eq '^[[:space:]]*api_key:[[:space:]]*\$LINEAR_API_KEY([[:space:]]|$)' "$WORKFLOW_FILE"; then
  echo "workflow file does not reference \$LINEAR_API_KEY: $WORKFLOW_FILE" >&2
  exit 1
fi

if [[ -z "$project_slug" ]]; then
  echo "tracker.project_slug is missing in $WORKFLOW_FILE" >&2
  exit 1
fi

if [[ "$project_slug" == "your-linear-project-slug" ]]; then
  echo "tracker.project_slug still uses the example placeholder in $WORKFLOW_FILE" >&2
  exit 1
fi

payload="$(jq -cn '{query:"query VerifyLinearKey { viewer { id name email } }"}')"
response="$(
  curl -sS "$LINEAR_API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    --data "$payload"
)"

if ! printf '%s' "$response" | jq -e '.data.viewer.id? != null and ((.errors // []) | length == 0)' >/dev/null; then
  printf '%s\n' "$response" | jq . 2>/dev/null || printf '%s\n' "$response"
  exit 1
fi

viewer_name="$(printf '%s' "$response" | jq -r '.data.viewer.name // "unknown"')"
viewer_email="$(printf '%s' "$response" | jq -r '.data.viewer.email // "unknown"')"

printf 'project_slug: %s\n' "$project_slug"
printf 'viewer: %s <%s>\n' "$viewer_name" "$viewer_email"
