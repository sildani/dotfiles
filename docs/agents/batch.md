# Batch sessions

Several issues implemented in one session, one branch and PR each, after a separate triage session. The triage session leaves its decisions (labels, spec amendments, order, seams, merge policy) in `.scratch/handoff/handoff.md`, and the issue comments amend the specs: read both.

The user runs `/mattpocock-skills:implement <n> <n> …` once. Apply it per issue: finish the whole loop for one issue before starting the next.

1. Branch off the updated `main`.
2. `tdd` at the seam the handoff pre-agreed: red, then green. Stop and ask only when a seam doesn't work.
3. Commit and `code-review` as AGENTS.md "Writing code" says.
4. Push and open a PR whose body follows `mattpocock-skills:pr` and ends `Closes #N`.
5. Watch CI by run ID. Green: merge. Red: stop and report.
6. Run `./prune-merged.sh`.

Merge on green before branching the next issue, so each branch builds on the earlier merges, unless the handoff chose another policy.

Note friction as it happens (seams that didn't hold, specs that needed widening, waits, slips) in the handoff, so the retro has material. After the last PR, suggest `/mattpocock-skills:retro` once for the whole batch.
