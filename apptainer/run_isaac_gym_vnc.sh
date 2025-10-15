#!/bin/bash

# ============================================================
# Isaac Gym VNC Runtime Script for UMN MSI
# ============================================================
# This script runs Isaac Gym with GUI support via VNC.
#
# KEY PROBLEM IT SOLVES:
# UMN MSI compute nodes run Rocky Linux, but our container runs
# Ubuntu. These systems store libraries in different locations:
#   - Rocky Linux: /usr/lib64/
#   - Ubuntu:      /usr/lib/x86_64-linux-gnu/
#
# The standard --nv flag doesn't handle this mismatch, so we
# manually bind the specific NVIDIA/Vulkan libraries needed.
#
# ARCHITECTURE:
# 1. Load CUDA module from host
# 2. Bind NVIDIA/Vulkan libraries from host to container
# 3. Start virtual display (Xvfb)
# 4. Start VNC server for remote access
# 5. Run Isaac Gym
# ============================================================

# ============================================================
# STEP 1: Load Host CUDA Module
# ============================================================
# MSI provides CUDA through environment modules
# This ensures the host driver is properly initialized
module load cuda/11.8.0-gcc-7.2.0-xqzqlf2

# ============================================================
# STEP 2: Define Paths
# ============================================================
CONTAINER=$HOME/isaac_gym.sif
ISAACGYM_PATH=$HOME/isaacgym

# Verify paths exist
if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Container not found at $CONTAINER"
    echo "Did you run build_container.sh?"
    exit 1
fi

if [ ! -d "$ISAACGYM_PATH" ]; then
    echo "ERROR: Isaac Gym not found at $ISAACGYM_PATH"
    echo "Please download Isaac Gym Preview 4 to ~/isaacgym/"
    exit 1
fi

# ============================================================
# STEP 3: Build Library Binding Flags
# ============================================================
# WHY: Rocky Linux stores libs in /usr/lib64/, but Ubuntu
#      containers expect them in /usr/lib/x86_64-linux-gnu/
#
# WHAT WE BIND:
# - libnvidia-*    : NVIDIA driver libraries
# - libEGL_*       : EGL libraries for offscreen rendering
# - libGLX_*       : GLX libraries for X11 OpenGL
# - libvulkan*     : Vulkan loader and related
#
# WHY SELECTIVE: Binding the entire /usr/lib64/ would include
#                system libraries like glibc that conflict with
#                the container's versions. We only bind GPU libs.

lib_bind_flags=""

# Loop through GPU-related libraries only
for lib in /usr/lib64/{libnvidia-*,libEGL_*,libGLX_*,libvulkan*}; do
    if [ -e "$lib" ]; then
        # Bind host library to Ubuntu's expected location
        lib_bind_flags+=" --bind $lib:/usr/lib/x86_64-linux-gnu/$(basename $lib)"
    fi
done

# ============================================================
# STEP 4: Bind Critical Libraries with Absolute Paths
# ============================================================
# WHY: The nvidia_icd.json file uses an absolute path:
#      /usr/lib64/libGLX_nvidia.so.0
# We must bind this file to the exact same path in the container,
# otherwise Vulkan can't find the NVIDIA ICD loader.
lib_bind_flags+=" --bind /usr/lib64/libGLX_nvidia.so.0:/usr/lib64/libGLX_nvidia.so.0"

# ============================================================
# STEP 5: Bind Vulkan Configuration Files
# ============================================================
# WHY: Vulkan needs these JSON files to find the NVIDIA driver
#
# WHAT THEY DO:
# - nvidia_icd.json      : Tells Vulkan where to find NVIDIA's ICD
# - nvidia_layers.json   : Defines Vulkan layers (e.g., Optimus)
# - 10_nvidia.json       : Tells EGL where to find NVIDIA's implementation
#
# NOTE: Some clusters have nvidia_icd.x86_64.json, but Vulkan
#       looks for nvidia_icd.json, so we bind the former to the latter.

# Check if files exist on host
if [ ! -f "/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json" ]; then
    echo "WARNING: nvidia_icd.x86_64.json not found on host"
    echo "Vulkan rendering may not work. Check your NVIDIA driver installation."
fi

lib_bind_flags+=" --bind /usr/share/vulkan/icd.d/nvidia_icd.x86_64.json:/usr/share/vulkan/icd.d/nvidia_icd.json"
lib_bind_flags+=" --bind /usr/share/vulkan/implicit_layer.d/nvidia_layers.json:/usr/share/vulkan/implicit_layer.d/nvidia_layers.json"
lib_bind_flags+=" --bind /usr/share/glvnd/egl_vendor.d/10_nvidia.json:/usr/share/glvnd/egl_vendor.d/10_nvidia.json"

# ============================================================
# STEP 6: Run Container with VNC
# ============================================================
echo "Starting Isaac Gym with VNC..."
echo ""

apptainer exec \
  --nv \
  $lib_bind_flags \
  --bind $ISAACGYM_PATH:/workspace/isaacgym \
  --env LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib64:$LD_LIBRARY_PATH \
  $CONTAINER \
  bash -c "
    # ========================================================
    # INSIDE CONTAINER: Setup Virtual Display
    # ========================================================
    
    # Start Xvfb (X Virtual FrameBuffer)
    # This creates a virtual display :99 that Isaac Gym can render to
    # even though there's no physical monitor
    #
    # OPTIONS:
    # :99           - Display number
    # -screen 0     - Screen number
    # 1920x1080x24  - Resolution and color depth
    # -ac           - Disable access control (allow all connections)
    # +extension GLX - Enable OpenGL extension (required for GPU rendering)
    # +render       - Enable RENDER extension
    # -noreset      - Don't reset when last client disconnects
    Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
    XVFB_PID=\$!
    
    # Set DISPLAY environment variable so apps know where to render
    export DISPLAY=:99
    
    # Wait for Xvfb to start
    sleep 3
    
    # Start a window manager (fluxbox)
    # WHY: Some apps expect a window manager to be present
    #      even if we're not using the windows interactively
    fluxbox -display :99 > /dev/null 2>&1 &
    sleep 2
    
    # Start x11vnc server
    # This streams the Xvfb display over VNC so we can view it remotely
    #
    # OPTIONS:
    # -display :99  - Connect to our Xvfb display
    # -forever      - Keep running after client disconnects
    # -shared       - Allow multiple VNC clients
    # -nopw         - No password (safe on internal cluster network)
    # -quiet        - Reduce log output
    x11vnc -display :99 -forever -shared -nopw -quiet &
    
    echo '================================'
    echo 'VNC Server is running!'
    echo 'Node: '\$(hostname)
    echo 'Port: 5900'
    echo ''
    echo 'From your LOCAL machine, run:'
    echo 'ssh -L 5900:'\$(hostname)':5900 $USER@agate.msi.umn.edu'
    echo ''
    echo 'Then connect VNC viewer to: localhost:5900'
    echo '================================'
    echo ''
    
    # ========================================================
    # INSIDE CONTAINER: Run Isaac Gym
    # ========================================================
    cd /workspace/isaacgym/python/examples
    
    # Run the joint_monkey example
    # This demonstrates Isaac Gym with 36 parallel environments
    # showing humanoid robots with animated joints
    python3 joint_monkey.py
    
    # ========================================================
    # CLEANUP
    # ========================================================
    # Kill Xvfb when Isaac Gym exits
    kill \$XVFB_PID
  "

# ============================================================
# NOTES FOR ADAPTATION TO OTHER CLUSTERS
# ============================================================
#
# If you're adapting this to a different cluster:
#
# 1. CHECK HOST OS:
#    cat /etc/os-release
#    - If Rocky/CentOS/RHEL: Use this script as-is
#    - If Ubuntu: You might not need library binding at all
#
# 2. FIND NVIDIA LIBRARIES:
#    ls /usr/lib64/libnvidia-* 2>/dev/null
#    - If found: Use this script
#    - If not found: Check /usr/lib/x86_64-linux-gnu/libnvidia-*
#
# 3. CHECK VULKAN FILES:
#    ls /usr/share/vulkan/icd.d/nvidia_icd*.json
#    - Update binding paths if file names differ
#    - If missing: You'll need to create them (see ManiSkill docs)
#
# 4. UPDATE MODULE LOAD:
#    module avail cuda  # Check available CUDA modules
#    # Update the 'module load' line above
#
# 5. TEST INCREMENTALLY:
#    - First test: GPU access (nvidia-smi in container)
#    - Second test: PyTorch + CUDA
#    - Third test: EGL rendering
#    - Fourth test: Full Isaac Gym with VNC
#
# ============================================================