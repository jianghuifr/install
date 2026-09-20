#!/usr/bin/env bash
# macOS 上可双击运行的入口（Finder 里双击会用终端打开并执行）
cd "$(dirname "$0")" || exit 1
exec ./install.sh "$@"
