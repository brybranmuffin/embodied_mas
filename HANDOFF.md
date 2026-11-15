# Handoff: Embodied Agent Scaling Experiments on Quest

**For:** a Claude Code agent starting the experiment pipeline
**From:** Bryant Bettencourt (with Natasha Dhanrajani and Simron Patel), Northwestern
**Written:** 2026-11-15 · **Hard deadline for the whole project:** 2026-12-02

> **Note to the human handing this over:** fill in the placeholders in section 9
> (allocation ID, NetIDs, shared paths) before you give this to the agent, and run
> the agent where it has a shell on a Quest login node (directly, or over SSH).

---

## 1. Your mission

Get the MECoBench embodied multi-agent benchmark running on Northwestern's Quest
cluster, then build the job pipeline that runs our experiment grid across three
team members' accounts. You are building infrastructure and running pilots. You
are **not** writing the paper or doing the final analysis.

You are done when:

1. One MECoBench episode runs end to end on a Quest GPU compute node and
   produces a `result.json` (Phase 1–3).
2. We know whether teams of 7 and 9 agents can be spawned, and have a code
   patch if they can (Phase 4).
3. A Slurm job template runs one experiment cell from start to finish with no
   manual steps, on any of the three accounts (Phase 5).
4. A pilot has been timed, and a run manifest of every job for the full grid
   exists, split into three shards (Phase 6).
5. An aggregation script turns all `result.json` files into one CSV (Phase 7).
6. `STATUS.md` (section 8) is up to date at every stopping point.

## 2. The research in one paragraph

We are testing whether multi-agent scaling patterns found for text-based LLM
agents (Kim et al. 2025, "Towards a Science of Scaling Agent Systems",
arXiv:2512.08296) hold for embodied agents. We run a single agent and several
multi-agent team designs at several team sizes in VirtualHome household tasks,
and measure success, steps to finish and tokens. MECoBench (Liu et al. 2026,
arXiv:2606.31966) is our testbed because its code, simulator and tasks are
public. A second question (why performance drops past an optimal team size) is
a stretch goal and **out of scope for you**.

## 3. Scope decisions already made (do not reopen without asking)

| Factor | Values | Notes |
|---|---|---|
| Team designs | single agent (`VWAH_NUM_AGENTS=1`), `no_comm`, `base`, `leader_worker` | Map to Kim et al.'s Single, Independent, Decentralized, Centralized. No Hybrid unless humans ask. |
| Team sizes | 1, 2, 3, 5 first; 7 and 9 only if Phase 4 succeeds | n=1 only needs running once per model/budget (mode is irrelevant). |
| Models | Qwen3-VL-8B first; Qwen3-VL-32B second | Same model for every agent, including the leader. |
| Tasks | ~24 tasks from the full `parallel.json` | Selected and labeled in Phase 6. Do not use `sequential.json` (fixed 2-agent room zones). |
| Budgets | action-matched and time-matched | Defined in section 5. |
| Seeds | 1 to start; 2 if the pilot says we can afford it | Requires the seed patch in Phase 4. |

## 4. Facts verified from the MECoBench code

Checked against `github.com/q-i-n-g/MECoBench`, commit `219d429` (2026-07-01).
Re-check if the repo has moved on.

**Setup**
- Python 3.10 conda env from `environment.yml`; `requirements.txt` installs the
  repo's modified VirtualHome API with `pip install -e ./virtualhome`. The stock
  VirtualHome package will not work.
- Simulator: `simulator_linux.zip` from the repo's release `v1`
  (`https://github.com/q-i-n-g/MECoBench/releases/download/v1/simulator_linux.zip`).
  Its binary path goes in `MECOBENCH_SIMULATOR_BIN`.
- Full tasks: Hugging Face dataset `q-i-n-g/MECoBench`, files
  `task/parallel.json` and `task/sequential.json`, placed in `data/task/`.
- Model config: `eval/agents/models.json`, endpoints and keys from
  `eval/agents/.env` (copy from `.env.example`).

**Rendering: the simulator uses the GPU, not just the CPU**
- `src/start_screen.sh` is one line: `Xvfb :1 -screen 0 1024x768x24`.
- `src/start_unity_multi_8gpu.sh` sets
  `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json` and launches each
  simulator as `$BIN -batchmode -http-port=$PORT -force-device-index $GPU`.
  So Unity renders through **Vulkan on an NVIDIA GPU**, with Xvfb as the display.
  Simulator jobs need a GPU and a working NVIDIA Vulkan driver.

**How a run works**
- Entry point: `python eval/main.py`, configured entirely by environment variables.
- One worker process per simulator port (`UNITY_BASE_PORT` …
  `UNITY_BASE_PORT + UNITY_NUM_SIMULATORS - 1`); each simulator runs one case at a time.
- Output: `$VWAH_OUTPUT_ROOT/batch_<timestamp>/case_<idx>/result.json`, plus a
  `summary.json` per batch and per-step logs and images.
- `result.json` fields: `case_idx`, `success`, `completion_rate`,
  `satisfied_count`, `total_count`, `steps`, `token_usage` (per role: main,
  resolver, embedding), `token_usage_estimate_total`, `error`.

**Environment variables that matter**

| Variable | Meaning | Our setting |
|---|---|---|
| `VWAH_TASK_FILE` | task JSON | `data/task/parallel.json` |
| `VWAH_TASK_ID_LIST` | comma-separated case indices | from the manifest |
| `VWAH_NUM_AGENTS` | team size | 1, 2, 3, 5 (7, 9) |
| `VWAH_COMMUNICATION_MODE` | `base`, `no_comm`, `discuss_then_act`, `leader_worker`, `shared_memory` | `no_comm`, `base`, `leader_worker` |
| `VWAH_STEPS_THRESHOLD` | max **team rounds**; every agent acts once per round | see section 5 |
| `VWAH_OUTPUT_ROOT` | output root | see section 7 |
| `VWAH_GOAL_MODE` | goal text variant | leave default `goal_with_location_and_desc` |
| `VWAH_LEADER_COMM_MODE` | leader_worker only | `text_only` |
| `VLM_MAIN_MODEL` / `VLM_LEADER_MODEL` / `VLM_WORKER_MODEL` | model aliases in `models.json` | all the same model |
| `VLM_RESOLVE_MODEL` | model that maps action text to object IDs | see the warning below |
| `VLM_EMBEDDING_MODEL`, `VLM_USE_EMBEDDING_FILTER` | candidate filtering by embeddings | see the warning below |
| `UNITY_BASE_PORT`, `UNITY_NUM_SIMULATORS` | simulator ports and parallelism | unique per job |
| `VWAH_UNITY_HTTP_TIMEOUT` | seconds, default 60 | raise if renders time out |

**Five things that will bite you**
1. **OpenAI calls by default.** `VLM_RESOLVE_MODEL` defaults to `gpt-5-mini-2`
   and `VLM_EMBEDDING_MODEL` to `text-embedding-3-large`, both through
   `OPENAI_API_KEY`/`OPENAI_BASE_URL`. The embedding client is constructed even
   when the filter is off, and the OpenAI client errors on an empty key, so set a
   dummy key (`EMPTY`) when not using OpenAI. **Ask the humans** whether to use
   the OpenAI API (matches the paper; costs money; needs outbound internet from
   compute nodes) or run the resolver locally (free; results won't match the
   paper exactly). Record the decision in `STATUS.md`.
2. **Port clash.** `models.json`/`.env.example` put Qwen-32B at
   `localhost:8001`, the same as the default `UNITY_BASE_PORT`. Use a separate
   port range for vLLM.
3. **Team size is capped at 5 by the data.** `data/chars/profile_sample.json`
   defines agents `"0"`–`"4"`, and `Scene.initialize` raises
   `init_rooms does not provide an initial room for agent N` when a task's
   `init_rooms` list is shorter than the team. The example tasks have 5 entries.
   Teams of 7 and 9 need both lists extended (Phase 4).
4. **Seed is hard-coded.** `main.py` sets `seed = 123`; each case uses
   `123 + case_idx`. Multiple seeds need a small patch (Phase 4). Sampling
   temperature is 0.7, so repeat runs already differ somewhat.
5. **The provided launcher is not cluster-friendly.** `eval/exp_scripts/test_strong_leader.sh`
   uses `screen`, a fixed display `:1`, and fixed `sleep 300` waits. Write our own
   job script with readiness checks instead (Phase 5).

## 5. Budget definitions

`VWAH_STEPS_THRESHOLD` counts team rounds, not individual actions.

- **Action-matched** (the paper's protocol, our proxy for Kim et al.'s matched
  compute): total agent-actions fixed at 60, so
  `VWAH_STEPS_THRESHOLD = round(60 / n)` → n=1: 60, 2: 30, 3: 20, 5: 12, 7: 9, 9: 7.
- **Time-matched**: the same number of rounds for every team size, so bigger
  teams get more total actions. Start with `T = 30` and adjust after the pilot:
  pick T so a 3-agent `base` team rarely runs out of rounds. Confirm T with the
  humans before the full run.

Tokens are recorded per case either way, so we can also report tokens per success.

## 6. Quest facts

From Northwestern's Quest documentation (`rcdsdocs.it.northwestern.edu`):
- GPU partition `gengpu`: A100 (40/80 GB) and H100 (80 GB), NVIDIA driver 570.86.15.
- Max walltime 48 h. **At most 8 GPUs per user** across all running jobs.
- Request GPUs with `#SBATCH --partition=gengpu` and `#SBATCH --gres=gpu:a100:1`
  (or `h100`), plus `--account=<ALLOCATION>`. Check the GPU page for exact syntax.
- Interactive GPU sessions are available through Quest OnDemand, or `srun --pty` on `gengpu`.
- Singularity: `module load singularityce/4.3.1-gcc-8.5.0`. No image builds on
  Quest (needs root): build elsewhere and pull, or `singularity build --remote`.
  Use `--nv` for GPU access.
- **Unknown, check on day 1:** whether `Xvfb` exists on GPU nodes, whether a
  Vulkan ICD file exists, and whether compute nodes have outbound internet.
- Never run simulators, vLLM or evaluation on login nodes. Downloads and
  environment setup on login nodes are fine.

## 7. Phased plan

Work in order. Each phase has a check; do not start the next phase until it passes.

### Phase 0 — Workspace (login node)
- Fork or copy the repo into the team's shared project space
  (`<SHARED_ROOT>/MECoBench`), and put it under git so all three accounts use
  the same code. Commit every change we make to MECoBench there, with a short
  message saying why.
- Create the conda env (in shared space if possible, so all three accounts can use it).
- Download: simulator zip (unzip, `chmod +x` the `*.x86_64`), `parallel.json`,
  and model weights for the 8B model (`Qwen/Qwen3-VL-8B-Instruct`; verify the
  exact Hugging Face ID) into a shared cache (`HF_HOME`).
- Install vLLM in a separate env, at a version that supports Qwen3-VL (check its docs).
- **Check:** `python -c "import virtualhome.simulation.unity_simulator as u; print(u.UnityCommunication)"` works.

### Phase 1 — Rendering smoke test (interactive GPU node). Highest-risk step.
On one GPU node, in one shell:
1. `which Xvfb`; `ls /usr/share/vulkan/icd.d/ /etc/vulkan/icd.d/ 2>/dev/null`;
   `nvidia-smi`; `ldconfig -p | grep -i -E "vulkan|GLX_nvidia"`.
2. Start `Xvfb :$D -screen 0 1024x768x24 &` with a display number unlikely to
   clash (e.g. `100 + SLURM_JOB_ID % 800`), `export DISPLAY=:$D`.
3. Launch one simulator: `$MECOBENCH_SIMULATOR_BIN -batchmode -http-port=$P -force-device-index 0 &`.
4. From Python, connect with `UnityCommunication(port=P)`, reset environment 0,
   and request one camera image. Save it and look at it.

If it fails, try in this order and log each attempt in `STATUS.md`:
- **No NVIDIA ICD file:** write your own JSON
  (`{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.0"}}`)
  in your home directory and point `VK_ICD_FILENAMES` at it.
- **No Xvfb:** run Xvfb and the simulator inside a container (Ubuntu base with
  `xvfb` and the Vulkan loader, run with `--nv`).
- **Vulkan won't start:** try Unity's OpenGL backend (`-force-glcore`).

**Stop and report to the humans** if none works after about half a day. They
may need to ask `quest-help@northwestern.edu`; draft that email for them.

**Check:** a saved, non-black camera image from a compute node.

### Phase 2 — Model serving
- On a second GPU in the same job, serve the 8B model:
  `vllm serve Qwen/Qwen3-VL-8B-Instruct --served-model-name qwen-8b-vl --port <VLLM_PORT>`
  (add `--max-model-len` and `--gpu-memory-utilization` as needed).
- Set `QWEN_8B_BASE_URL=http://localhost:<VLLM_PORT>/v1` and `QWEN_API_KEY=EMPTY`.
- Resolver and embeddings: follow the humans' decision from section 4, item 1.
  - **Local option:** `VLM_RESOLVE_MODEL=qwen-8b-vl`, `VLM_USE_EMBEDDING_FILTER=0`,
    `OPENAI_API_KEY=EMPTY`.
  - **OpenAI option:** first test `curl -sI https://api.openai.com` from a compute node.
- **Check:** a chat completion with an image succeeds against the local endpoint.

### Phase 3 — First end-to-end run
- `VWAH_TASK_FILE=data/examples/parallel_5.json`, `VWAH_NUM_AGENTS=2`,
  `VWAH_COMMUNICATION_MODE=base`, `VWAH_STEPS_THRESHOLD=30`, 2–5 simulators.
- **Check:** 5 `result.json` files with `error: null`; read one log to confirm
  agents are acting sensibly.
- Then a rough reproduction on ~20 cases of the full `parallel.json`. The paper
  reports a success rate of about 0.458 for Qwen3-VL-8B with 2 agents on the
  parallel set. A local resolver may lower this. Report the number and the
  differences in setup; don't spend more than a few hours chasing a match.

### Phase 4 — Code patches (each a separate, documented commit)
1. **Seed:** read an optional `VWAH_SEED` env var (default 123) in `main.py`.
2. **Teams of 7 and 9:** add agents `"5"`–`"8"` to `profile_sample.json` using
   other VirtualHome character models, and extend each task's `init_rooms` at
   load time when it's shorter than the team (e.g. cycle through the task's
   existing rooms). Do not edit the downloaded task file itself.
   Test that 7 and 9 agents spawn and complete a few steps on 3 tasks.
   If they don't work by **Nov 18**, report it; the humans will likely cap team size at 5.
3. Anything else needed for clean runs. Keep the prompts untouched.

### Phase 5 — Slurm job template
Write `jobs/run_cell.sbatch` that runs one cell
(model × mode × team size × budget × task shard) with no manual steps:
1. Derive a unique display, simulator base port and vLLM port from `SLURM_JOB_ID`.
2. Start Xvfb, then vLLM, then K simulators; **poll until each is ready**
   (vLLM `/v1/models` responds; each simulator port accepts a connection).
3. Run `eval/main.py` with the cell's environment variables and
   `VWAH_OUTPUT_ROOT=<RESULTS_ROOT>/<model>/<budget>/<mode>/n<N>/seed<S>`.
4. Write a small `cell.json` beside the outputs recording every setting,
   the git commit and the job ID.
5. Kill everything on exit (`trap`), including after errors.

Suggested resources for the 8B model: 2 GPUs (one for vLLM, one for
simulators), enough CPUs and memory for K simulators; tune K in the pilot.
With the 8-GPU cap, that's 4 jobs at a time per account.

**Check:** the same cell runs successfully from all three accounts.

### Phase 6 — Pilot, task selection and run manifest
- **Task subset:** choose ~24 tasks from `parallel.json`, spread across
  `level` and `goal_item_total`. Label each with simple decomposability
  features already in the task (e.g. `goal_item_total`,
  `goal_item_kind_count`, number of distinct goal rooms). Save as
  `config/tasks_subset.json` with the indices and labels.
- **Pilot:** about 20 episodes per condition for a handful of conditions
  (e.g. n=1, n=3 base, n=5 leader_worker). Record wall-clock time per episode,
  GPU memory per simulator, and failure rate.
- From the pilot, estimate total GPU-hours for the full grid at 1 and 2 seeds,
  and propose the time-matched T. **Send these to the humans for sign-off.**
- Write `config/manifest.csv` (one row per job) and split it into three shards,
  one per account, balanced by estimated runtime. Include a submit script that
  skips cells whose outputs already exist, so reruns are safe.

### Phase 7 — Aggregation
- `analysis/collect.py`: walk `<RESULTS_ROOT>`, read every `cell.json` and
  `result.json`, and write one CSV with a row per case: all settings, success,
  completion rate, steps, tokens by role, error.
- Do not build plots or statistics. A teammate owns analysis.

## 8. Working rules

- **Keep `STATUS.md`** at the repo root: what works, what failed and what you
  tried, decisions made by humans, open questions, and next steps. Update it
  whenever you stop. It is how three people and future agents pick up your work.
- **Ask the humans before:** spending money (OpenAI API), changing anything in
  section 3, editing prompts or task content, deleting any results, or anything
  that needs admin help on Quest.
- **Config freeze:** once the humans approve the pilot (target Nov 19–20), no
  more changes to code, prompts, tasks or settings without their sign-off, or
  results from different days won't be comparable.
- Never run heavy work on login nodes. Respect the 8-GPU cap per account.
- Prefer short jobs (one cell per job) over long ones; they get through the queue faster.
- Never overwrite outputs; every run writes to its own path.

## 9. Placeholders the humans fill in

| Placeholder | Value |
|---|---|
| `<ALLOCATION>` (Quest account for `--account`) | |
| NetIDs of the three accounts | |
| `<SHARED_ROOT>` (shared project directory) | |
| `<RESULTS_ROOT>` (shared results directory) | |
| Team git remote (if any) | |
| OpenAI API key and budget (only if approved) | |
| Who to contact when blocked | |

## 10. Timeline

| Dates | Target |
|---|---|
| Nov 15–16 | Phases 0–2: environment, rendering, model serving |
| Nov 17–18 | Phases 3–4: first runs, reproduction, patches, 7/9-agent decision |
| Nov 19–20 | Phases 5–6: job template, pilot, manifest; humans approve and freeze |
| Nov 21–28 | Full runs across three accounts (humans submit shards; you fix failures) |
| Nov 29–Dec 2 | Teammates analyze and write; you support with reruns and `collect.py` |

## 11. References

- MECoBench code: `https://github.com/q-i-n-g/MECoBench`; paper arXiv:2606.31966
- Kim et al., Towards a Science of Scaling Agent Systems, arXiv:2512.08296
- Cemri et al., Why Do Multi-Agent LLM Systems Fail? (MAST), arXiv:2503.13657
  (used later by a teammate to code failures; not your job)
- Quest GPU guide: `https://rcdsdocs.it.northwestern.edu/systems/quest/user-guide/gpu/gpu.html`
- Quest Singularity guide: `https://rcdsdocs.it.northwestern.edu/tutorials/software-management/singularity/singularity-quest.html`
