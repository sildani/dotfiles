# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

`ready-for-agent` means the red step is proven: before applying it, run or prototype each Acceptance's failing case on today's tree (the check goes red, the test fails), or say in the issue why it can't be shown yet. When the full check is slow (`test/fresh-home.sh` takes minutes), also leave a fast red the implementer can rerun in seconds: its set-up and command. Cite places in `test/fresh-home.sh` by a step's `echo` label or a quoted line rather than a line number, since earlier merges in a batch move the lines.

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.
