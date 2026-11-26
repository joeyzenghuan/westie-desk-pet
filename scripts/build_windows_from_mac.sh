#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${1:-win-x64}"
SELF_CONTAINED="${2:-false}"
OUT_DIR="${ROOT_DIR}/dist/windows-${RUNTIME}"

echo "==> Running cross-platform Core unit tests..."
DOTNET_ROLL_FORWARD=Major dotnet test "${ROOT_DIR}/windows/WestieDeskPet.Tests/WestieDeskPet.Tests.csproj" -c Release

echo "==> Cross-publishing Windows WPF app (${RUNTIME}, self-contained=${SELF_CONTAINED})..."
rm -rf "${OUT_DIR}"
dotnet publish "${ROOT_DIR}/windows/WestieDeskPet.Windows/WestieDeskPet.Windows.csproj" \
    -c Release \
    -r "${RUNTIME}" \
    --self-contained "${SELF_CONTAINED}" \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -o "${OUT_DIR}"

echo "==> Built Windows app at: ${OUT_DIR}/WestieDeskPet.exe"
ls -lh "${OUT_DIR}/WestieDeskPet.exe"
echo "    Sprites copied: $(find "${OUT_DIR}/Sprites" -name '*.png' | wc -l | tr -d ' ') PNGs"
