#!/usr/bin/env bash
set -Eeuo pipefail

echo '== versions =='
elixir --version | head -n 3 || true
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || true
node --version || true
npm --version || true
codex --version || true
gh --version | head -n 1 || true
git --version || true
mise --version || true

echo
echo '== auth =='
if codex login status >/dev/null 2>&1; then
  echo 'codex: OK'
else
  echo 'codex: NOT LOGGED IN'
fi
if gh auth status >/dev/null 2>&1; then
  echo 'gh: OK'
else
  echo 'gh: NOT LOGGED IN'
fi

echo
echo '== ssh =='
ls -ld /root/.ssh || true
ls -l /root/.ssh || true
ssh -G github.com | sed -n '1,20p' || true
ssh -T git@github.com || true

echo
echo '== git =='
git config --global --list || true

echo
echo '== symphony files =='
ls -l /config || true
ls -l /data || true
