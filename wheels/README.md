# Pre-built Wheels

This directory contains pre-built wheels for CI/CD environments without GPU access.

## amd_aiter-0.0.0-cp312-cp312-linux_x86_64.whl

Built in distrobox toolbox with GPU (gfx1151):
- ROCm 7.12.0a20260213
- PyTorch 2.9.1+rocm7.12.0a20260208
- PYTORCH_ROCM_ARCH=gfx1151

To rebuild this wheel:
1. Fresh toolbox: `./00-provision-toolbox.sh -f`
2. Install tools: `./01-install-tools.sh`
3. Install ROCm: `./02-install-rocm.sh`
4. Build AITER: `./03-build-aiter.sh`
5. Copy wheel: `cp /workspace/wheels/*.whl ./wheels/`

Note: The GitHub Actions Docker build may fail to build AITER due to missing GPU,
but this pre-built wheel will be used instead.
