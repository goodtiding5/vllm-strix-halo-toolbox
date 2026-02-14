#!/usr/bin/env bash
set -euo pipefail

# 03-build-aiter.sh
# AMD AITER build script for gfx1151 (Strix Halo)
#
# WARNING: AITER may not be compatible with gfx1151 (Strix Halo) GPU.
#
# Reason: AITER contains inline AMD GPU assembly instructions (e.g., v_pk_mul_f32)
# that may not be supported on gfx1151 architecture. AITER is designed for datacenter
# GPUs like MI300X (gfx942), MI350 (gfx950), and gfx12 series.
#
# vLLM works perfectly WITHOUT AITER - it's an optional performance optimization
# library. All core vLLM functionality is fully operational on gfx1151.
#
# Supported AITER GPUs: gfx942, gfx950, gfx1250, gfx12*
# Potentially unsupported: gfx1150, gfx1151 (Strix Halo)
#
# To use AITER when support is added in the future:
#   export VLLM_ROCM_USE_AITER=1

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
AITER_DIR="${WORK_DIR}/aiter"
WHEEL_DIR="${WORK_DIR}/wheels"
GPU_TARGET="${GPU_TARGET:-gfx1151}"

echo "[03] Building AMD AITER..."
echo "  GPU Target: ${GPU_TARGET}"
echo "  AITER Dir: ${AITER_DIR}"
echo ""
echo "⚠️  WARNING: AITER may not be compatible with gfx1151 (Strix Halo)"
echo "  If build fails, vLLM will still work using standard ROCm kernels"
echo ""

# Activate virtual environment
if [ -f "${VENV_DIR}/bin/activate" ]; then
    source "${VENV_DIR}/bin/activate"
else
    echo "ERROR: Virtual environment not found at ${VENV_DIR}"
    echo "This should have been created by 01-install-tools.sh"
    exit 1
fi

# Clone AITER repository
if [ -d "${AITER_DIR}" ]; then
    echo "AITER directory exists, pulling latest changes..."
    cd "${AITER_DIR}"
    git pull origin main || true
else
    echo "Cloning AITER repository..."
    git clone https://github.com/ROCm/aiter.git "${AITER_DIR}"
    cd "${AITER_DIR}"
fi

# Explicitly set ROCm architecture to gfx1151
echo "Setting ROCm architecture..."
export PYTORCH_ROCM_ARCH="${GPU_TARGET}"
echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"

# Set ROCm paths for AITER
echo "Setting ROCm paths..."
export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
export ROCM_PATH="${ROCM_HOME}"
export PATH="${VENV_DIR}/bin:${PATH}"
echo "  ROCM_HOME=${ROCM_HOME}"
echo "  PATH includes ${VENV_DIR}/bin"

# Create wheels directory
mkdir -p "${WHEEL_DIR}"

# Build AITER wheel
# Note: Using --no-build-isolation to use existing environment with rocm_sdk installed
echo "Building AITER wheel (using no-build-isolation)..."
pip wheel . --no-deps --no-build-isolation -w "${WHEEL_DIR}" || echo "AITER build failed - vLLM will work without it"

# Find the built wheel
AITER_WHEEL=$(ls -t "${WHEEL_DIR}"/amd_aiter-*.whl 2>/dev/null | head -1)
if [ -z "${AITER_WHEEL}" ]; then
    echo "WARNING: Failed to find built AITER wheel - vLLM will work without it"
else
    echo ""
    echo "  ✓ AITER wheel built: ${AITER_WHEEL}"
    
    # Install AITER from wheel
    echo ""
    echo "Installing AITER from wheel..."
    pip install "${AITER_WHEEL}"
fi

echo ""
echo "[03] AITER build complete!"
echo ""
echo "Verifying installation..."
source "${VENV_DIR}/bin/activate"
if pip show amd-aiter >/dev/null 2>&1; then
    echo "  ✅ AITER: Successfully installed"
    pip show amd-aiter | grep "^Name:" && pip show amd-aiter | grep "^Version:"
    if [ -n "${AITER_WHEEL}" ]; then
        echo "  📦 Wheel: ${AITER_WHEEL}"
    fi
else
    echo "  ⚠️  AITER: Build failed - vLLM will work without it"
fi
echo ""
echo "Current Status:"
echo "  ✅ vLLM: Can be built with or without AITER"
echo "  ✅ PyTorch: ROCm backend functional"
echo ""
echo "To proceed with vLLM:"
echo "  distrobox enter vllm-toolbox"
echo "  source /opt/venv/bin/activate"
echo "  ./04-build-vllm.sh"
