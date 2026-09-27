#!/usr/bin/env sh
# Build the place and run the headless checks.
#   ./scripts/check.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json -o build/FillTheStore.rbxlx
lune run tests/layout.luau build/FillTheStore.rbxlx
lune run tests/playtest.luau build/FillTheStore.rbxlx
cp build/FillTheStore.rbxlx FillTheStore.rbxlx
echo "All checks passed. FillTheStore.rbxlx updated."
