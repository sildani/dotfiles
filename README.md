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
  gitleaks, tree-sitter-cli, tmux (≥ 3.5), neovim (≥ 0.12), ffmpeg, imagemagick,
  pngquant and ghostscript (for `shrink`), Ghostty, Hurmit Nerd Font, Rectangle. Anything already installed is left alone unless it's below
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
  | `bin/shrink`      | `~/.local/bin/shrink`       |
  | `man/shrink.1`    | `~/.local/share/man/man1/shrink.1` |

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
- sets `core.hooksPath` to `hooks` in this clone, so commits run the commit
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

The other links go back the same way. A backup keeps its path under `~/`, and a
machine can have several, so look for the one that holds your file. Remove the
link first, or `mv` puts a folder inside the repo:
`rm ~/.config/nvim && mv ~/.dotfiles-backup/<time>/.config/nvim ~/.config/nvim`.
If there's no backup, removing the link is enough. Running `./install.sh` again
moves what you restored back to a backup and relinks.

## Check a machine

```sh
"$DOTFILES/doctor.sh"
```

Read-only. Shows tool versions and where they came from, whether the links point
here, missing plugins/parsers, and which languages are set up, with a fix-it hint
on every problem. It also warns if macOS would take Ctrl-Space, the tmux prefix,
to switch input sources, and if the clone is behind `origin`.

It also warns about each Lookalike of `shrink`: a command on `PATH`, or a
function or alias in `~/.zshrc.local` or `~/.oh-my-zsh/custom/`, whose name has
`compress`, `shrink`, `squash`, `small` or `minify` in it, in any case, and any
other `shrink` that runs instead of the repo's. It goes by name only, and
leaves commands from macOS's folders and Homebrew's `bin` alone. Nothing is
removed: if `shrink` does the job, remove the Lookalike by hand.

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

## Utilities

Commands `install.sh` puts on `PATH` (in `~/.local/bin`) on every Mac.

### shrink

Makes a Shrunk copy of each file next to it and leaves the original untouched:

```sh
shrink a.mov b.mp4        # writes a.shrunk.mp4 and b.shrunk.mp4
shrink -o ~/Desktop *.mov # into a folder
shrink IMG_0042.HEIC      # writes IMG_0042.shrunk.jpg
shrink report.pdf         # writes report.shrunk.pdf
shrink -n a.mov           # print the ffmpeg command instead of running it
```

Videos (`mov mp4 m4v mkv avi webm`) come out as H.264 `.mp4` at CRF 23, with
AAC stereo at 128k, the short side capped at 1080, the frame rate capped at 30
and the metadata kept; `--crf`, `--audio-bitrate`, `--max-res` and `--fps`
change those. On a terminal it shows ffmpeg's progress line. An HDR video (as
iPhones record) gets a warning: the shrunk copy is standard range and looks
washed out.

Images (`jpg jpeg png heic heif webp tif tiff`) keep their format, except HEIC,
HEIF and TIFF, which become `.jpg`. ImageMagick resizes them so the long edge is
at most 2560 (never enlarging) at quality 80, and PNGs go through `pngquant`;
`--max-edge` and `--quality` change those. Metadata stays, the EXIF
orientation tag included, and pixels aren't rotated, with two exceptions: a
HEIC comes out upright with orientation 1, and a TIFF is turned upright and
loses its EXIF.

PDFs go through Ghostscript at `/ebook` (images at about 150 dpi); `--pdf
screen` or `--pdf printer` picks another level. A damaged PDF fails rather than coming out incomplete,
and a PDF that's mostly text often comes out no smaller, so nothing is written.

`-f` replaces an existing output, and a result that
isn't smaller is deleted. `shrink -h` lists the options, `shrink --help
TYPE` every setting for `video`, `image` or `pdf`, and `man shrink` the full
reference. Tab completes its flags, the types after `--help`, the levels after
`--pdf`, and only the files it takes. A flag beats a `SHRINK_*` variable, which beats the
default, so a Mac can set its own defaults in `~/.zshrc.local`, such as
`export SHRINK_CRF=28`.

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

Checks (also run by CI on every PR, on pushes to `main` and weekly):

- `test/lint.sh`: shellcheck, secret scan (gitleaks), that the extras are
  documented, that CI runs every `test/*.sh` and this list names it (from the
  commit hook: every tracked one, so an untracked script doesn't block an
  unrelated commit), that text avoids the multi-word _Avoid_ entries in
  `GLOSSARY.md`, that `shrink`'s man page and completion know every flag its
  help lists (and the completion its extensions, types and PDF levels), and that the language
  recipes agree across `doctor.sh`, the nvim config and `LANGUAGES.md`. A new test script needs a `run:` step in
  `.github/workflows/check.yml` and a bullet here, and must source
  `lib/test-guard.sh`, which names the line that stopped it; sourced helpers go
  in `lib/`. Runs before each commit through the hook `install.sh` turns on,
  with `test/doctor-warnings.sh`, `test/updates.sh`, `test/ci-wait.sh` and
  `test/shrink.sh`, so a
  commit takes about half a minute. The hook also refuses commits on `main`;
  changes go through a PR.
- `test/lint-selftest.sh`: in a copy of the repo, removes or rewords the
  fresh-home.sh markers, malforms one, drops one marker's text from
  fresh-home.sh, adds an unmarked grep, breaks the extras rows, drops each test
  script's CI step and bullet here, adds an unlisted test script, blanks the
  glossary's _Avoid_ lines and adds each multi-word entry, drops a flag from
  `shrink`'s man page and completion and an extension, a type and a PDF level
  from the completion, one
  at a time, and
  checks that `test/lint.sh` fails on each. It also runs `lib/test-guard.sh` on a test that
  stops, and checks that lint as the commit hook runs it passes an untracked
  test script. Takes minutes.
- `test/doctor-warnings.sh`: runs `doctor.sh` in an empty temporary HOME with a
  fake `defaults` and Homebrew prefix, and checks when it warns.
- `test/updates.sh`: runs `update.sh` against a fake Homebrew and nvim and local
  repos, and checks brew upgrades below a minimum and the update reminder.
- `test/ci-wait.sh`: runs `ci-wait.sh` against a fake `gh`: a short SHA
  refused, no run yet, success and failure.
- `test/shrink.sh`: runs `shrink` against a fake `ffmpeg`, `ffprobe`, `magick`,
  `pngquant` and `gs`, and
  checks the commands it builds, its outputs and its errors.
- `test/fresh-home.sh`: full install in a temporary empty HOME, run twice, then
  doctor, then `man -w shrink` and shrink's completion in a new shell, and a
  real `shrink` of a small generated video, JPEG, PNG, HEIC and PDF.

After pushing to a PR, `./ci-wait.sh <full-sha>` waits for that commit's CI run
and prints one line with its result. After merging a PR, `./prune-merged.sh`
deletes the merged branches locally and on `origin`.

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
  of the keyboard shortcuts. Markdown files open rendered for reading (raw on
  the cursor line and in insert mode); **Space m r** switches the current file
  between rendered and raw.
