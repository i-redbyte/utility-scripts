#!/usr/bin/env bash
set -euo pipefail
if ! command -v brew >/dev/null; then
  echo "Homebrew не установлен: https://brew.sh"; exit 1
fi
brew update
brew upgrade
brew cleanup -s
brew doctor || true
echo "Готово ✅"
