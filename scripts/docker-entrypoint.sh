#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[entrypoint] %s\n' "$*"
}

copy_if_exists() {
  local src="$1" dst="$2" mode="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    chmod "$mode" "$dst"
    log "copied $(basename "$src") -> $dst"
  fi
}

sync_dir_if_exists() {
  local src="$1" dst="$2"
  if [ -d "$src" ] && [ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    mkdir -p "$dst"
    rsync -a --delete "$src"/ "$dst"/
    log "synced directory $src -> $dst"
  fi
}

overlay_dir_if_exists() {
  local src="$1" dst="$2"
  if [ -d "$src" ] && [ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    mkdir -p "$dst"
    rsync -a "$src"/ "$dst"/
    log "overlayed directory $src -> $dst"
  fi
}

seed_dir_missing_entries() {
  local src="$1" dst="$2"
  if [ -d "$src" ] && [ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    mkdir -p "$dst"
    rsync -a --ignore-existing "$src"/ "$dst"/
    log "seeded missing entries in $dst from $src"
  fi
}

: "${SYMPHONY_WORKSPACE_ROOT:=/data/workspaces}"
: "${SYMPHONY_LOGS_ROOT:=/data/logs}"
: "${WORKFLOW_PATH:=/config/WORKFLOW.docker.md}"
: "${SYMPHONY_PORT:=4000}"
: "${SSH_KNOWN_HOSTS_SOURCE:=/secrets/ssh/known_hosts}"
: "${SSH_CONFIG_SOURCE:=/secrets/ssh/config}"
: "${SSH_PRIVATE_KEY_SOURCE:=/secrets/ssh/id_ed25519}"
: "${GH_CONFIG_SOURCE:=/secrets/gh}"
: "${CODEX_CONFIG_SOURCE:=/secrets/codex}"
: "${CODEX_TEMPLATE_SOURCE:=/opt/symphony/.codex}"

mkdir -p "$SYMPHONY_WORKSPACE_ROOT" "$SYMPHONY_LOGS_ROOT" /root/.ssh /root/.codex /root/.config/gh
chmod 700 /root/.ssh

# Seed writable runtime copies so ssh/gh can update state safely.
copy_if_exists "$SSH_PRIVATE_KEY_SOURCE" /root/.ssh/id_ed25519 600
copy_if_exists "$SSH_CONFIG_SOURCE" /root/.ssh/config 600
copy_if_exists "$SSH_KNOWN_HOSTS_SOURCE" /root/.ssh/known_hosts 644
sync_dir_if_exists "$GH_CONFIG_SOURCE" /root/.config/gh
seed_dir_missing_entries "$CODEX_TEMPLATE_SOURCE" /root/.codex
overlay_dir_if_exists "$CODEX_CONFIG_SOURCE" /root/.codex

# Populate github.com host key if missing.
if ! ssh-keygen -F github.com -f /root/.ssh/known_hosts >/dev/null 2>&1; then
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null || true
fi
chmod 644 /root/.ssh/known_hosts || true

# Basic git defaults.
git config --global user.name "${GIT_AUTHOR_NAME:-Codex}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-codex@users.noreply.github.com}"
git config --global pull.rebase false
git config --global init.defaultBranch main
git config --global safe.directory '*'
git config --global rerere.enabled true
git config --global rerere.autoupdate true

# Optional non-interactive Codex login via API key.
if ! codex login status >/dev/null 2>&1; then
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    printf '%s' "${OPENAI_API_KEY}" | codex login --with-api-key
    log "performed codex login using OPENAI_API_KEY"
  else
    log "Codex is not logged in; mount a prepared /secrets/codex directory or set OPENAI_API_KEY"
  fi
fi

# Optional non-interactive GitHub CLI auth.
if ! gh auth status >/dev/null 2>&1; then
  if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
    printf '%s' "${GH_TOKEN:-${GITHUB_TOKEN:-}}" | gh auth login --with-token
    gh auth setup-git || true
    log "performed gh login using GH_TOKEN/GITHUB_TOKEN"
  else
    log "gh is not logged in; mount /secrets/gh or set GH_TOKEN/GITHUB_TOKEN"
  fi
fi

cd /opt/symphony/elixir
exec ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --logs-root "$SYMPHONY_LOGS_ROOT" \
  --port "$SYMPHONY_PORT" \
  "$WORKFLOW_PATH"
