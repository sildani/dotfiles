# tmux sessions across reboots

The shared config saves your tmux sessions and brings them back after a reboot
or `tmux kill-server`. It uses two TPM plugins, which `install.sh` installs:
[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) saves and
restores; [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum)
runs them for you.

## How it works

- **Auto-save** every 15 minutes, while a tmux client is attached.
- **Auto-restore** when the tmux server starts: the first `tmux` after a reboot
  or `kill-server` brings the last save back.
- **By hand**: `prefix Ctrl-s` saves now, `prefix Ctrl-r` restores the last
  save. The prefix here is Ctrl-Space.

Saves live in `${XDG_DATA_HOME:-~/.local/share}/tmux/resurrect/` (or
`~/.tmux/resurrect/` if that folder exists); `last` points to the newest one.

Auto-save and auto-restore stay off on a tmux server started while another tmux
server is running, so a second server can't overwrite your saves. If tmux
doesn't restore on its own, run `./doctor.sh`: it warns about a stray server
(a test or `-L` socket) and names it. Stop it with `tmux -L <name> kill-server`.
The save keys work either way.

## What comes back

Restored:

- sessions, windows, panes and their layouts
- each pane's working directory
- the active and previous window and pane
- programs on resurrect's default list, started again with the same arguments:
  `vi vim view nvim emacs man less more tail top htop irssi weechat mutt`

Not restored:

- any other running program (pane gets a fresh shell in the same directory)
- pane contents and scrollback
- nvim's open buffers and windows (nvim starts again with its original
  arguments only)

## Try it

1. Start tmux, make a second session (`tmux new -s demo`), split a pane, `cd`
   somewhere in it.
2. Press `prefix Ctrl-s`. "Tmux environment saved!" shows at the bottom.
3. `tmux kill-server`.
4. Run `tmux`. About a second later, the sessions are back: `prefix s` lists them.

Without step 2, step 4 brings back the last auto-save, up to 15 minutes old.

## On one machine

- Turn auto-restore off (the save keys and auto-save still work):
  `touch ~/tmux_no_auto_restore`. Delete the file to turn it back on.
  This is continuum's own switch. Setting `@continuum-restore 'off'` in the
  per-machine file `~/.tmux.local.conf` isn't reliable: that file loads after
  the plugins, and continuum may already have checked the option.
- Don't set `status-right` in `~/.tmux.local.conf`: continuum's auto-save hooks
  into the `status-right` that the shared config sets (see `tmux/tmux.conf`),
  and replacing it stops auto-save.
