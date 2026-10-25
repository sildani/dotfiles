# dotfiles

tmux, Neovim (NvChad) and Ghostty config for macOS, shared across machines.
Nothing else (shell, git and gh config are left alone on purpose).

## New machine

```sh
git clone https://github.com/sildani/dotfiles ~/code/dotfiles
~/code/dotfiles/install.sh
~/code/dotfiles/doctor.sh
```

Needs macOS with Homebrew. If the Xcode Command Line Tools are missing, the
first `git` command offers to install them.

## Update

```sh
cd ~/code/dotfiles && git pull && ./install.sh
```

`install.sh` is safe to re-run. It:

- installs only what's **missing** with brew: git, gh, ripgrep, tree-sitter-cli,
  tmux (≥ 3.5), neovim (≥ 0.12), Ghostty, Hurmit Nerd Font. Anything already
  installed, however it was installed, is left alone; if it's too old you get a
  warning with how to upgrade.
- symlinks the configs (existing files are moved to `~/.dotfiles-backup/<time>/`):

  | Repo             | Linked at                   |
  | ---------------- | --------------------------- |
  | `tmux/tmux.conf` | `~/.tmux.conf`              |
  | `nvim/`          | `~/.config/nvim`            |
  | `ghostty/config` | `~/.config/ghostty/config`  |

  It also moves away Ghostty's `~/Library/Application Support/com.mitchellh.ghostty/config*`,
  which would otherwise override the repo's file.
- installs tmux plugins (TPM), nvim plugins at the versions in
  `nvim/lazy-lock.json`, and the treesitter parsers for the files in this repo.

It never logs in to GitHub or changes git/gh config: each machine keeps its own account.

## Check a machine

```sh
~/code/dotfiles/doctor.sh
```

Read-only. Shows tool versions and where they came from, whether the links point
here, missing plugins/parsers, and which languages are set up, with a fix-it hint
on every problem.

## Languages (Java, Python, Go)

**Not installed by the script, on purpose.** When you need one, follow
[LANGUAGES.md](LANGUAGES.md); the spots to change are marked `[JAVA]`, `[PYTHON]`
and `[GO]` in `nvim/lua/configs/`.

## Per-machine tweaks

Optional, not in git, ignored if missing:

| Tool    | File                                          |
| ------- | --------------------------------------------- |
| tmux    | `~/.tmux.local.conf`                          |
| Ghostty | `~/.config/ghostty/local`                     |
| nvim    | `~/code/dotfiles/nvim/lua/local.lua`          |

## Changing config

Edit on the personal laptop (the links mean you're editing the repo), commit and
push. Work machines only pull.

Checks (also run by CI on every push):

- `test/lint.sh`: shellcheck, secret scan (gitleaks), and that the language
  recipes agree across `doctor.sh`, the nvim config and `LANGUAGES.md`.
  Runs before each commit once you enable the hook: `git config core.hooksPath hooks`
- `test/fresh-home.sh`: full install in a temporary empty HOME, run twice, then doctor.

To update nvim plugins: `:Lazy update` on the laptop, test, then commit
`nvim/lazy-lock.json`. Other machines get the same versions on their next
`./install.sh`.

## Cheatsheets

- tmux: <https://tmuxcheatsheet.com/>. Prefix here is **Ctrl-Space**
  (not Ctrl-b); `prefix k` clears the screen and scrollback.
