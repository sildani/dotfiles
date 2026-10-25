#!/usr/bin/env bash
# Fast checks: shellcheck, secret scan, and that the language recipes agree
# across doctor.sh, the nvim config and LANGUAGES.md. Run by CI and the
# pre-commit hook.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
CONFIGS=nvim/lua/configs
errors=0
err() { echo "lint: $1" >&2; errors=$((errors + 1)); }

shellcheck -x install.sh doctor.sh lib/common.sh test/*.sh hooks/* || err "shellcheck failed"

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
