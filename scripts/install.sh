#!/bin/bash
# ビルドして ~/Applications に置き、起動する。
# ログイン時の自動起動は、アプリが起動時に自分で登録する（メニューで切り替えられる）。
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
DEST="$HOME/Applications/LuLu Sidekick.app"
mkdir -p "$HOME/Applications"
for pid in $(pgrep -u "$(id -u)" -f "LuLu Sidekick.app/Contents/MacOS/LuLuSidekick" || true); do kill "$pid"; done
# 古いプロセスが終わるまで待つ（終わる前に open すると LaunchServices が -600 で失敗する）
for _ in $(seq 50); do pgrep -u "$(id -u)" -f "LuLu Sidekick.app/Contents/MacOS/LuLuSidekick" >/dev/null || break; sleep 0.1; done
rm -rf "$DEST"
cp -R "build/LuLu Sidekick.app" "$DEST"
open "$DEST"
echo "OK: $DEST"
