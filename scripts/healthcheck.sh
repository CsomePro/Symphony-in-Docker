#!/usr/bin/env bash
set -Eeuo pipefail
pgrep -f './bin/symphony' >/dev/null
