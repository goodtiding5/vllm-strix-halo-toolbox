#!/usr/bin/env bash
set -euo pipefail

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
WORK_DIR="${WORK_DIR:-/workspace}"
AITER_DIR="${WORK_DIR}/aiter"
AITER_VERSION="${AITER_VERSION:-main}"
WHEEL_DIR="${WORK_DIR}/wheels"
GPU_TARGET="${GPU_TARGET:-gfx1151}"
GFX_VERSION="${GFX_VERSION:-11.5.1}"

usage() {
  cat <<'USAGE'
Usage: 03-build-aiter.sh [-f|--force] [--wheel] [--help]

Options:
  -f, --force    Remove ${AITER_DIR} and start fresh
  --wheel        Build wheel (default: in-place install)
  --help         Show this help and exit

Build AMD AITER from source for ROCm with gfx1151 support.
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

echo "[Step 1] Building AMD AITER..."
echo "  GPU Target: ${GPU_TARGET}"
echo "  GFX Version: ${GFX_VERSION}"
echo "  AITER Dir: ${AITER_DIR}"
echo ""

# Activate virtual environment
if [ -f "${VENV_DIR}/bin/activate" ]; then
    source "${VENV_DIR}/bin/activate"
else
    echo "ERROR: Virtual environment not found at ${VENV_DIR}"
    exit 1
fi

# Force: remove aiter directory
if [ "${FORCE_REBUILD}" = "1" ]; then
  echo "Force: removing ${AITER_DIR}..."
  rm -rf "${AITER_DIR}"
fi

# Clone AITER repository
if [ -d "${AITER_DIR}" ]; then
    echo "AITER directory exists, pulling latest changes..."
    cd "${AITER_DIR}"
    git fetch origin
    git checkout "${AITER_VERSION}"
    # Only pull if it's a branch, not a tag
    if git show-ref --verify "refs/remotes/origin/${AITER_VERSION}" > /dev/null 2>&1; then
	git pull origin "${AITER_VERSION}"
    fi
else
    echo "Cloning AITER repository..."
    git clone --branch "${AITER_VERSION}" https://github.com/ROCm/aiter.git "${AITER_DIR}"
    cd "${AITER_DIR}"
fi

# Explicitly set ROCm architecture
export PYTORCH_ROCM_ARCH="${GPU_TARGET}"
export HSA_OVERRIDE_GFX_VERSION="${GFX_VERSION}"
export ROCM_PATH="${ROCM_HOME}"

# Verify ROCm SDK is initialized and hipconfig exists
echo ""
echo "Verifying ROCm SDK initialization..."
HIPCONFIG="${ROCM_HOME}/bin/hipconfig"
if [ ! -f "${HIPCONFIG}" ]; then
    echo "ERROR: hipconfig not found at ${HIPCONFIG}"
    exit 1
fi
echo "  ✓ hipconfig found at ${HIPCONFIG}"

# Create wheels directory
mkdir -p "${WHEEL_DIR}"

# Build AITER
if [ "${BUILD_WHEEL}" = "1" ]; then
    # Build wheel
    echo "Building AITER wheel (using no-build-isolation)..."
    pip wheel . --no-deps --no-build-isolation -w "${WHEEL_DIR}"
    
    # Find the built wheel
    AITER_WHEEL=$(ls -t "${WHEEL_DIR}"/amd_aiter-*.whl 2>/dev/null | head -1)
    if [ -z "${AITER_WHEEL}" ]; then
        echo "WARNING: Failed to find built AITER wheel"
    else
        echo ""
        echo "  ✓ AITER wheel built: ${AITER_WHEEL}"
    fi
else
    # In-place install
    echo "Installing AITER in-place (using no-build-isolation)..."
    pip install -e . --no-build-isolation --no-deps
fi

echo ""
echo "[Done] AITER build complete!"
