#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# s4s-pc — host-side build driver. Run on your Mac (or any Docker host).
#
#   ./build.sh            full build  -> ./out/s4s-pc-noble-amd64.iso
#   ./build.sh check      sanity-check the builder (tools + scripts), no ISO
#
# Env knobs:
#   VW_MODE=offline|pull  how Vaultwarden's image gets into the ISO (default offline)
#
# On Apple Silicon the amd64 ISO is built under emulation and can take 1-3+
# hours. For a fast, reliable amd64 build, push to GitHub and let
# .github/workflows/build-iso.yml build it on a native x86_64 runner.
# ============================================================================

IMAGE="s4s-pc-builder:amd64"
MODE="${1:-build}"
VW_MODE="${VW_MODE:-offline}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${ROOT}/out"

echo "==> [1/2] Building the builder image (amd64; emulated on Apple Silicon)…"
docker build --platform=linux/amd64 -t "${IMAGE}" "${ROOT}"

echo "==> [2/2] Running the build (MODE=${MODE}, VW_MODE=${VW_MODE})…"
docker run --rm -it \
  --platform=linux/amd64 \
  --privileged \
  -e MODE="${MODE}" \
  -e VW_MODE="${VW_MODE}" \
  -v "${ROOT}/out:/build/out" \
  "${IMAGE}"

echo "==> Output in ${ROOT}/out:"
ls -la "${ROOT}/out/" || true
