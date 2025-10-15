#!/bin/bash
# run.sh

module load cuda/11.8.0-gcc-7.2.0-xqzqlf2

CONTAINER=$HOME/isaac_gym.sif
ISAACGYM_PATH=$HOME/isaacgym
LEGGED_GYM_PATH=$HOME/legged_gym
RSL_RL_PATH=$HOME/rsl_rl

# Build library binding flags
lib_bind_flags=""
for lib in /usr/lib64/{libnvidia-*,libEGL_*,libGLX_*,libvulkan*}; do
    [ -e "$lib" ] && lib_bind_flags+=" --bind $lib:/usr/lib/x86_64-linux-gnu/$(basename $lib)"
done
lib_bind_flags+=" --bind /usr/lib64/libGLX_nvidia.so.0:/usr/lib64/libGLX_nvidia.so.0"
lib_bind_flags+=" --bind /usr/share/vulkan/icd.d/nvidia_icd.x86_64.json:/usr/share/vulkan/icd.d/nvidia_icd.json"
lib_bind_flags+=" --bind /usr/share/vulkan/implicit_layer.d/nvidia_layers.json:/usr/share/vulkan/implicit_layer.d/nvidia_layers.json"
lib_bind_flags+=" --bind /usr/share/glvnd/egl_vendor.d/10_nvidia.json:/usr/share/glvnd/egl_vendor.d/10_nvidia.json"

apptainer exec --nv \
  $lib_bind_flags \
  --bind $ISAACGYM_PATH:/workspace/isaacgym \
  --bind $LEGGED_GYM_PATH:/workspace/legged_gym \
  --bind $RSL_RL_PATH:/workspace/rsl_rl \
  --env LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib64:$LD_LIBRARY_PATH \
  --env PYTHONPATH=/workspace/rsl_rl:/workspace/legged_gym:$PYTHONPATH \
  $CONTAINER \
  bash -c "
    # Install if needed
    python3 -c 'import rsl_rl' 2>/dev/null || (cd /workspace/rsl_rl && pip3 install -e . --user)
    python3 -c 'import legged_gym' 2>/dev/null || (cd /workspace/legged_gym && pip3 install -e . --user)
    
    # Start VNC
    Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
    XVFB_PID=\$!
    export DISPLAY=:99
    sleep 3
    fluxbox -display :99 > /dev/null 2>&1 &
    sleep 2
    x11vnc -display :99 -forever -shared -nopw -quiet &
    
    echo '========================================'
    echo 'VNC Server running on: '\$(hostname)
    echo 'From your laptop run:'
    echo 'ssh -L 5900:'\$(hostname)':5900 kanth042@agate.msi.umn.edu'
    echo 'Then connect VNC viewer to: localhost:5900'
    echo '========================================'
    
    # Run training
    cd /workspace/legged_gym
    python3 legged_gym/scripts/train.py --task=anymal_c_flat --num_envs=256
    
    kill \$XVFB_PID
  "