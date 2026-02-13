#!/usr/bin/env bash
set -euo pipefail

# 99-build-vllm.sh
# Complete build script for vLLM with ROCm support
# Usage: Run from INSIDE the vllm-toolbox:
#   ./99-build-vllm.sh [-f|--force] [--wheel]

WORK_DIR="${WORK_DIR:-/workspace}"
VLLM_VERSION="${VLLM_VERSION:-main}"
VENV_DIR="${VENV_DIR:-${WORK_DIR}/venv}"

usage() {
  cat <<'USAGE'
Usage: 99-build-vllm.sh [-f|--force] [--wheel]

Options:
  -f, --force    Remove /workspace/venv and /workspace/vllm and start fresh
  --wheel        Build wheel (default: in-place install)
  --help         Show this help and exit

Complete build: setup venv and build vLLM with ROCm support for gfx1151.
Run this script from INSIDE the vllm-toolbox container.
USAGE
}

FORCE_REBUILD=${FORCE_REBUILD:-0}
BUILD_WHEEL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE_REBUILD=1
      shift
      ;;
    --wheel)
      BUILD_WHEEL=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

echo "[01] Setting up build environment for vLLM ${VLLM_VERSION}..."

VENV_DIR="${VENV_DIR:-${WORK_DIR}/venv}"
PYTHON="${VENV_DIR}/bin/python"
VLLM_DIR="${WORK_DIR}/vllm"

# Force: remove venv and vllm directory
if [ "${FORCE_REBUILD}" = "1" ]; then
  echo "Force: removing ${VENV_DIR} and ${VLLM_DIR}..."
  rm -rf "${VENV_DIR}"
  rm -rf "${VLLM_DIR}"
fi

# Clone /opt/venv to WORK_DIR using virtualenv-clone
if [ ! -d "${VENV_DIR}" ]; then
  echo "Cloning venv from /opt/venv to ${VENV_DIR}..."
  TEMP_VENV=$(mktemp -d)
  python3 -m venv "${TEMP_VENV}"
  "${TEMP_VENV}/bin/pip" install --no-cache-dir virtualenv-clone
  "${TEMP_VENV}/bin/virtualenv-clone" /opt/venv "${VENV_DIR}"
  rm -rf "${TEMP_VENV}"
fi

echo "Using Python: ${PYTHON}"
${PYTHON} --version

# Install build dependencies
echo "Installing build dependencies..."
${PYTHON} -m pip install --no-cache-dir ninja cmake wheel build pybind11 "setuptools-scm>=8" grpcio-tools

echo "[01] Setup complete!"
echo "  Venv: ${VENV_DIR}"

echo "[02] Building vLLM ${VLLM_VERSION} for gfx1151..."

# Clone or update vllm
cd "$(dirname "${VLLM_DIR}")"

if [ ! -d "vllm" ]; then
  echo "Cloning vLLM (main branch, shallow)..."
  git clone --depth 1 https://github.com/vllm-project/vllm.git
  cd vllm
else
  echo "Using existing vLLM directory at ${VLLM_DIR}"
  cd "${VLLM_DIR}"
  echo "Updating vLLM (git pull)..."
  git fetch origin
  git checkout "${VLLM_VERSION}"
  git pull origin "${VLLM_VERSION}"
fi

# Activate venv
source "${VENV_DIR}/bin/activate"

# Set environment variables for Strix Halo (gfx1151)
export PYTORCH_ROCM_ARCH="gfx1151"
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export MAX_JOBS=$(nproc)
export PIP_EXTRA_INDEX_URL=""

# Link to the container's pre-installed PyTorch if script exists
if [ -f "use_existing_torch.py" ]; then
  python use_existing_torch.py
fi

echo "Building vLLM with ROCm gfx1151..."
if [ "${BUILD_WHEEL}" = "1" ]; then
  python -m build --wheel --no-isolation
  echo "Wheel location: ${VLLM_DIR}/dist/"
else
  python -m pip install -e . --no-build-isolation --no-deps
fi

echo "[02] Build complete!"
