#!/usr/bin/env bash
set -euo pipefail

# 04-build-fa.sh
# Build Flash Attention wheel for ROCm with gfx1151 (Strix Halo) support

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
WORK_DIR="${WORK_DIR:-/workspace}"
FA_DIR="${WORK_DIR}/flash-attention"
FA_VERSION="${FA_VERSION:-main_perf}"
WHEEL_DIR="${WORK_DIR}/wheels"
GPU_TARGET="${GPU_TARGET:-gfx1151}"
GFX_VERSION="${GFX_VERSION:-11.5.1}"

usage() {
  cat <<'USAGE'
Usage: 04-build-fa.sh [-f|--force] [--wheel] [--help]

Options:
  -f, --force    Remove ${FA_DIR} and start fresh
  --wheel        Build wheel (default: in-place install)
  --help         Show this help and exit

Build Flash Attention from source for ROCm with gfx1151 support.
USAGE
}

FORCE_REBUILD=0
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

echo "Building Flash Attention..."
echo "  GPU Target: ${GPU_TARGET}"
echo "  GFX Version: ${GFX_VERSION}"
echo "  Flash Attention Dir: ${FA_DIR}"
echo ""

# Activate virtual environment
if [ -f "${VENV_DIR}/bin/activate" ]; then
    source "${VENV_DIR}/bin/activate"
else
    echo "ERROR: Virtual environment not found at ${VENV_DIR}"
    exit 1
fi

# Force: remove flash-attention directory
if [ "${FORCE_REBUILD}" = "1" ]; then
  echo "Force: removing ${FA_DIR}..."
  rm -rf "${FA_DIR}"
fi

# Clone Flash Attention repository
if [ -d "${FA_DIR}" ]; then
    echo "Flash Attention directory exists, updating..."
    cd "${FA_DIR}"
    git fetch origin
    git checkout "${FA_VERSION}"
    # Only pull if it's a branch, not a tag
    if git show-ref --verify "refs/remotes/origin/${FA_VERSION}" > /dev/null 2>&1; then
        git pull origin "${FA_VERSION}"
    fi
else
    echo "Cloning Flash Attention repository (${FA_VERSION} branch)..."
    git clone --branch "${FA_VERSION}" https://github.com/ROCm/flash-attention.git "${FA_DIR}"
    cd "${FA_DIR}"
fi

# Set ROCm architecture for Flash Attention
echo "Setting ROCm architecture..."
export PYTORCH_ROCM_ARCH="${GPU_TARGET}"
export HSA_OVERRIDE_GFX_VERSION="${GFX_VERSION}"
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
export FLASH_ATTENTION_SKIP_CK_BUILD="TRUE"  # Skip CK backend - not supported on gfx1151
echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
echo "  FLASH_ATTENTION_TRITON_AMD_ENABLE=${FLASH_ATTENTION_TRITON_AMD_ENABLE}"
echo "  FLASH_ATTENTION_SKIP_CK_BUILD=${FLASH_ATTENTION_SKIP_CK_BUILD}"

# Set ROCm paths for Flash Attention
export ROCM_PATH="${ROCM_HOME}"

# Create wheels directory
mkdir -p "${WHEEL_DIR}"

# Build Flash Attention
if [ "${BUILD_WHEEL}" = "1" ]; then
    # Build wheel
    echo "Building Flash Attention wheel (using no-build-isolation)..."
    pip wheel . --no-deps --no-build-isolation -w "${WHEEL_DIR}"
    
    # Find the built wheel
    FA_WHEEL=$(ls -t "${WHEEL_DIR}"/flash_attn-*.whl 2>/dev/null | head -1)
    if [ -z "${FA_WHEEL}" ]; then
        echo "WARNING: Failed to find built Flash Attention wheel"
        exit 1
    else
        echo ""
        echo "  ✓ Flash Attention wheel built: ${FA_WHEEL}"
    fi
else
    # In-place install
    echo "Installing Flash Attention in-place (using no-build-isolation)..."
    pip install -e . --no-build-isolation --no-deps
fi

echo ""
echo "[Done] Flash Attention build and installation complete!"
