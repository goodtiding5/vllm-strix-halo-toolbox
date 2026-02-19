#!/usr/bin/env bash
set -euo pipefail

# 02-build-vllm.sh
# Build vLLM from source for ROCm with gfx1151 support

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
WORK_DIR="${WORK_DIR:-/workspace}"
VLLM_DIR="${WORK_DIR}/vllm"
VLLM_VERSION="${VLLM_VERSION:-main}"
WHEEL_DIR="${WORK_DIR}/wheels"
GPU_TARGET="${GPU_TARGET:-gfx1151}"
GFX_VERSION="${GFX_VERSION:-11.5.1}"

# Set SUDO based on whether running as root (Docker) or non-root (distrobox)
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

usage() {
  cat <<'USAGE'
Usage: 02-build-vllm.sh [-f|--force] [--wheel]

Options:
  -f, --force    Remove ${VLLM_DIR} and start fresh
  --wheel        Build wheel (default: in-place install)
  --help         Show this help and exit

Complete build: build vLLM with ROCm support for gfx1151.
Run this script from INSIDE the container.
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

echo "[Step 1] Setting up build environment for vLLM ..."

# Force: remove vllm directory
if [ "${FORCE_REBUILD}" = "1" ]; then
  echo "Force: removing ${VLLM_DIR}..."
  rm -rf "${VLLM_DIR}"
fi

# Install build dependencies
echo "Installing build dependencies..."
# Activate virtual environment
source "${VENV_DIR}/bin/activate"
python3 -m pip install --no-cache-dir ninja cmake wheel build pybind11 "setuptools-scm>=8" grpcio-tools

echo "[Step 2] Building vLLM from source for ROCm gfx1151..."

# Set environment variables for GPU target
export PYTORCH_ROCM_ARCH="${GPU_TARGET}"
export HSA_OVERRIDE_GFX_VERSION="${GFX_VERSION}"
export MAX_JOBS=$(nproc)
export PIP_EXTRA_INDEX_URL=""

export ROCM_PATH="${ROCM_HOME}"

# Disable CK-based flash-attention (not supported on gfx1151)
# Use Triton-based kernels only
export BUILD_FA=0
export BUILD_TRITON=1

# Step 1: Clone or update vllm
if [ ! -d "${VLLM_DIR}" ]; then
  echo "Cloning vLLM (${VLLM_VERSION} branch, shallow)..."
  git clone --depth 1 --branch "${VLLM_VERSION}" https://github.com/vllm-project/vllm.git "${VLLM_DIR}"
  cd "${VLLM_DIR}"
else
  echo "Using existing vLLM directory at ${VLLM_DIR}"
  cd "${VLLM_DIR}"
  echo "Updating vLLM..."
  git fetch origin
  git checkout "${VLLM_VERSION}"
  # Only pull if it's a branch, not a tag
  if git show-ref --verify "refs/remotes/origin/${VLLM_VERSION}" > /dev/null 2>&1; then
    git pull origin "${VLLM_VERSION}"
  fi
fi

# Step 2: Configure to use existing PyTorch
echo "[Step 3] Configuring vLLM..."
python3 use_existing_torch.py

# Create wheels directory
mkdir -p "${WHEEL_DIR}"

# Step 3: Build vLLM
echo "Building vLLM with ROCm ${GPU_TARGET}..."
if [ "${BUILD_WHEEL}" = "1" ]; then
  python3 -m build --wheel --no-isolation -o "${WHEEL_DIR}"
  echo "Wheel location: ${WHEEL_DIR}"
else
  python3 -m pip install -e . --no-build-isolation --no-deps
fi

echo "[Done] vLLM build complete!"

