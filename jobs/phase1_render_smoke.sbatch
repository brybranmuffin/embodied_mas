#!/bin/bash
#SBATCH --job-name=mas_render_smoke
#SBATCH --account=e32706
#SBATCH --partition=gengpu
#SBATCH --gres=gpu:a100:1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=00:20:00
#SBATCH --output=/scratch/rsr7518/embodied_mas_data/results/phase1/slurm-%j.out

# Phase 1 rendering smoke test (HANDOFF.md section 7).
# Records what the GPU node provides, starts Xvfb and one simulator, and saves one camera image.
# Also records whether compute nodes have outbound internet (no API calls are made).

set -uo pipefail
umask 007

ROOT=/scratch/rsr7518/embodied_mas_data
REPO_JOBS=${REPO_JOBS:-$SLURM_SUBMIT_DIR}
OUT=$ROOT/results/phase1/job_$SLURM_JOB_ID
mkdir -p "$OUT"
SIM_BIN=$ROOT/simulator/linux_simulator/linux.x86_64
PY=$ROOT/envs/mecobench/bin/python

D=$((100 + SLURM_JOB_ID % 800))
PORT=$((20000 + SLURM_JOB_ID % 20000))

cleanup() { kill $(jobs -p) 2>/dev/null; sleep 2; kill -9 $(jobs -p) 2>/dev/null; }
trap cleanup EXIT

echo "== node =="; hostname; date
echo "== nvidia-smi =="; nvidia-smi
echo "== Xvfb =="; which Xvfb xvfb-run 2>&1
echo "== Vulkan ICD files =="; ls -l /usr/share/vulkan/icd.d/ /etc/vulkan/icd.d/ 2>&1
echo "== libraries =="; ldconfig -p | grep -i -E "vulkan|GLX_nvidia|EGL_nvidia"
echo "== outbound internet from compute node =="
for url in https://api.openai.com https://huggingface.co https://github.com; do
  echo "$url -> $(curl -sI -m 10 -o /dev/null -w '%{http_code}' "$url" 2>&1 || echo unreachable)"
done

# Use the system NVIDIA ICD if present; otherwise write our own (handoff fallback 1).
ICD=$(ls /usr/share/vulkan/icd.d/nvidia_icd*.json /etc/vulkan/icd.d/nvidia_icd*.json 2>/dev/null | head -1)
if [ -z "$ICD" ]; then
  ICD=$OUT/nvidia_icd.json
  echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.0"}}' > "$ICD"
  echo "no system NVIDIA ICD; wrote $ICD"
fi
export VK_ICD_FILENAMES=$ICD
echo "VK_ICD_FILENAMES=$VK_ICD_FILENAMES"

# Quest GPU nodes have no Xvfb, so we use our own copy (conda-forge build plus one CentOS 7 library).
XVFB_ENV=$ROOT/envs/xvfb
XVFB_BIN=$XVFB_ENV/x86_64-conda-linux-gnu/sysroot/usr/bin/Xvfb
echo "== system xkb =="; ls -d /usr/bin/xkbcomp /usr/share/X11/xkb 2>&1

echo "== starting Xvfb :$D =="
LD_LIBRARY_PATH=$XVFB_ENV/compat PATH=$XVFB_ENV/bin:$PATH \
  "$XVFB_BIN" :$D -screen 0 1024x768x24 -nolisten tcp -xkbdir "$XVFB_ENV/share/X11/xkb" > "$OUT/xvfb.log" 2>&1 &
XVFB_PID=$!
export DISPLAY=:$D
for i in $(seq 1 20); do [ -S /tmp/.X11-unix/X$D ] && break; sleep 1; done
if ! kill -0 $XVFB_PID 2>/dev/null || [ ! -S /tmp/.X11-unix/X$D ]; then
  echo "FAIL: Xvfb did not start"; cat "$OUT/xvfb.log"; exit 2
fi
echo "Xvfb is up"; cat "$OUT/xvfb.log"

echo "== starting simulator on port $PORT =="
"$SIM_BIN" -batchmode -http-port=$PORT -force-device-index 0 -logFile "$OUT/unity.log" &

"$PY" "$REPO_JOBS/phase1_render_check.py" $PORT "$OUT"
RC=$?

echo "== simulator GPU use =="; nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv
echo "== unity.log (renderer lines) =="; grep -i -E "vulkan|opengl|renderer|graphics device|error" "$OUT/unity.log" | head -30
echo "render check exit code: $RC"
exit $RC
