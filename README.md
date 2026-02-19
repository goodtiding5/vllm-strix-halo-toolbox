# vLLM for AMD Strix Halo (gfx1151)

[![Build and Push Docker Image](https://github.com/openmtx/vllm-strix-halo-toolbox/actions/workflows/docker-build-push.yml/badge.svg)](https://github.com/openmtx/vllm-strix-halo-toolbox/actions/workflows/docker-build-push.yml)

Docker-based build system for running vLLM on AMD Strix Halo GPUs (gfx1151 architecture).

## Overview

This repository provides a workflow to build vLLM from source for the gfx1151 architecture (AMD Strix Halo / Ryzen AI MAX+ PRO 395).

**Key Features:**
- Uses official ROCm/PyTorch Docker image as base
- Builds vLLM, AITER, and Flash Attention from source
- Supports CPU-only build environment (no GPU required for building)
- Multi-stage Docker build with optimized runtime image
- Configurable versions via build arguments

## Requirements

- **OS:** Linux with Docker support (Ubuntu 24.04 recommended)
- **GPU:** AMD Strix Halo (gfx1151) - Ryzen AI MAX+ PRO 395 with Radeon 8060S
- **RAM:** 16GB+ recommended (32GB+ for larger models)
- **Disk:** 50GB+ for ROCm, PyTorch, and vLLM
- **Tools:** Docker 24.0+, Docker Compose 2.0+

**Note:** GPU is only required for runtime inference. The build process runs entirely in CPU-only environment.

## Architecture

**gfx1151** is AMD's GPU architecture for Strix Halo APUs. It requires:
- ROCm 7.2+ with gfx1151 support
- PyTorch 2.9+ compiled for ROCm
- Target architecture: `gfx1151`
- GPU version: `11.5.1`

## Quick Start

### Docker Build (Recommended)

The easiest way to build and run vLLM is using Docker:

```bash
# Build the image
docker build -t vllm-gfx1151 .

# Or use docker-compose
docker compose up -d
```

### Build Process

**Evolution of Our Approach:**

We initially attempted to build vLLM using ROCm and PyTorch nightly pip releases in a CPU-only environment. While this approach works for some configurations, we encountered build complexities with vLLM's C++ extensions and ROCm toolchain integration.

**Our Solution:**

We successfully pivoted to using the official `rocm/pytorch` Docker image as the base, which provides:
- Pre-installed ROCm 7.2.0 with working toolchain
- PyTorch 2.9.1 with ROCm support
- Properly configured build environment

This approach allows building all components (Flash Attention, AITER, and vLLM) for gfx1151 in a **CPU-only environment** without requiring GPU access during the build process. The build:
- Compiles for `gfx1151` architecture using HIP compiler
- Generates GPU binaries ahead of time
- Works in CI/CD and cloud environments
- Produces portable wheels for distribution

### Build Scripts

If you prefer to build manually:

```bash
# Build Flash Attention (optional but recommended)
./04-build-fa.sh --wheel

# Build AITER (optional)
./03-build-aiter.sh --wheel

# Build vLLM
./02-build-vllm.sh --wheel
```

All scripts support:
- `--wheel` flag to build wheels instead of in-place install
- `--force` flag to clean rebuild
- Version control via environment variables (VLLM_VERSION, AITER_VERSION, FA_VERSION)

## Docker Build System

### Multi-Stage Dockerfile

The main `Dockerfile` uses a multi-stage build process:

**Stage 1: Builder**
- Based on `rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1`
- Builds wheels for Flash Attention, AITER, and vLLM
- Runs in CPU-only environment (no GPU required)
- Configurable versions via build arguments

**Stage 2: Release**
- Same base image for consistency
- Installs pre-built wheels from builder stage
- Minimal runtime environment
- Ready for GPU inference

```bash
# Build with default versions
docker build -t vllm-gfx1151 .

# Build with specific versions
docker build \
  --build-arg VLLM_VERSION=v0.6.0 \
  --build-arg AITER_VERSION=main \
  --build-arg FA_VERSION=main_perf \
  -t vllm-gfx1151 .
```

### Docker Compose

Use `docker-compose.yml` for easier management:

```bash
# Build and start
docker compose up -d

# View logs
docker compose logs -f

# Stop
docker compose down
```

### Builder-Only Image

For CI/CD or extracting wheels:

```bash
# Build only the builder stage
docker build --target builder -t vllm-gfx1151-builder .

# Extract wheels
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-builder \
    bash -c "cp /workspace/wheels/*.whl /output/"
```

## GitHub Actions CI/CD

This repository uses GitHub Actions for automated Docker image builds:

### Main Branch Workflows

**Workflow:** `.github/workflows/docker-build-push.yml`

- **Trigger:** Pushes to `main` branch or tags
- **Image Name:** `vllm-rocm-gfx1151`
- **Tags:** Semantic versioning (e.g., `1.0.0`, `v1.0`, `latest`)
- **Use case:** Production releases with versioned images

### Dev Branch Workflows

**Workflow:** `.github/workflows/docker-build-dev.yml`

- **Trigger:** Pushes to `dev` branch
- **Image Name:** `vllm-rocm-dev-gfx1151`
- **Tags:** Timestamp-based (e.g., `dev-20250214120000`, `latest`)
- **Use case:** Development builds for testing (reflects nightly ROCm packages)

### Workflow Features

- Uses Docker Buildx for multi-platform support
- No caching (avoids issues with venv persistence)
- Requires `DOCKER_USERNAME` and `DOCKER_PASSWORD` secrets
- Builds `runtime` target from multi-stage Dockerfile
- Sets `SUDO=""` and `SKIP_VERIFICATION=true` for CPU-only builds

### Manual Trigger

Workflows can be manually triggered via GitHub Actions UI for on-demand builds.

## Build Scripts

These scripts are used by the Docker build process but can also be run manually:

### 02-build-vllm.sh

Builds vLLM from source with ROCm support for gfx1151.

**Features:**
- Configures for gfx1151 architecture (BUILD_FA=0, BUILD_TRITON=1)
- Uses existing PyTorch/ROCm from base image
- Creates installable wheel

**Usage:**
```bash
./02-build-vllm.sh [--wheel] [--force]
```

**Options:**
- `--wheel` - Build wheel instead of in-place install
- `--force` - Clean rebuild (removes existing vllm directory)

**Output:**
- Wheel: `/workspace/wheels/vllm-*.whl`

### 03-build-aiter.sh

Builds AMD AITER (AI Tensor Engine for ROCm) from source.

**Features:**
- Builds AMD optimized kernels for ROCm
- Produces wheel for distribution
- Optional component (vLLM works without it on gfx1151)

**Usage:**
```bash
./03-build-aiter.sh [--wheel] [--force]
```

**Output:**
- Wheel: `/workspace/wheels/amd_aiter-*.whl`

### 04-build-fa.sh

Builds Flash Attention with AMD Triton backend.

**Features:**
- Custom Flash Attention for gfx1151
- Uses Triton AMD backend
- Required for optimal attention performance

**Usage:**
```bash
./04-build-fa.sh [--wheel] [--force]
```

**Output:**
- Wheel: `/workspace/wheels/flash_attn-*.whl`
- GPU: gfx1151 (Strix Halo)

### 03-build-aiter.sh

Builds AMD AITER (AI Tensor Engine for ROCm) from source.

**AITER Support Status:**
- Supported: gfx942 (MI300X), gfx950, gfx1250, gfx12
- **Not Supported by AITER: gfx1150, gfx1151 (Strix Halo)**

**Note:** AITER builds successfully on gfx1151 but vLLM won't use it since it only supports gfx9 architectures. Runtime warning is expected and harmless.

**Installs:**
- AITER wheel: `/workspace/wheels/amd_aiter-*.whl`
- AITER to virtual environment

**Usage:**
```bash
./03-build-aiter.sh
```

### 04-build-vllm.sh

Builds vLLM from source with ROCm support.

**Features:**
- Clones vLLM repository (main branch)
- Uses existing PyTorch/ROCm installation
- Builds C++ extensions for gfx1151
- Creates installable wheel

**Output:**
- Wheel: `/workspace/wheels/vllm-*.whl`
- Installation: `/opt/venv`

Note: AITER also produces a wheel at `/workspace/wheels/amd_aiter-*.whl`

## Configuration

### Environment Variables

Key environment variables for building and runtime:

```bash
# Required for runtime
ROCM_HOME=/opt/rocm
PYTORCH_ROCM_ARCH=gfx1151
HSA_OVERRIDE_GFX_VERSION=11.5.1

# Optional build settings
MAX_JOBS=4                    # Build parallelism (default: nproc)
GPU_TARGET=gfx1151           # Target architecture
```

### Build Arguments

When building with Docker, you can customize versions:

```bash
docker build \
  --build-arg VLLM_VERSION=main \
  --build-arg AITER_VERSION=main \
  --build-arg FA_VERSION=main_perf \
  -t vllm-gfx1151 .
```

### .toolbox.env

Environment configuration file for manual builds:

```bash
# Base image
BASE_IMAGE=docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1

# GPU settings
GPU_TARGET=gfx1151
GFX_VERSION=11.5.1

# Workspace settings
WORK_DIR=/workspace
VENV_DIR=/opt/venv

# Version overrides
VLLM_VERSION=main
AITER_VERSION=main
FA_VERSION=main_perf
```

## Usage Examples

### Start vLLM Server

```bash
# Using docker-compose
docker compose up -d

# Or manually with Docker
docker run -d \
  --name vllm-gfx1151 \
  --device /dev/kfd \
  --device /dev/dri \
  -p 8080:8080 \
  -e HSA_OVERRIDE_GFX_VERSION=11.5.1 \
  vllm-gfx1151 \
  vllm serve Qwen/Qwen2.5-0.5B-Instruct \
    --host 0.0.0.0 \
    --port 8080 \
    --tensor-parallel-size 1
```

### Test API

```bash
./test.sh
```

Or manually:
```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Download Models

```bash
./download-model.sh Qwen/Qwen2.5-0.5B-Instruct
```

Models are cached in `./cache/huggingface/`

## Key Technical Details

### Why TCMalloc?

The pip-installed ROCm SDK can cause "double free or corruption" memory errors. TCMalloc (Google's memory allocator) prevents this by replacing the standard malloc.

**Configured in:** `/etc/ld.so.preload`

### Device Libraries

ROCm device bitcode libraries are located at:
```
/opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel/lib/llvm/amdgcn/bitcode/
```

These are required for compiling HIP kernels and are automatically configured.

### ROCm Symlink

For compatibility with tools expecting ROCm at `/opt/rocm`:
```bash
/opt/rocm -> /workspace/venv/lib/python3.12/site-packages/_rocm_sdk_devel
```

## Troubleshooting

### Dependency Version Conflicts

vLLM and AITER wheels depend on specific ROCm and PyTorch versions. To avoid conflicts:

**Docker Build:**
- ROCm nightly packages are installed first (matching builder environment)
- Wheels are installed with `--no-deps` to prevent pip from changing ROCm packages
- Ensures runtime environment matches what wheels were built against

**Manual Installation:**
- Install ROCm packages before installing vLLM/AITER wheels
- Use the same ROCm nightly index URL for both packages and wheels
- Example:
  ```bash
  pip install --pre --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
      "rocm[libraries,devel]" torch torchaudio torchvision
  pip install --no-deps vllm-*.whl
  ```

### GPU Not Detected

**Docker Builder:** This is expected and harmless - the Docker builder is CPU-only and doesn't need GPU access to build wheels.

**Runtime Container:** If GPU isn't detected:
```bash
# Check ROCm
rocminfo | grep gfx

# Check PyTorch
python -c "import torch; print(torch.cuda.is_available())"
```

**Skip verification:** To skip GPU checks (e.g., for CPU-only builds):
```bash
# For individual script
SKIP_VERIFICATION=true ./02-install-rocm.sh
```

### Memory Corruption Errors

TCMalloc should prevent these. If they occur:
```bash
# Verify TCMalloc is loaded
cat /etc/ld.so.preload
# Should show: /usr/lib/x86_64-linux-gnu/libtcmalloc.so.4
```

### Build Failures

**CMake can't find Torch:**
```bash
export Torch_DIR=/opt/venv/lib/python3.12/site-packages/torch/share/cmake/Torch
```

**GPU architecture detection fails:**
Ensure you're using the Docker-based build or set `GPU_TARGET=gfx1151` explicitly.

**Out of memory during build:**
```bash
# Reduce parallel jobs
export MAX_JOBS=4
```

**ROCm SDK issues:**
```bash
# Check ROCm installation
ls /opt/rocm/bin/rocminfo

# Verify device libraries
ls /opt/rocm/lib/llvm/amdgcn/bitcode/
```

### AITER Warning at Runtime

vLLM may show a warning about AITER at startup:
```
WARNING: AITER is not supported on this architecture (gfx1151)
```

This is **expected and harmless** - vLLM will automatically use standard ROCm/PyTorch kernels instead. AITER only supports gfx9 architectures (MI300X, MI350), not gfx1151 (Strix Halo).

## Directory Structure

```
.
├── 02-build-vllm.sh           # Build vLLM from source
├── 03-build-aiter.sh          # Build AITER kernels
├── 04-build-fa.sh             # Build Flash Attention
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── .toolbox.env               # Environment configuration
├── .dockerignore             # Docker build exclusions
├── docker-compose.yml         # Docker Compose configuration
├── Dockerfile                 # Multi-stage Docker build
├── Dockerfile.builder         # Builder-only image
├── archive/                   # Archived legacy scripts
├── cache/
│   └── huggingface/          # Model cache
├── wheels/                   # Built wheels (created by build scripts)
└── README.md                  # This file
```

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| ROCm 7.11.0 | ✅ Working | Nightly packages for gfx1151 |
| PyTorch 2.11.0 | ✅ Working | ROCm backend functional |
| vLLM 0.16.0rc2 | ✅ Working | Built from source |
| TCMalloc | ✅ Configured | Prevents memory corruption |
| AITER | ✅ Builds | Produces wheel but vLLM won't use on gfx1151 (optional) |
| **Docker** | **✅ Working** | **46.4GB image, GPU access, API server healthy** |

## Docker Deployment Success

The Docker image `openmtx/vllm-rocm-gfx1151:latest` has been successfully built and tested:

### Build Results
- **Image Size:** 46.4GB
- **Architecture:** AMD Strix Halo (gfx1151)
- **Container:** vllm-strix-halo
- **Status:** Healthy API server running on port 8080

### Verification

**GPU Access:**
```bash
docker exec vllm-strix-halo rocm-smi
# Output: Device 0 detected (0x1586, gfx1151), VRAM 38% usage
```

**API Health Check:**
```bash
curl http://localhost:8080/health
# Returns: 200 OK (Application startup complete)
```

**Generate Text:**
```bash
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-0.5B-Instruct", "prompt": "Write a haiku about AI", "max_tokens": 50}'
# Returns: Generated text with 50 tokens
```

### Start the Container

```bash
# Using docker-compose
docker compose up -d

# Or manually
docker run -d \
  --name vllm-strix-halo \
  --gpus all \
  --device /dev/kfd:/dev/kfd \
  --device /dev/dri:/dev/dri \
  -p 8080:8080 \
  -v $(pwd)/cache/huggingface:/root/.cache/huggingface \
  openmtx/vllm-rocm-gfx1151:latest \
  vllm serve Qwen/Qwen2.5-0.5B-Instruct \
    --host 0.0.0.0 \
    --port 8080 \
    --enforce-eager
```

### Model Loading

- **Model:** Qwen/Qwen2.5-0.5B-Instruct
- **Download Time:** ~15 seconds
- **Load Time:** ~0.25 seconds
- **VRAM Usage:** 1.0 GB (38% of total)
- **Backend:** Triton Attention (ROCm)

## Acknowledgments

This project is based on pioneering work by **Donato Capitella** ([amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes)).

**Key improvements in this fork:**
- Multi-stage Docker builds for optimized runtime images
- CPU-only build support for CI/CD (no GPU required)
- Simplified version management via build arguments
- Integrated Flash Attention and AITER builds (not available in original)
- Pre-built wheels for all components

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [ROCm TheRock](https://github.com/ROCm/TheRock) - AMD's nightly build system
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for Linux distributions

## License

This project follows the same license as vLLM (Apache 2.0).
