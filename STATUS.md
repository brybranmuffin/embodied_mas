# STATUS

Last updated: 2026-11-15 (Phase 0 started; waiting on answers from the team)

## Done

- Created this git repo at `/scratch/rsr7518/embodied_mas` (local only, no remote yet) with the handoff, README and `.gitignore`.
- Read-only checks from Quest login node `quser43`, account `rsr7518`:

| Check | Result |
|---|---|
| Slurm accounts for `rsr7518` | `e32706` and `p53299` |
| Unix groups for `rsr7518` | `e32706` only |
| `/projects/e32706` | Exists. 1736 / 2048 GB used (84%), about 312 GB free. Shared with about 20 other users. |
| `p53299` | Listed as a Slurm account, but `/projects/p53299` does not exist and `checkproject` says the allocation does not exist. |
| `/scratch/rsr7518` | Mode `drwxr-s---`, group `p32859`. `rsr7518` is not a member of `p32859`, and teammates cannot read this folder. |
| `gengpu` partition | Visible. 48 h limit. Nodes with A100 (1, 2 or 4 per node) and H100 (4 per node). |
| GitHub from login node | Reachable. `q-i-n-g/MECoBench` HEAD is still `219d429`, the commit the handoff was checked against. |
| Hugging Face from login node | Reachable. |
| `conda` / `mamba` | Available on the login node (`/hpc/software/mamba/24.3.0`). |
| `Xvfb` | Not on the login node. Still to check on a GPU node (Phase 1). |
| `singularity` | Not on the default path; needs `module load`. |
| `gh` CLI | Not installed. |

## Not started

Nothing has been downloaded, no environment has been created and no Slurm job has been submitted.

## Decisions made by humans

None yet.

## Open questions for the humans

1. **Allocation** for `--account`: `e32706` or `p53299`? Do all three teammates have the same one?
2. **Shared root**: where should MECoBench, the conda envs, the model cache and results live so all three accounts can use them? This folder is private to `rsr7518`. `/projects/e32706` has about 312 GB free.
3. **NetIDs** of the other two accounts.
4. **Team git remote**: should this repo and our MECoBench fork go on GitHub, and under which account?
5. **Resolver and embeddings**: OpenAI API (matches the paper, costs money, needs internet from compute nodes) or local Qwen resolver (free, results will not match the paper exactly)?
6. **Who to contact when blocked.**

## Next steps (once the questions above are answered)

1. Clone MECoBench at `219d429` into the shared root and put our changes under git.
2. Create the Python 3.10 conda env from `environment.yml` and a separate vLLM env.
3. Download the simulator zip, `parallel.json` and the Qwen3-VL-8B weights.
4. Phase 1 rendering smoke test on one GPU node (highest risk).
