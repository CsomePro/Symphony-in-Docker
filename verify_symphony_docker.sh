#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

SERVICE_NAME="${SERVICE_NAME:-symphony}"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
REPO_REMOTE="${REPO_REMOTE:-}"
GH_REPO="${GH_REPO:-}"
WORKFLOW_FILE="${WORKFLOW_FILE:-/config/WORKFLOW.docker.md}"
INSIDE_SHELL="${INSIDE_SHELL:-bash}"

if [ -z "${GH_REPO:-}" ] && [ -n "${SOURCE_REPO_URL:-}" ]; then
  GH_REPO="${SOURCE_REPO_URL#git@github.com:}"
  GH_REPO="${GH_REPO#https://github.com/}"
  GH_REPO="${GH_REPO%.git}"
  echo "Derived GH_REPO='$GH_REPO' from SOURCE_REPO_URL='$SOURCE_REPO_URL'" 
fi


if [ -z "$REPO_REMOTE" ] && [ -n "$SOURCE_REPO_URL" ]; then
  REPO_REMOTE="$SOURCE_REPO_URL"
fi

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

WARN_ITEMS=()
FAIL_ITEMS=()

pass() {
  printf "%b[PASS]%b %s\n" "$GREEN" "$RESET" "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf "%b[FAIL]%b %s\n" "$RED" "$RESET" "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_ITEMS+=("$1")
}

warn() {
  printf "%b[WARN]%b %s\n" "$YELLOW" "$RESET" "$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  WARN_ITEMS+=("$1")
}

info() {
  printf "%b==>%b %s\n" "$BLUE" "$RESET" "$1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_host_check() {
  local desc="$1"
  shift
  if "$@" >/tmp/verify_host.out 2>/tmp/verify_host.err; then
    pass "$desc"
    sed 's/^/    /' /tmp/verify_host.out || true
  else
    fail "$desc"
    sed 's/^/    /' /tmp/verify_host.err || true
    sed 's/^/    /' /tmp/verify_host.out || true
  fi
}

run_container_check() {
  local desc="$1"
  local cmd="$2"
  if $COMPOSE_CMD exec -T "$SERVICE_NAME" "$INSIDE_SHELL" -lc "$cmd" >/tmp/verify_ctr.out 2>/tmp/verify_ctr.err; then
    pass "$desc"
    sed 's/^/    /' /tmp/verify_ctr.out || true
  else
    fail "$desc"
    sed 's/^/    /' /tmp/verify_ctr.err || true
    sed 's/^/    /' /tmp/verify_ctr.out || true
  fi
}

run_container_warn_check() {
  local desc="$1"
  local cmd="$2"
  if $COMPOSE_CMD exec -T "$SERVICE_NAME" "$INSIDE_SHELL" -lc "$cmd" >/tmp/verify_ctr.out 2>/tmp/verify_ctr.err; then
    pass "$desc"
    sed 's/^/    /' /tmp/verify_ctr.out || true
  else
    warn "$desc"
    sed 's/^/    /' /tmp/verify_ctr.err || true
    sed 's/^/    /' /tmp/verify_ctr.out || true
  fi
}

print_summary() {
  echo
  printf "%bSummary%b: %s pass, %s warn, %s fail\n" \
    "$BOLD" "$RESET" "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

  if [[ "${#WARN_ITEMS[@]}" -gt 0 ]]; then
    echo
    printf "%bWARN items%b\n" "$BOLD" "$RESET"
    for item in "${WARN_ITEMS[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi

  if [[ "${#FAIL_ITEMS[@]}" -gt 0 ]]; then
    echo
    printf "%bFAIL items%b\n" "$BOLD" "$RESET"
    for item in "${FAIL_ITEMS[@]}"; do
      printf "  - %s\n" "$item"
    done
  fi

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
  fi
}

cleanup() {
  rm -f /tmp/verify_host.out /tmp/verify_host.err /tmp/verify_ctr.out /tmp/verify_ctr.err
}
trap cleanup EXIT

info "Checking host prerequisites"
if have_cmd docker; then
  pass "docker is installed"
else
  fail "docker is not installed"
fi

if docker compose version >/dev/null 2>&1; then
  pass "docker compose plugin is available"
else
  fail "docker compose plugin is unavailable"
fi

run_host_check "docker daemon is reachable" docker info
run_host_check "compose config parses successfully" bash -lc "$COMPOSE_CMD config >/dev/null"

info "Checking expected local files"
for path in \
  .env \
  docker-compose.yml \
  Dockerfile \
  scripts/docker-entrypoint.sh \
  scripts/doctor.sh \
  scripts/healthcheck.sh \
  config/WORKFLOW.docker.md; do
  if [[ -e "$path" ]]; then
    pass "exists: $path"
  else
    fail "missing: $path"
  fi
done

for path in secrets/ssh secrets/codex secrets/gh data/logs data/workspaces; do
  if [[ -e "$path" ]]; then
    pass "exists: $path"
  else
    warn "missing optional/runtime path: $path"
  fi
done

if [[ -f secrets/ssh/id_ed25519 ]]; then
  perms="$(stat -c '%a' secrets/ssh/id_ed25519 2>/dev/null || stat -f '%Lp' secrets/ssh/id_ed25519 2>/dev/null || true)"
  if [[ "$perms" == "600" ]]; then
    pass "SSH private key permissions are 600"
  else
    warn "SSH private key permissions are $perms (recommended 600)"
  fi
else
  warn "SSH private key not found at secrets/ssh/id_ed25519"
fi

if [[ -f secrets/ssh/config ]]; then
  perms="$(stat -c '%a' secrets/ssh/config 2>/dev/null || stat -f '%Lp' secrets/ssh/config 2>/dev/null || true)"
  if [[ "$perms" == "600" ]]; then
    pass "SSH config permissions are 600"
  else
    warn "SSH config permissions are $perms (recommended 600)"
  fi
else
  warn "SSH config not found at secrets/ssh/config"
fi

if [[ -f secrets/ssh/known_hosts ]]; then
  perms="$(stat -c '%a' secrets/ssh/known_hosts 2>/dev/null || stat -f '%Lp' secrets/ssh/known_hosts 2>/dev/null || true)"
  if [[ "$perms" == "644" ]]; then
    pass "known_hosts permissions are 644"
  else
    warn "known_hosts permissions are $perms (recommended 644)"
  fi
else
  warn "known_hosts not found at secrets/ssh/known_hosts"
fi

info "Checking service state"
CID="$($COMPOSE_CMD ps -q "$SERVICE_NAME" 2>/dev/null || true)"
if [[ -z "$CID" ]]; then
  fail "service '$SERVICE_NAME' is not created; run: docker compose up -d"
  print_summary
fi

run_host_check "service '$SERVICE_NAME' is running" bash -lc "test -n \"$($COMPOSE_CMD ps -q "$SERVICE_NAME")\""
run_host_check "service '$SERVICE_NAME' passes inspect state" bash -lc "docker inspect -f '{{.State.Running}}' $CID | grep -qx true"

info "Checking tools inside container"
run_container_check "codex is installed" "codex --version"
run_container_check "gh is installed" "gh --version"
run_container_check "git is installed" "git --version"
run_container_check "mise is installed" 'if command -v mise >/dev/null 2>&1; then mise --version; elif [ -x /usr/local/bin/mise ]; then /usr/local/bin/mise --version; elif [ -x /root/.local/bin/mise ]; then /root/.local/bin/mise --version; elif [ -x /home/linuxbrew/.linuxbrew/bin/mise ]; then /home/linuxbrew/.linuxbrew/bin/mise --version; else echo "mise not found in PATH or common install locations" >&2; exit 1; fi'

info "Checking configuration inside container"
run_container_check "workflow file exists in container" "test -f '$WORKFLOW_FILE' && ls -l '$WORKFLOW_FILE'"
run_container_check "workflow file is readable" "sed -n '1,80p' '$WORKFLOW_FILE' >/dev/null && sed -n '1,20p' '$WORKFLOW_FILE'"
run_container_check "SSH directory permissions are sane" "test \"\$(stat -c '%a' /root/.ssh 2>/dev/null || stat -f '%Lp' /root/.ssh)\" = 700"
run_container_warn_check "container SSH config is present" "test -f /root/.ssh/config && ls -l /root/.ssh/config"
run_container_warn_check "container known_hosts is present" "test -f /root/.ssh/known_hosts && ls -l /root/.ssh/known_hosts"

info "Checking application auth inside container"
run_container_warn_check "Codex login status" "codex login status"
run_container_warn_check "GitHub CLI auth status" "gh auth status"

if ${COMPOSE_CMD:-docker compose} exec -T "${SERVICE_NAME:-symphony}" bash -lc 'gh api user >/dev/null 2>&1'; then
  info "GitHub CLI auth is available; checking GitHub permissions"

  if [ -n "${GH_REPO:-}" ]; then
    run_container_warn_check "gh permission: repo metadata read" \
      "gh repo view \"$GH_REPO\" --json name,defaultBranchRef >/dev/null"

    run_container_warn_check "gh permission: pull requests read" \
      "gh pr list -R \"$GH_REPO\" --limit 1 >/dev/null"

    run_container_warn_check "gh permission: issues read" \
      "gh issue list -R \"$GH_REPO\" --limit 1 >/dev/null"

    run_container_warn_check "gh permission: actions read" \
      "gh run list -R \"$GH_REPO\" --limit 1 >/dev/null"
  else
    warn "GH_REPO not set; skipping gh permission probes"
  fi
else
  warn "GitHub CLI is not authenticated; skipping gh permission probes"
fi

info "Checking GitHub network access"
run_container_warn_check "SSH handshake to github.com" "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com || test \$? -eq 1"

if [[ -n "$REPO_REMOTE" ]]; then
  run_container_warn_check "git remote access to configured repository" "git ls-remote '$REPO_REMOTE' | head"
else
  warn "REPO_REMOTE not set; skipping git ls-remote test"
fi

if [[ -n "$GH_REPO" ]]; then
  run_container_warn_check "gh can view repository $GH_REPO" "gh repo view '$GH_REPO'"
else
  warn "GH_REPO not set; skipping gh repo view test"
fi

info "Running bundled doctor script"
run_container_warn_check "doctor.sh completes" "doctor.sh"

print_summary
