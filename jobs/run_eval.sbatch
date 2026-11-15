#!/bin/bash
#SBATCH --job-name=mas_eval
#SBATCH --account=e32706
#SBATCH --partition=gengpu
#SBATCH --gres=gpu:2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=01:00:00
#SBATCH --output=/scratch/rsr7518/embodied_mas_data/results/slurm_logs/slurm-%j.out

# Runs one MECoBench evaluation batch end to end: Xvfb, vLLM (GPU 0), K simulators (GPU 1), eval/main.py.
# Everything is set through environment variables, e.g.
#   sbatch --export=ALL,RUN_NAME=phase3_examples,VWAH_NUM_AGENTS=2 jobs/run_eval.sbatch
# Resolver decision (Bryant, 2026-11-15): local Qwen model, no OpenAI calls, embedding filter off.

set -uo pipefail
umask 007

ROOT=${MAS_ROOT:-/scratch/rsr7518/embodied_mas_data}
MECO=$ROOT/MECoBench
SIM_BIN=$ROOT/simulator/linux_simulator/linux.x86_64
XVFB_ENV=$ROOT/envs/xvfb

# ---- what to run (defaults = Phase 3 first run) ----
RUN_NAME=${RUN_NAME:-phase3_examples}
NUM_SIMS=${NUM_SIMS:-5}
export VWAH_TASK_FILE=${VWAH_TASK_FILE:-data/examples/parallel_5.json}
export VWAH_TASK_ID_LIST=${VWAH_TASK_ID_LIST:-}
export VWAH_NUM_AGENTS=${VWAH_NUM_AGENTS:-2}
export VWAH_COMMUNICATION_MODE=${VWAH_COMMUNICATION_MODE:-base}
export VWAH_STEPS_THRESHOLD=${VWAH_STEPS_THRESHOLD:-30}
export VWAH_LEADER_COMM_MODE=${VWAH_LEADER_COMM_MODE:-text_only}
export VWAH_UNITY_HTTP_TIMEOUT=${VWAH_UNITY_HTTP_TIMEOUT:-180}

OUT=$ROOT/results/$RUN_NAME/job_$SLURM_JOB_ID
mkdir -p "$OUT"
export VWAH_OUTPUT_ROOT=$OUT

# ---- unique display and ports for this job ----
D=$((100 + SLURM_JOB_ID % 800))
export UNITY_BASE_PORT=$((20000 + SLURM_JOB_ID % 19000))
export UNITY_NUM_SIMULATORS=$NUM_SIMS
VLLM_PORT=$((40000 + SLURM_JOB_ID % 20000))

# ---- model: same local model for agents and resolver ----
SERVED=qwen-8b-vl
export VLM_MAIN_MODEL=$SERVED VLM_LEADER_MODEL=$SERVED VLM_WORKER_MODEL=$SERVED VLM_RESOLVE_MODEL=$SERVED
export VLM_USE_EMBEDDING_FILTER=0
export QWEN_8B_BASE_URL=http://localhost:$VLLM_PORT/v1
export QWEN_API_KEY=EMPTY OPENAI_API_KEY=EMPTY
export HF_HOME=$ROOT/hf_cache HF_HUB_OFFLINE=1
export VLLM_USE_FLASHINFER_SAMPLER=0     # see STATUS.md, Phase 2

cleanup() { kill $(jobs -p) 2>/dev/null; sleep 3; kill -9 $(jobs -p) 2>/dev/null; }
trap cleanup EXIT

echo "job $SLURM_JOB_ID on $(hostname) at $(date)"; nvidia-smi --query-gpu=index,name,memory.total --format=csv
env | grep -E "^(VWAH_|VLM_|UNITY_|QWEN_8B)" | sort

# ---- 1. Xvfb ----
LD_LIBRARY_PATH=$XVFB_ENV/compat PATH=$XVFB_ENV/bin:$PATH \
  "$XVFB_ENV/x86_64-conda-linux-gnu/sysroot/usr/bin/Xvfb" :$D -screen 0 1024x768x24 -nolisten tcp \
  -xkbdir "$XVFB_ENV/share/X11/xkb" > "$OUT/xvfb.log" 2>&1 &
export DISPLAY=:$D
for i in $(seq 1 20); do [ -S /tmp/.X11-unix/X$D ] && break; sleep 1; done
[ -S /tmp/.X11-unix/X$D ] || { echo "FAIL: Xvfb did not start"; cat "$OUT/xvfb.log"; exit 2; }

# ---- 2. vLLM on GPU 0 ----
T0=$SECONDS
CUDA_VISIBLE_DEVICES=0 "$ROOT/envs/vllm/bin/vllm" serve Qwen/Qwen3-VL-8B-Instruct --served-model-name $SERVED \
  --port $VLLM_PORT --max-model-len 49152 --gpu-memory-utilization 0.90 > "$OUT/vllm.log" 2>&1 &
VLLM_PID=$!

# ---- 3. simulators on GPU 1 ----
export VK_ICD_FILENAMES=$(ls /usr/share/vulkan/icd.d/nvidia_icd*.json | head -1)
for i in $(seq 0 $((NUM_SIMS - 1))); do
  "$SIM_BIN" -batchmode -http-port=$((UNITY_BASE_PORT + i)) -force-device-index 1 -logFile "$OUT/unity_$i.log" > /dev/null 2>&1 &
done

# ---- 4. wait until everything is ready ----
for i in $(seq 0 $((NUM_SIMS - 1))); do
  P=$((UNITY_BASE_PORT + i))
  until (exec 3<>/dev/tcp/127.0.0.1/$P) 2>/dev/null; do
    [ $((SECONDS - T0)) -gt 600 ] && { echo "FAIL: simulator on port $P not ready after 10 minutes"; exit 3; }
    sleep 3
  done
done
echo "all $NUM_SIMS simulators ready after $((SECONDS - T0))s"
until curl -sf -m 5 http://localhost:$VLLM_PORT/v1/models > /dev/null; do
  kill -0 $VLLM_PID 2>/dev/null || { echo "FAIL: vLLM exited during startup"; tail -n 40 "$OUT/vllm.log"; exit 4; }
  [ $((SECONDS - T0)) -gt 1200 ] && { echo "FAIL: vLLM not ready after 20 minutes"; exit 5; }
  sleep 5
done
echo "vLLM ready after $((SECONDS - T0))s"

# ---- 5. run the evaluation ----
cd "$MECO"
cat > "$OUT/run.json" <<EOF
{"job_id": "$SLURM_JOB_ID", "run_name": "$RUN_NAME", "node": "$(hostname)", "mecobench_commit": "$(git rev-parse HEAD)",
 "mecobench_dirty": $( [ -z "$(git status --porcelain)" ] && echo false || echo true ),
 "model": "Qwen/Qwen3-VL-8B-Instruct", "resolver": "$VLM_RESOLVE_MODEL", "embedding_filter": "$VLM_USE_EMBEDDING_FILTER",
 "task_file": "$VWAH_TASK_FILE", "task_id_list": "$VWAH_TASK_ID_LIST", "num_agents": $VWAH_NUM_AGENTS,
 "communication_mode": "$VWAH_COMMUNICATION_MODE", "steps_threshold": $VWAH_STEPS_THRESHOLD, "num_simulators": $NUM_SIMS}
EOF
T1=$SECONDS
"$ROOT/envs/mecobench/bin/python" eval/main.py
RC=$?
echo "eval/main.py exit code $RC after $((SECONDS - T1))s"
nvidia-smi --query-gpu=index,memory.used --format=csv
exit $RC
