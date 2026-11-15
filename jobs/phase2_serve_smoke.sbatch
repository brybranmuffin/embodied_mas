#!/bin/bash
#SBATCH --job-name=mas_serve_smoke
#SBATCH --account=e32706
#SBATCH --partition=gengpu
#SBATCH --gres=gpu:1
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/rsr7518/embodied_mas_data/results/phase2/slurm-%j.out

# Phase 2 model-serving smoke test (HANDOFF.md section 7).
# Serves Qwen3-VL-8B with vLLM, waits until it is ready, and sends one image chat completion.

set -uo pipefail
umask 007

ROOT=/scratch/rsr7518/embodied_mas_data
REPO_JOBS=${REPO_JOBS:-$SLURM_SUBMIT_DIR}
OUT=$ROOT/results/phase2/job_$SLURM_JOB_ID
mkdir -p "$OUT"

export HF_HOME=$ROOT/hf_cache
export HF_HUB_OFFLINE=1          # weights are already in the shared cache
# vLLM 0.33's FlashInfer sampler compiles CUDA code at startup (needs nvcc and ninja, which Quest
# nodes do not have on PATH) and crashes. Use the built-in PyTorch sampler instead.
export VLLM_USE_FLASHINFER_SAMPLER=0
MODEL=Qwen/Qwen3-VL-8B-Instruct
SERVED=qwen-8b-vl
VLLM_PORT=$((40000 + SLURM_JOB_ID % 20000))   # separate range from simulator ports (20000-39999)
IMAGE=${IMAGE:-$(ls $ROOT/results/phase1/job_*/camera_1.png | tail -1)}

cleanup() { kill $(jobs -p) 2>/dev/null; sleep 3; kill -9 $(jobs -p) 2>/dev/null; }
trap cleanup EXIT

hostname; date; nvidia-smi --query-gpu=name,memory.total --format=csv

T0=$SECONDS
"$ROOT/envs/vllm/bin/vllm" serve $MODEL --served-model-name $SERVED --port $VLLM_PORT \
  --max-model-len 49152 --gpu-memory-utilization 0.90 > "$OUT/vllm.log" 2>&1 &
VLLM_PID=$!

echo "waiting for vLLM on port $VLLM_PORT"
until curl -sf -m 5 http://localhost:$VLLM_PORT/v1/models > /dev/null; do
  if ! kill -0 $VLLM_PID 2>/dev/null; then
    echo "FAIL: vLLM exited during startup"; tail -n 60 "$OUT/vllm.log"; exit 2
  fi
  if [ $((SECONDS - T0)) -gt 1200 ]; then
    echo "FAIL: vLLM not ready after 20 minutes"; tail -n 60 "$OUT/vllm.log"; exit 3
  fi
  sleep 5
done
echo "vLLM ready after $((SECONDS - T0))s"
nvidia-smi --query-gpu=memory.used --format=csv

"$ROOT/envs/mecobench/bin/python" "$REPO_JOBS/phase2_serve_check.py" http://localhost:$VLLM_PORT/v1 $SERVED "$IMAGE"
RC=$?
echo "serve check exit code: $RC"
exit $RC
