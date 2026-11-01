#!/usr/bin/env bash
# Fast checks: shellcheck, zsh syntax, secret scan, that the docs list every
# config link, override file, extra and test script, that CI runs every test
# script and each has lib/test-guard.sh, that the messages fresh-home.sh greps
# for are marked, that text avoids the glossary's multi-word _Avoid_ entries,
# and that the language recipes agree across doctor.sh, the nvim config and
# LANGUAGES.md.
# Run by CI and the commit hook.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
CONFIGS=nvim/lua/configs
errors=0
err() { echo "lint: $1" >&2; errors=$((errors + 1)); }

shellcheck -x install.sh doctor.sh update.sh prune-merged.sh lib/common.sh test/*.sh hooks/* || err "shellcheck failed"

# One file per call: zsh -n treats any extra files as arguments to the first.
for f in zsh/* zsh/extras/*; do
  [[ -f "$f" ]] || continue
  zsh -n "$f" || err "zsh syntax check failed: $f"
done

# test/lint-selftest.sh sets LINT_SKIP_SECRETS=1: its copies have only a
# snapshot commit, and its many runs stay fast.
if [[ -n "${LINT_SKIP_SECRETS:-}" ]]; then
  echo "lint: LINT_SKIP_SECRETS set, skipping secret scan" >&2
elif command -v gitleaks >/dev/null; then
  # The commit hook sets LINT_STAGED=1 to scan what's about to be committed.
  scope=()
  [[ -n "${LINT_STAGED:-}" ]] && scope=(--pre-commit --staged)
  gitleaks git --redact --no-banner ${scope[@]+"${scope[@]}"} . || err "gitleaks found a possible secret"
elif [[ -n "${CI:-}" ]]; then
  err "gitleaks not installed"
else
  echo "lint: gitleaks not installed, skipping secret scan (brew install gitleaks)" >&2
fi

# Every linked config and per-machine override file in lib/common.sh is
# documented where people and agents look for it.
# shellcheck source=lib/common.sh
source lib/common.sh
for entry in "${LINKS[@]}"; do
  src="${entry%%:*}"
  grep -Eq "\`$src/?\`" README.md || err "README.md link table is missing \`$src\` (LINKS in lib/common.sh)"
done
for f in "${LOCAL_FILES[@]}"; do
  f="${f#"$REPO_DIR"/}"
  f="${f/#$HOME/~}"
  for doc in README.md AGENTS.md; do
    grep -qF "$f" "$doc" || err "$doc doesn't mention $f (LOCAL_FILES in lib/common.sh)"
  done
done

# Every test script runs in CI, is in the README "Checks" list and has the guard.
# Sourced helpers go in lib/, not test/, so every test/*.sh is a script CI runs.
for f in test/*.sh; do
  path_re="${f//./\\.}"
  grep -Eq "^[[:space:]]*-?[[:space:]]*run:[[:space:]]*${path_re}[[:space:]]*\$" .github/workflows/check.yml ||
    err ".github/workflows/check.yml doesn't run $f"
  grep -q "^- \`${path_re}\`:" README.md || err "README.md \"Checks\" list is missing \`$f\`"
  grep -q '^source .*lib/test-guard\.sh"$' "$f" || err "$f doesn't source lib/test-guard.sh, so a stop under set -e could print nothing"
done

# Every opt-in extra has a row in the README's extras table that ends in its
# line and per-machine file (fresh-home.sh turns it on from them), and every
# extras folder has a per-machine file to turn it on from, so doctor.sh can
# report it.
for f in */extras/*; do
  row="$(grep -F "| \`$f\` " README.md)" || { err "README.md extras table is missing \`$f\`"; continue; }
  [[ "$row" =~ $EXTRAS_ROW_RE ]] ||
    err "README.md extras row for $f doesn't end in | \`<line>\` | \`<file>\` | (EXTRAS_ROW_RE in lib/common.sh)"
done
for dir in */extras; do
  [[ -d "$dir" ]] || continue
  tool="${dir%%/*}" host=""
  for pair in "${EXTRAS_HOSTS[@]}"; do
    [[ "${pair%%:*}" == "$tool" ]] && host="${pair#*:}"
  done
  if [[ -z "$host" ]]; then
    err "$dir has no entry in EXTRAS_HOSTS (lib/common.sh)"
  elif [[ " ${LOCAL_FILES[*]} " != *" $host "* ]]; then
    err "EXTRAS_HOSTS file for $tool isn't in LOCAL_FILES: $host"
  fi
done

# The repo can be cloned anywhere: docs and extras lines reach it through
# $DOTFILES or a link install.sh made, and the clone path appears only as
# README's example.
# shellcheck disable=SC2088  # literal text to search for, split so this file doesn't match
clone_path='~/code''/dotfiles'
while IFS= read -r hit; do
  [[ "$hit" == "README.md:DOTFILES=$clone_path "* ]] || err "hard-coded clone path, use \$DOTFILES or a link install.sh made: $hit"
done < <(grep -rF --exclude-dir=.git --exclude-dir=.scratch -- "$clone_path" . | sed 's|^\./||')

# Text uses the glossary's terms: no multi-word _Avoid_ entry in any other
# tracked file, wrapped over lines or `#` comments too. Review covers the single
# words, since most uses of them are fine.
phrases=()
while IFS= read -r phrase; do phrases+=("$phrase"); done < <(avoid_phrases)
((${#phrases[@]})) || err "no multi-word _Avoid_ entries in GLOSSARY.md"
while IFS= read -r file; do
  text=" $(LC_ALL=C tr -s ' \t\n#' ' ' <"$file" | LC_ALL=C tr '[:upper:]' '[:lower:]') "
  for phrase in ${phrases[@]+"${phrases[@]}"}; do
    if [[ "$text" == *[![:alnum:]]"$phrase"[![:alnum:]]* ]]; then
      err "$file says \"$phrase\", which GLOSSARY.md lists under _Avoid_"
    fi
  done
done < <(git grep -Il '' -- . ':!GLOSSARY.md')

# Messages test/fresh-home.sh greps for carry a `# fresh-home.sh greps for
# "<text>"` marker where they're printed, so whoever rewords one updates the
# test: each marker is still in the test, each script line with a marker's
# text carries one, and each grep on script output is covered by a marker.
marker_files=(install.sh doctor.sh lib/common.sh)
markers=()
while IFS= read -r marker; do markers+=("$marker"); done < <(
  sed -nE 's/.*# fresh-home\.sh greps for "(.*)"$/\1/p' "${marker_files[@]}" | sort -u)
for marker in ${markers[@]+"${markers[@]}"}; do
  # <placeholders> are gaps: each fixed piece must appear.
  while IFS= read -r piece; do
    [[ -z "$piece" ]] && continue
    grep -qF -- "$piece" test/fresh-home.sh ||
      err "test/fresh-home.sh no longer greps for \"$piece\", from marker \"$marker\" (${marker_files[*]})"
    while IFS=: read -r file n code; do
      [[ "$code" == *"# fresh-home.sh greps for"* || "$code" == *"# fresh-home.sh doesn't grep for this"* ]] ||
        err "$file:$n prints \"$piece\" without its marker: # fresh-home.sh greps for \"$marker\""
    done < <(grep -nF -- "$piece" "${marker_files[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  done < <(sed -E 's/<[^>]+>/\n/g' <<<"$marker")
done

# grep_texts <grep arguments>: the texts the grep matches, one per line: each
# top-level alternative of a single-quoted pattern, and each piece of a
# double-quoted one between its $variables.
grep_texts() {
  { grep -oE "'[^']*'" <<<"$1" || true; } | awk '{
    s = ""; depth = 0
    for (i = 2; i < length($0); i++) {
      c = substr($0, i, 1)
      if (c == "(") depth++
      if (c == ")") depth--
      if (c == "|" && depth == 0) { print s; s = "" } else s = s c
    }
    print s
  }'
  { grep -oE '"[^"]*"' <<<"$1" || true; } | sed -E 's/^"//; s/"$//; s/\$\{[^}]*\}|\$[A-Za-z_][A-Za-z_0-9]*/\n/g'
}
# Only one-line greps on these four outputs are scanned. Texts of 2 characters
# or fewer (left between $variables) are skipped. A grep on something else
# (diff's own output, a seeded line) ends in `# not a script message`.
# shellcheck disable=SC2016  # a literal $ in the pattern
while IFS=: read -r n line; do
  [[ "$line" == *"# not a script message"* ]] && continue
  grep_args="${line#*grep }"
  grep_args="${grep_args%%<<<*}"
  while IFS= read -r text; do
    ((${#text} > 2)) || continue
    covered=false
    for marker in ${markers[@]+"${markers[@]}"}; do
      [[ "$text" == *"$marker"* || "$marker" == *"$text"* ]] && covered=true
    done
    $covered || err "test/fresh-home.sh:$n greps script output for '$text', but no script marks a message with it (# fresh-home.sh greps for \"...\")"
  done < <(grep_texts "$grep_args")
done < <(grep -nE 'grep .*<<<"\$(first|second|diff_out|doctor_out)"' test/fresh-home.sh)

# tmux-continuum auto-saves from a hook it adds to status-right when TPM loads
# it, so status-left/right must be set before TPM's run line, not after.
tpm_line="$(grep -n "^run '~/.tmux/plugins/tpm/tpm'" tmux/tmux.conf | cut -d: -f1)"
if [[ -z "$tpm_line" || "$tpm_line" == *$'\n'* ]]; then
  err "tmux/tmux.conf needs exactly one TPM run line"
else
  while IFS=: read -r n line; do
    ((n < tpm_line)) || err "tmux/tmux.conf:$n sets the status bar after TPM's run line, wiping continuum's auto-save: $line"
  done < <(grep -nE '^set(-option)? .*status-(left|right) ' tmux/tmux.conf)
fi

# Each [LANG] marker sits in all three nvim config files.
for marker in JAVA PYTHON GO; do
  for f in treesitter.lua lspconfig.lua conform.lua; do
    grep -q "\[$marker\]" "$CONFIGS/$f" || err "[$marker] marker missing from $CONFIGS/$f"
  done
done

# Each language doctor.sh checks has a LANGUAGES.md section, and its parser,
# server and Mason packages appear where the recipe says to enable them.
while read -r line; do
  args=()
  while IFS= read -r tok; do args+=("$tok"); done < <(xargs printf '%s\n' <<<"$line")
  name="${args[1]}" parser="${args[5]}" server="${args[6]}"
  grep -qx "## $name" LANGUAGES.md || err "LANGUAGES.md has no '## $name' section (doctor links to it)"
  grep -q "\"$parser\"" "$CONFIGS/treesitter.lua" || err "$name: parser \"$parser\" not in treesitter.lua"
  grep -q "\"$server\"" "$CONFIGS/lspconfig.lua" || err "$name: server \"$server\" not in lspconfig.lua"
  for pkg in "${args[@]:7}"; do
    grep -Eq ":MasonInstall .*\b$pkg\b" LANGUAGES.md || err "$name: Mason package $pkg not in LANGUAGES.md"
  done
done < <(grep -E '^[[:space:]]+language_status [A-Z]' doctor.sh)

if ((errors)); then
  echo "lint: $errors problem(s)" >&2
  exit 1
fi
echo "lint: ok"
