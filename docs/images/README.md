# Sample images from the Quest runs

A small sample only. The full set (about 2,700 images, 800 MB) is in
`/scratch/rsr7518/embodied_mas_data/results/<run>/job_<id>/batch_<time>/case_<n>/img/`.

| Folder | Source | What it shows |
|---|---|---|
| `phase1_render/` | job 8858952 | Two fixed scene cameras from the rendering smoke test (no agents). |
| `phase3_2agents_case2/` | job 8859836, example task 2 | A successful 2-agent episode (5 of 5 goals, 22 rounds): each agent's view at rounds 0, 10 and 21. |
| `phase4_9agents_case45/` | job 8864492, task 45 | A 9-agent team at round 3: views from agents 0, 4 and 8. |

`agentN_roundR.png` is agent N's four-direction first-person view at round R.
`*_labeled.png` is the same view with the object labels the model is shown.
`overview_*.png` is the top-down map of the apartment.
