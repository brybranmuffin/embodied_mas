# STATUS

Last updated: 2026-11-15 (Phases 0, 1 and the Phase 2 serving check pass; Phase 3 waits on the resolver decision)

## Where everything is

| Thing | Path |
|---|---|
| This repo (pipeline, status, handoff) | `/scratch/rsr7518/embodied_mas`, remote `github.com/brybranmuffin/embodied_mas` |
| `<SHARED_ROOT>` | `/projects/e32706/embodied_mas` (group `e32706`, mode 2770) |
| MECoBench clone | `<SHARED_ROOT>/MECoBench`, upstream commit `219d429`, no local changes yet |
| MECoBench env (Python 3.10) | `<SHARED_ROOT>/envs/mecobench` |
| vLLM env (Python 3.12) | `<SHARED_ROOT>/envs/vllm` (vLLM 0.33.0, torch 2.14.0, 8.3 GB) |
| Xvfb (our own copy; Quest has none) | `<SHARED_ROOT>/envs/xvfb` |
| Simulator binary (`MECOBENCH_SIMULATOR_BIN`) | `<SHARED_ROOT>/simulator/linux_simulator/linux.x86_64` |
| Full task file | `<SHARED_ROOT>/MECoBench/data/task/parallel.json` |
| Model cache (`HF_HOME`) | `<SHARED_ROOT>/hf_cache` (`Qwen/Qwen3-VL-8B-Instruct`, 17 GB) |
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

- **vLLM env** and **Qwen3-VL-8B weights** installed and downloaded (snapshot `0c351dd`).

### Phase 1 — rendering smoke test: PASS (job 8854145, node `qgpu2005`, A100 80 GB)

- One simulator started under our Xvfb, rendered through Vulkan on the NVIDIA GPU, and returned camera images.
  `reset(0)` took 8.0 s; two 640x480 images took 3.1 s; the scene has 79 cameras; the simulator used 1.6 GB of GPU memory.
- Images saved in `<SHARED_ROOT>/results/phase1/job_8854145/` and checked by eye (a furnished kitchen/dining room, not black).
- Run it again with `sbatch jobs/phase1_render_smoke.sbatch` (20 minutes, 1 GPU).

What it took (attempt log):

1. Job 8852391 failed in 4 s: **Xvfb is not installed on Quest GPU nodes.**
2. Fix: Xvfb installed without root into `<SHARED_ROOT>/envs/xvfb` from conda-forge
   (`xorg-x11-server-xvfb-cos7-x86_64`, plus `xkbcomp` and `xkeyboard-config`). It needs `libcrypto.so.10`,
   which Quest does not have, so `envs/xvfb/compat/` holds that one library from the CentOS 7 package
   `openssl-libs-1.0.2k-19.el7` (from vault.centos.org; sha256 matches the repository metadata).
   Start it with `LD_LIBRARY_PATH=<SHARED_ROOT>/envs/xvfb/compat` set for Xvfb only. No container was needed.
3. The NVIDIA Vulkan ICD file exists but is named `/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json`,
   not `nvidia_icd.json` as `src/start_unity_multi_8gpu.sh` assumes. Always set `VK_ICD_FILENAMES` ourselves.

### Phase 2 — model serving check: PASS (job 8855509, node `qgpu3014`, H100 80 GB)

- vLLM 0.33.0 served `Qwen/Qwen3-VL-8B-Instruct` as `qwen-8b-vl` from the shared cache with no internet (`HF_HUB_OFFLINE=1`).
- Ready 240 s after launch (model load about 30 s, the rest is one-time compilation and warm-up).
- One image chat completion, with the same sampling settings as `models.json`, took 1.2 s
  (326 prompt + 47 completion tokens) and correctly described the Phase 1 kitchen image.
- vLLM held 71 GB of the 80 GB GPU (`--gpu-memory-utilization 0.90`), so **vLLM and simulators cannot share one GPU
  at that setting**. Either keep the handoff's 2-GPU layout or lower the setting (weights need only 16.5 GB).
- Run it again with `sbatch jobs/phase2_serve_smoke.sbatch` (30 minutes, 1 GPU).

What it took (attempt log):

1. Job 8854415 failed after 4 min 48 s: vLLM's FlashInfer sampler tried to compile CUDA code at startup
   and died with `FileNotFoundError: 'ninja'` (Quest nodes have no `nvcc`/`ninja` on PATH).
   The prebuilt package `flashinfer-cubin` has no release matching the installed `flashinfer-python 0.7.2.post1`.
2. Fix: `export VLLM_USE_FLASHINFER_SAMPLER=0` (vLLM's built-in PyTorch sampler). Required in every job that starts vLLM.

Not done yet in Phase 2: the resolver and embedding setup, which depends on open question 1.

## In progress

Nothing is running. No jobs are queued.

## Findings worth knowing

- **`parallel.json` has 96 tasks, all `level` 1, all with 5 `init_rooms` entries.** The Phase 6 plan to spread the 24-task subset across `level` cannot apply; the spread has to come from `goal_item_total`, `goal_item_kind_count` and goal rooms.
- **The shared root is open to all of `e32706`** (about 20 users), not only our three accounts. Nothing narrower is possible with Quest group permissions there.
- `/projects/e32706` was at 1736 / 2048 GB (84%) before we started; we share that quota with the rest of the allocation.
- Slurm lists a second account, `p53299`, for `rsr7518`, but it has no project folder and `checkproject` says it does not exist. Not used.
- **Compute nodes have outbound internet:** from a GPU node, `huggingface.co` and `github.com` return 200 and `api.openai.com` answers (HTTP 421 to a bare request, so the host is reachable). The OpenAI resolver option is technically possible.
- GPU nodes report NVIDIA driver 610.43.02 (the handoff says 570.86.15).
- The `gengpu` queue estimate was about 15 hours, but single-GPU 20-minute jobs started within minutes.
- Quest login node: `conda`/`mamba` available; `singularity` needs `module load`; `gh` CLI not installed.
- This shell cannot push to GitHub (no saved HTTPS login; the Quest SSH key is not registered). Bryant pushes from VS Code.
- `gengpu`: 48 h limit; nodes with A100 (1, 2 or 4 per node) and H100 (4 per node).

## Decisions made by humans

| Date | Decision | By |
|---|---|---|
| 2026-11-15 | Slurm account for jobs: `e32706` | Bryant |
| 2026-11-15 | Shared root: `/projects/e32706/embodied_mas` | Bryant |
| 2026-11-15 | All Phase 0 downloads approved (code, envs, simulator, tasks, 8B weights) | Bryant |
| 2026-11-15 | Git remote: `github.com/brybranmuffin/embodied_mas` | Bryant |

## Open questions for the humans

1. **Resolver and embeddings:** OpenAI API (matches the paper, costs money, needs internet from compute nodes) or local Qwen resolver (free, results will not match the paper exactly)? **This now blocks Phase 3.**
2. **NetIDs** of the other two accounts, and whether both are members of `e32706`.
3. **MECoBench changes:** where should our patched MECoBench be pushed (a fork under `brybranmuffin`, or local commits in the shared clone only)?
4. **Who to contact when blocked.**

## Next steps

1. Get the resolver decision (open question 1).
2. Phase 3: first end-to-end run on `data/examples/parallel_5.json` with 2 agents, `base`, 30 rounds;
   then about 20 cases of `parallel.json` to compare with the paper's 0.458.
3. Phase 4 patches (seed, teams of 7 and 9) in the shared MECoBench clone. Deadline for the 7/9 decision: Nov 18.
