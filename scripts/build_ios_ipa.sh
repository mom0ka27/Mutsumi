#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="$project_dir/build/ios/iphoneos/Runner.app"
ipa_dir="$project_dir/build/ios/ipa"
ipa_path="$ipa_dir/Runner.ipa"
payload_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$payload_dir"
}

trap cleanup EXIT

cd "$project_dir"
flutter build ios --release \
  --dart-define=DANDANPLAY_APP_ID="${DANDANPLAY_APP_ID:-}" \
  --dart-define=DANDANPLAY_APP_SECRET="${DANDANPLAY_APP_SECRET:-}"
  
if [[ ! -d "$app_path" ]]; then
  printf '未找到构建产物：%s\n' "$app_path" >&2
  exit 1
fi

rm -rf "$ipa_dir"
mkdir -p "$ipa_dir" "$payload_dir/Payload"
ditto "$app_path" "$payload_dir/Payload/Runner.app"
(
  cd "$payload_dir"
  zip -qry "$ipa_path" Payload
)

printf 'IPA 已生成：%s\n' "$ipa_path"
