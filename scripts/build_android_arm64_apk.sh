#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk_path="$project_dir/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

cd "$project_dir"
flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=DANDANPLAY_APP_ID="${DANDANPLAY_APP_ID:-}" \
  --dart-define=DANDANPLAY_APP_SECRET="${DANDANPLAY_APP_SECRET:-}"

if [[ ! -f "$apk_path" ]]; then
  printf '未找到构建产物：%s\n' "$apk_path" >&2
  exit 1
fi

printf 'ARM64 APK 已生成：%s\n' "$apk_path"
