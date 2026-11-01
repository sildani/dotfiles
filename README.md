# dotfiles

zsh (Oh My Zsh), tmux, Neovim (NvChad) and Ghostty config for macOS, shared across machines.
Nothing else (git and gh config are left alone on purpose, apart from this
clone's `core.hooksPath`).

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

Keep a machine current, with no repo change needed:

```sh
"$DOTFILES/update.sh"
```

It upgrades the formulae below with brew (skipping any brew didn't install), then
updates Oh My Zsh, the tmux plugins, nvim plugins and treesitter parsers, and
shows old → new for each, with a restart note for what changed. It never pulls
the repo: it ends with a note if the clone is behind `origin`. It leaves Ghostty,
the font, Rectangle and other brew packages alone, and skips catppuccin, which
`tmux/tmux.conf` pins to a tag, any plugin with changed tracked files, and Oh My
Zsh if it has a commit of your own. A new shell reminds you once `update.sh`
hasn't run for 14 days, in place of Oh My Zsh's own prompt; `install.sh` starts
that count.

Get changes to the repo:

```sh
cd "$DOTFILES" && git pull && ./install.sh
```

`install.sh` is safe to re-run. It:

- installs only what's **missing** with brew: git, gh, ripgrep, shellcheck,
  gitleaks, tree-sitter-cli, tmux (≥ 3.5), neovim (≥ 0.12), Ghostty, Hurmit Nerd
  Font, Rectangle. Anything already installed is left alone unless it's below
  its minimum: brew's then gets `brew upgrade`, and anything else gets a warning
  with how to upgrade. A failed Rectangle
  install is only a warning. Grant it Accessibility permission by hand. Its
  settings stay out of the repo.
- symlinks the configs (existing files are moved to `~/.dotfiles-backup/<time>/`):

  | Repo              | Linked at                   |
  | ----------------- | --------------------------- |
  | `zsh/zshrc`       | `~/.zshrc`                  |
  | `tmux/tmux.conf`  | `~/.tmux.conf`              |
  | `nvim/`           | `~/.config/nvim`            |
  | `ghostty/config`  | `~/.config/ghostty/config`  |
  | `ghostty/extras/` | `~/.config/ghostty/extras`  |

  It also moves away Ghostty's `~/Library/Application Support/com.mitchellh.ghostty/config*`,
  which would otherwise override the repo's file. A machine's own `~/.zshrc` is
  backed up too, and copied to `~/.zshrc.local` (if that doesn't exist yet) so its
  PATH and tool setup keep working. The copy leaves out comments, blank lines and
  what the shared zshrc already does (Homebrew, loading Oh My Zsh, and the
  settings it reads only while loading: `ZSH`, `ZSH_THEME`, `plugins`, `zstyle
  ':omz:…'` lines and the template's others, such as `HIST_STAMPS`; the full list
  is in `migrate_zshrc` in `install.sh`). Those load too late in `~/.zshrc.local`,
  so install warns about any that differ from the shared zshrc's, to add to
  `zsh/zshrc` by hand.
- sets `core.hooksPath` to `hooks` in this clone, so commits run the pre-commit
  hook. If it's already set to something else, it warns and leaves it.
- installs Oh My Zsh, and links its sample zshrc, with all its comments, to
  `~/.zshrc.example` (unless something is already there).
- installs tmux plugins (TPM), the latest nvim plugins, and the treesitter
  parsers for the files in this repo.

A `~/.zshrc.local` copied by an older install still has the whole old `~/.zshrc`.
To tidy it by hand, delete its comments and the lines the shared zshrc already
does (listed above); move any Oh My Zsh settings you want to keep into `zsh/zshrc`.

It never logs in to GitHub or changes `~/.gitconfig` or `gh`: each machine keeps
its own account.

To go back to a machine's own zsh config, replace the link with the backup and
remove the copy: `mv ~/.dotfiles-backup/<time>/.zshrc ~/.zshrc && rm ~/.zshrc.local`
(`~/.oh-my-zsh` can stay; nothing loads it unless your `~/.zshrc` does).

## Check a machine

```sh
"$DOTFILES/doctor.sh"
```

Read-only. Shows tool versions and where they came from, whether the links point
here, missing plugins/parsers, and which languages are set up, with a fix-it hint
on every problem. It also warns if macOS would take Ctrl-Space, the tmux prefix,
to switch input sources, and if the clone is behind `origin`.

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
added it), open a new shell and run `tmux kill-server` once. Ghostty doesn't
expand `$DOTFILES`, so its extras load through the `~/.config/ghostty/extras`
link instead.

<!-- test/lint.sh checks each row and test/fresh-home.sh turns each extra on from it (EXTRAS_ROW_RE in lib/common.sh): keep the last two cells as `<line>` and `<file>`. -->

| Extra                              | What it does                                   | Line to add                                                | Per-machine file          |
| ---------------------------------- | ---------------------------------------------- | ---------------------------------------------------------- | ------------------------- |
| `tmux/extras/agy-ctrl-k.conf`      | `prefix Ctrl-k` sends Ctrl-k to the pane (agy) | `source-file "$DOTFILES/tmux/extras/agy-ctrl-k.conf"`      | `~/.tmux.local.conf`      |
| `zsh/extras/utc-prompt.zsh`        | Prompt starts with the current UTC time        | `source "$DOTFILES/zsh/extras/utc-prompt.zsh"`             | `~/.zshrc.local`          |
| `ghostty/extras/window-frame.conf` | Brings back Ghostty's title bar and frame      | `config-file = ~/.config/ghostty/extras/window-frame.conf` | `~/.config/ghostty/local` |

## Changing config

Edit the repo from any Mac (the links mean you're editing it already), then
commit on a branch and open a PR.

Checks (also run by CI on every push and weekly):

- `test/lint.sh`: shellcheck, secret scan (gitleaks), that the extras are
  documented, that CI runs every `test/*.sh` and this list names it, and that
  the language recipes agree across `doctor.sh`, the nvim config and
  `LANGUAGES.md`. A new test script needs a `run:` step in
  `.github/workflows/check.yml` and a bullet here; sourced helpers go in `lib/`.
  Runs before each commit through the hook `install.sh` turns on (it also refuses
  commits on `main`; changes go through a PR).
- `test/lint-selftest.sh`: in a copy of the repo, removes or rewords the
  fresh-home.sh markers, drops one marker's text from fresh-home.sh, adds an
  unmarked grep, breaks the extras rows, drops each test script's CI step and
  bullet here and adds an unlisted test script, one at a time, and checks that
  `test/lint.sh` fails on each.
- `test/doctor-warnings.sh`: runs `doctor.sh` in an empty temporary HOME with a
  fake `defaults`, and checks when it warns.
- `test/updates.sh`: runs `update.sh` against a fake Homebrew and nvim and local
  repos, and checks brew upgrades below a minimum and the update reminder.
- `test/fresh-home.sh`: full install in a temporary empty HOME, run twice, then doctor.

After merging a PR, `./prune-merged.sh` deletes the merged branches locally and
on `origin`.

Each machine keeps its own nvim lockfile, `lazy-lock.json` under
`~/.local/state/nvim`, outside the repo. `:Lazy restore` puts that machine's
plugins back at the versions in that file. `update.sh` and `:Lazy update` rewrite
it, so copy it first if you may want to go back past an update.

### Making changes from any Mac

`install.sh` makes a clone ready to commit, but signing in is yours to do:

```sh
gh auth login      # as the repo's owner
gh auth setup-git  # the remote is HTTPS, so git pushes through gh
```

On a Mac signed in to another account, add this one with `gh auth login`, then
move between them with `gh auth switch`.

A Mac's global git identity may not be the one to use in a public repo, so set
it for this clone only:

```sh
git -C "$DOTFILES" config user.name "Your Name"
git -C "$DOTFILES" config user.email "you@example.com"
```

## Cheatsheets

- tmux: <https://tmuxcheatsheet.com/>. Prefix here is **Ctrl-Space**
  (not Ctrl-b); `prefix k` clears the screen and scrollback. Sessions come
  back after a reboot or `tmux kill-server`: see [tmux/README.md](tmux/README.md).
- nvim comes set up with NvChad. Press **Space c h** in nvim for a cheatsheet
  of the keyboard shortcuts.
