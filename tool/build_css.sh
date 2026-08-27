#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🎨 Compiling Tailwind CSS..."
if command -v tailwindcss &> /dev/null; then
  tailwindcss -i web/styles.tw.css -o web/styles.css --minify
elif [ -f "$HOME/.local/bin/tailwindcss" ]; then
  "$HOME/.local/bin/tailwindcss" -i web/styles.tw.css -o web/styles.css --minify
else
  npx -y tailwindcss@3 -i web/styles.tw.css -o web/styles.css --minify
fi

# Also maintain main.css copy for compatibility
cp web/styles.css web/main.css

echo "✅ Compiled web/styles.css successfully."
