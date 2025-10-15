#!/bin/bash

# ============================================================
# Container Build Script for UMN MSI
# ============================================================
# This builds the Isaac Gym container using Apptainer/Singularity
# without requiring root/sudo access.
#
# WHY --fakeroot?
# - HPC clusters don't allow sudo
# - --fakeroot simulates root inside the build environment
# - This is sufficient for installing packages via apt/pip
#
# BUILD TIME: ~10-15 minutes
# DISK SPACE: Container will be ~4-5 GB
# ============================================================

echo "Building Isaac Gym container..."
echo "This will take approximately 10-15 minutes."
echo ""

# Build using fakeroot (no sudo required)
# The container will be saved to ~/isaac_gym.sif
apptainer build --fakeroot $HOME/isaac_gym.sif isaac_gym.def

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Build complete!"
    echo "Container saved to: $HOME/isaac_gym.sif"
    echo ""
    echo "Next step: Run ./run_isaac_gym_vnc.sh"
else
    echo ""
    echo "✗ Build failed!"
    echo "Common issues:"
    echo "  - Out of memory: Request more RAM (--mem=128gb)"
    echo "  - Disk space: Check quota with 'quota -s'"
    echo "  - APPTAINER_TMPDIR not set: Make sure you exported it"
fi