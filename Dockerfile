# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder - Build vLLM and AITER wheels
# =============================================================================

FROM ubuntu:24.04 AS builder

LABEL maintainer="ken@epenguin.com" \
      description="vLLM and AITER wheels builder for AMD gfx1151"

# Install basic dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    python3.12 \
    python3.12-venv \
    wget \
    curl \
    ca-certificates \
    libgfortran13 \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy entire project to workspace
COPY . /workspace/

# Make scripts executable
RUN chmod +x /workspace/*.sh

# Run build scripts sequentially
# Note: Running as root, so SUDO="" (no sudo needed)
ENV SUDO="" SKIP_VERIFICATION=true

# 01: Install system tools (creates /opt/venv)
RUN /workspace/01-install-tools.sh

# 02: Install ROCm and PyTorch (nightly packages)
RUN /workspace/02-install-rocm.sh

# 03: Build AITER wheel (optional, skip if pre-built wheel exists in wheels/)
RUN if [ -f "/workspace/wheels/amd_aiter-*.whl" ]; then \
      echo "[03] AITER wheel already exists, skipping build"; \
    else \
      echo "[03] Pre-built AITER wheel not found, building..."; \
      /workspace/03-build-aiter.sh; \
    fi

# 04: Build vLLM wheel
RUN /workspace/04-build-vllm.sh

# Set output path for easy access
ENV WHEELS_DIR=/workspace/wheels

# =============================================================================
# Stage 2: Runtime - Create minimal runtime environment with vLLM and AITER
# =============================================================================

FROM ubuntu:24.04 AS runtime

LABEL maintainer="ken@epenguin.com" \
      description="vLLM runtime for AMD gfx1151"

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    curl \
    ca-certificates \
    google-perftools \
    libatomic1 \
    libgfortran13 \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy wheels from builder (includes pre-built AITER from wheels/ in repo)
COPY --from=builder /workspace/wheels/*.whl /tmp/

# Create virtual environment and install ROCm nightly packages
RUN python3.12 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip

# Install ROCm first (no --pre, avoids fetching many PyTorch versions)
RUN /opt/venv/bin/pip install --no-cache-dir --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    "rocm[libraries,devel]"

# Install PyTorch (after ROCm, uses --pre for latest nightly versions)
RUN /opt/venv/bin/pip install --no-cache-dir --pre --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    torch torchaudio torchvision

# Install vLLM and AITER wheels with --no-deps to avoid dependency conflicts
# Note: Wheels depend on ROCm packages installed above
RUN /opt/venv/bin/pip install --no-deps /tmp/vllm-*.whl /tmp/amd_aiter-*.whl && \
    rm /tmp/vllm-*.whl /tmp/amd_aiter-*.whl

# Configure TCMalloc system-wide
RUN TCMALLOC_PATH="/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4" && \
    if [ -f "$TCMALLOC_PATH" ]; then \
        echo "$TCMALLOC_PATH" | tee /etc/ld.so.preload > /dev/null && \
        echo "TCMalloc configured: $(cat /etc/ld.so.preload)"; \
    else \
        echo "WARNING: TCMalloc not found"; \
    fi

# Set environment for vLLM
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONPATH="/opt/venv/lib/python3.12/site-packages" \
    HSA_OVERRIDE_GFX_VERSION="11.5.1" \
    VLLM_TARGET_DEVICE="rocm"

# Verify installation
RUN /opt/venv/bin/python -c "import vllm; print(f'vLLM version: {vllm.__version__}')" && \
    pip list | grep -E "(vllm|amd-aiter)"

# Expose default port for vLLM API server
EXPOSE 8080

# Default command - show help or start server
CMD ["/opt/venv/bin/vllm", "--help"]
