# embodied_mas

Embodied agent scaling experiments: does multi-agent scaling behaviour found for text-based LLM agents (Kim et al. 2025, arXiv:2512.08296) hold for embodied agents? We run single agents and multi-agent teams of several sizes on VirtualHome household tasks using MECoBench (Liu et al. 2026, arXiv:2606.31966), on Northwestern's Quest cluster.

Team: Bryant Bettencourt, Natasha Dhanrajani, Simron Patel. Project deadline: 2026-12-02.

## Where things are

| Path | What |
|---|---|
| `HANDOFF.md` | The project brief: scope, verified MECoBench facts, phased plan, working rules. |
| `STATUS.md` | Current state: what works, what failed, decisions, open questions, next steps. Read this first. |
| `jobs/` | Slurm job templates and submit scripts (Phase 5). |
| `config/` | Task subset and run manifest (Phase 6). |
| `analysis/` | `collect.py`, which turns all results into one CSV (Phase 7). |

The upstream MECoBench code, the simulator, model weights, task data and results are not stored in this repo (see `.gitignore`).

## Rules

- Never run simulators, vLLM or evaluation on login nodes.
- At most 8 GPUs per Quest account across running jobs.
- Never commit API keys; set them as environment variables.
- Never overwrite results; every run writes to its own path.
