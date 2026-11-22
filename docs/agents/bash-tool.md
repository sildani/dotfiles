# Bash tool gotchas

Claude Code's Bash tool runs the user's zsh with this repo's Oh My Zsh setup, inside the harness's own checks. These broke ad hoc commands in past sessions. Scripts run with `/bin/bash`, like the tests, avoid the zsh ones; the harness ones still apply inside them.

## zsh

- `tmux` is the Oh My Zsh plugin's alias, so a probe can fail with `_zsh_tmux_plugin_run: command not found`. Use `command tmux -L <private-socket> …`, and kill that server in the same command (`; command tmux -L <sock> kill-server`): a leftover one makes tmux-continuum skip saving and restoring the real server.
- An unquoted glob that matches nothing fails before the command runs (`no matches found`): quote it, as in `--include='*.md'`.
- `${PIPESTATUS[0]}` prints nothing; zsh's is `$pipestatus`, 1-based.
- A snippet with nested quotes or an `awk`/`sed` program: write it to a scratchpad script with the Write tool and run `/bin/bash <file>`, which also runs it under stock bash 3.2.

## macOS tools

- Renames: use the Edit tool, not `sed`. macOS `sed` has no `\b`, and escaped backticks in shell strings slip past patterns.
- To show invisible characters, use `cat -vet`; macOS has no `cat -A`.
- Pipe `ghostty +validate-config` through `cat`: unpiped, it erases earlier output from the same Bash call.
- `ssh-agent` probes need a short HOME under `/tmp` (its socket path under the scratchpad is too long). Keep stderr while probing.

## Harness

- To sleep inside a script, use `perl -e 'select(undef,undef,undef,N)'`. `read -t N <> <(:)` fails at once with `/dev/fd/<n>: Permission denied` when the script is started from the Bash tool.
- Delete with a guarded path, `rm "${VAR:?}/…"`, in a script written with the Write tool: it stops on an empty variable instead of reaching `/…`, and the harness's delete check has refused a Bash call containing `rm "$VAR/…"`, even inside a heredoc.
- To wait for something, run it in the background and act on its notification (`./ci-wait.sh`, the long tests in AGENTS.md "Checks").
