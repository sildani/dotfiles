# dotfiles

zsh (Oh My Zsh), tmux, Neovim (NvChad) and Ghostty config for macOS, shared across machines.
Nothing else (git and gh config are left alone on purpose).

## New machine

```sh
DOTFILES=~/code/dotfiles  # an example: clone it anywhere
git clone https://github.com/sildani/dotfiles "$DOTFILES"
"$DOTFILES/install.sh"
"$DOTFILES/doctor.sh"
```

From then on the shared zshrc exports `DOTFILES`, the repo root, worked out from
where `~/.zshrc` links to. The commands below and the extras lines use it.

Needs macOS with Homebrew. If the Xcode Command Line Tools are missing, the
first `git` command offers to install them.

## Update

```sh
cd "$DOTFILES" && git pull && ./install.sh
```

`install.sh` is safe to re-run. It:

- installs only what's **missing** with brew: git, gh, ripgrep, tree-sitter-cli,
  tmux (≥ 3.5), neovim (≥ 0.12), Ghostty, Hurmit Nerd Font. Anything already
  installed, however it was installed, is left alone; if it's too old you get a
  warning with how to upgrade.
- symlinks the configs (existing files are moved to `~/.dotfiles-backup/<time>/`):

  | Repo             | Linked at                   |
  | ---------------- | --------------------------- |
  | `zsh/zshrc`      | `~/.zshrc`                  |
  | `tmux/tmux.conf` | `~/.tmux.conf`              |
  | `nvim/`          | `~/.config/nvim`            |
  | `ghostty/config` | `~/.config/ghostty/config`  |

  It also moves away Ghostty's `~/Library/Application Support/com.mitchellh.ghostty/config*`,
  which would otherwise override the repo's file. A machine's own `~/.zshrc` is
  backed up too, and copied to `~/.zshrc.local` (if that doesn't exist yet) so its
  PATH and tool setup keep working; its Oh My Zsh load is commented out there.
- installs Oh My Zsh, tmux plugins (TPM), nvim plugins at the versions in
  `nvim/lazy-lock.json`, and the treesitter parsers for the files in this repo.

It never logs in to GitHub or changes git/gh config: each machine keeps its own account.

To go back to a machine's own zsh config, replace the link with the backup and
remove the copy: `mv ~/.dotfiles-backup/<time>/.zshrc ~/.zshrc && rm ~/.zshrc.local`
(`~/.oh-my-zsh` can stay; nothing loads it unless your `~/.zshrc` does).

## Check a machine

```sh
"$DOTFILES/doctor.sh"
```

Read-only. Shows tool versions and where they came from, whether the links point
here, missing plugins/parsers, and which languages are set up, with a fix-it hint
on every problem.

Before installing on a machine that already has its own config, see what
`install.sh` would replace:

```sh
"$DOTFILES/doctor.sh" --diff
```

Also read-only. For each config file that isn't linked yet it prints the diff
from this machine's copy (`-`) to the repo's (`+`); on a machine that's set up,
that's all ✓. It then counts the originals in `~/.dotfiles-backup/` that differ
from the repo. Those never come to match; `--diff --backups` shows their diffs,
for settings you may want to move into the per-machine files below.

## Languages (Java, Python, Go)

**Not installed by the script, on purpose.** When you need one, follow
[LANGUAGES.md](LANGUAGES.md); the spots to change are marked `[JAVA]`, `[PYTHON]`
and `[GO]` in `nvim/lua/configs/`.

## Per-machine tweaks

Optional, not in git, ignored if missing:

| Tool    | File                           |
| ------- | ------------------------------ |
| zsh     | `~/.zshrc.local`               |
| tmux    | `~/.tmux.local.conf`           |
| Ghostty | `~/.config/ghostty/local`      |
| nvim    | `$DOTFILES/nvim/lua/local.lua` |

### Optional extras

Snippets that are in the repo but off by default. Turn one on for a machine by
adding its line to that machine's per-machine file; `doctor.sh` lists the ones
in use. tmux gets `$DOTFILES` from the shell that starts its server: if the
server started before your shell had it (first install, or the update that
added it), open a new shell and run `tmux kill-server` once.

<!-- test/lint.sh checks each row and test/fresh-home.sh turns each extra on from it (EXTRAS_ROW_RE in lib/common.sh): keep the last two cells as `<line>` and `<file>`. -->

| Extra                         | What it does                                   | Line to add                                           | Per-machine file     |
| ----------------------------- | ---------------------------------------------- | ----------------------------------------------------- | -------------------- |
| `tmux/extras/agy-ctrl-k.conf` | `prefix Ctrl-k` sends Ctrl-k to the pane (agy) | `source-file "$DOTFILES/tmux/extras/agy-ctrl-k.conf"` | `~/.tmux.local.conf` |
| `zsh/extras/utc-prompt.zsh`   | Prompt starts with the current UTC time        | `source "$DOTFILES/zsh/extras/utc-prompt.zsh"`        | `~/.zshrc.local`     |

## Changing config

Edit on the personal laptop (the links mean you're editing the repo), commit and
push. Work machines only pull.

Checks (also run by CI on every push):

- `test/lint.sh`: shellcheck, secret scan (gitleaks), that the extras are
  documented, and that the language recipes agree across `doctor.sh`, the nvim
  config and `LANGUAGES.md`.
  Runs before each commit once you enable the hook: `git config core.hooksPath hooks`
  (the hook also refuses commits on `main`; changes go through a PR).
- `test/lint-selftest.sh`: breaks the fresh-home.sh markers and extras rows in a
  copy of the repo, one at a time, and checks that `test/lint.sh` fails on each.
- `test/fresh-home.sh`: full install in a temporary empty HOME, run twice, then doctor.

After merging a PR, `./prune-merged.sh` deletes the merged branches locally and
on `origin`.

To update nvim plugins: `:Lazy update` on the laptop, test, then commit
`nvim/lazy-lock.json`. Other machines get the same versions on their next
`./install.sh`.

## Cheatsheets

- tmux: <https://tmuxcheatsheet.com/>. Prefix here is **Ctrl-Space**
  (not Ctrl-b); `prefix k` clears the screen and scrollback. Sessions come
  back after a reboot or `tmux kill-server`: see [tmux/README.md](tmux/README.md).
- nvim comes set up with NvChad. Press **Space c h** in nvim for a cheatsheet
  of the keyboard shortcuts.
