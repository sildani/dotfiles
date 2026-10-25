# Prompt that starts with the current UTC time, e.g.
#   2026-10-25 16:30:00 ➜  main
# The arrow is green or red by the last command's exit status, like robbyrussell.
# Turn on by sourcing this from ~/.zshrc.local (after Oh My Zsh, for git_prompt_info).

prompt_utc_time() {
  date -u +'%Y-%m-%d %H:%M:%S'
}

setopt PROMPT_SUBST

PROMPT='%B%F{117}$(prompt_utc_time)%f%b '
PROMPT+='%(?:%F{green}%B➜%b%f:%F{red}%B➜%b%f) '
PROMPT+='$(git_prompt_info)'
