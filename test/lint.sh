#!/usr/bin/env bash
# Fast checks: shellcheck, zsh syntax, secret scan, that the docs list every
# config link, override file and extra, and that the language recipes agree
# across doctor.sh, the nvim config and LANGUAGES.md. Run by CI and the
# pre-commit hook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
CONFIGS=nvim/lua/configs
errors=0
err() { echo "lint: $1" >&2; errors=$((errors + 1)); }

shellcheck -x install.sh doctor.sh lib/common.sh test/*.sh hooks/* || err "shellcheck failed"

# One file per call: zsh -n treats any extra files as arguments to the first.
for f in zsh/* zsh/extras/*; do
  [[ -f "$f" ]] || continue
  zsh -n "$f" || err "zsh syntax check failed: $f"
done

if command -v gitleaks >/dev/null; then
  # The pre-commit hook sets LINT_STAGED=1 to scan what's about to be committed.
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

# Every opt-in extra is in the README's extras table, and every extras folder
# has a per-machine file to turn it on from, so doctor.sh can report it.
for f in */extras/*; do
  grep -qF "\`$f\`" README.md || err "README.md extras table is missing \`$f\`"
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
