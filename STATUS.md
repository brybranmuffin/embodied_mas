# STATUS

Last updated: 2026-11-15 (Phase 0 nearly complete; vLLM env and model weights still in progress)

## Where everything is

| Thing | Path |
|---|---|
| This repo (pipeline, status, handoff) | `/scratch/rsr7518/embodied_mas`, remote `github.com/brybranmuffin/embodied_mas` |
| `<SHARED_ROOT>` | `/projects/e32706/embodied_mas` (group `e32706`, mode 2770) |
| MECoBench clone | `<SHARED_ROOT>/MECoBench`, upstream commit `219d429`, no local changes yet |
| MECoBench env (Python 3.10) | `<SHARED_ROOT>/envs/mecobench` |
| vLLM env (Python 3.12) | `<SHARED_ROOT>/envs/vllm` (install in progress) |
| Simulator binary (`MECOBENCH_SIMULATOR_BIN`) | `<SHARED_ROOT>/simulator/linux_simulator/linux.x86_64` |
| Full task file | `<SHARED_ROOT>/MECoBench/data/task/parallel.json` |
| Model cache (`HF_HOME`) | `<SHARED_ROOT>/hf_cache` (empty so far) |
| `<RESULTS_ROOT>` (proposed) | `<SHARED_ROOT>/results` |
| Install logs and the simulator zip | `<SHARED_ROOT>/downloads` |

## Done

- **Repo:** created with the handoff, README, `.gitignore` and this file.
- **MECoBench:** cloned; HEAD is `219d429`, the commit the handoff was checked against.
- **MECoBench env:** built from `environment.yml` (467 MB). Phase 0 check passes:
  `python -c "import virtualhome.simulation.unity_simulator as u; print(u.UnityCommunication)"` prints the class.
- **Simulator:** `simulator_linux.zip` (1.2 GB) downloaded and unzipped (3.1 GB); binary is executable.
- **Tasks:** `parallel.json` downloaded (57 MB, sha256 matches the Hugging Face LFS hash `aaaa5f70…`).
- **Model ID verified:** `Qwen/Qwen3-VL-8B-Instruct` exists on Hugging Face.

## In progress

- vLLM env install (`<SHARED_ROOT>/downloads/env_vllm.log`).
- Qwen3-VL-8B weights download into `<SHARED_ROOT>/hf_cache` (starts after the vLLM env finishes).

## Findings worth knowing

- **`parallel.json` has 96 tasks, all `level` 1, all with 5 `init_rooms` entries.** The Phase 6 plan to spread the 24-task subset across `level` cannot apply; the spread has to come from `goal_item_total`, `goal_item_kind_count` and goal rooms.
- **The shared root is open to all of `e32706`** (about 20 users), not only our three accounts. Nothing narrower is possible with Quest group permissions there.
- `/projects/e32706` was at 1736 / 2048 GB (84%) before we started; we share that quota with the rest of the allocation.
- Slurm lists a second account, `p53299`, for `rsr7518`, but it has no project folder and `checkproject` says it does not exist. Not used.
- Quest login node checks: `conda`/`mamba` available; `Xvfb` not on the login node (to check on a GPU node in Phase 1); `singularity` needs `module load`; `gh` CLI not installed.
- `gengpu`: 48 h limit; nodes with A100 (1, 2 or 4 per node) and H100 (4 per node).

## Decisions made by humans

| Date | Decision | By |
|---|---|---|
| 2026-11-15 | Slurm account for jobs: `e32706` | Bryant |
| 2026-11-15 | Shared root: `/projects/e32706/embodied_mas` | Bryant |
| 2026-11-15 | All Phase 0 downloads approved (code, envs, simulator, tasks, 8B weights) | Bryant |
| 2026-11-15 | Git remote: `github.com/brybranmuffin/embodied_mas` | Bryant |

## Open questions for the humans

1. **Resolver and embeddings:** OpenAI API (matches the paper, costs money, needs internet from compute nodes) or local Qwen resolver (free, results will not match the paper exactly)? Needed before Phase 2.
2. **NetIDs** of the other two accounts, and whether both are members of `e32706`.
3. **MECoBench changes:** where should our patched MECoBench be pushed (a fork under `brybranmuffin`, or local commits in the shared clone only)?
4. **Who to contact when blocked.**

## No Slurm jobs have been submitted yet.

## Next steps

1. Finish the vLLM env and the 8B weights download.
2. Phase 1 rendering smoke test on one `gengpu` node (highest risk): Xvfb, Vulkan ICD, one simulator, one saved camera image.
3. Phase 2: serve the 8B model with vLLM and test an image chat completion.
