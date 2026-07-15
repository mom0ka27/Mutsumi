#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export PYTHONPYCACHEPREFIX=./.pycache

while true; do
  uv sync --locked --no-dev --no-install-project
  set +e
  uv run --no-sync python run.py
  status=$?
  set -e
  if [ "$status" -ne 75 ]; then
    exit "$status"
  fi
  sleep 1
done
