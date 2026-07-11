#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export PYTHONPYCACHEPREFIX=./.pycache

uv run python run.py
