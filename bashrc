# archy: bashrc.
#
# Installed to ~/.bashrc. This is an interactive-shell rc, not a login rc: the
# login shell is /etc/profile and ~/.bash_profile.
#
# Nothing here sources the old setup, and nothing is generated. If a line looks
# like it was written for a specific machine, it is, and that is deliberate.
#
# The first block runs for every bash, interactive or not, because the PATH
# setup has to be there for a script that is run over SSH. Everything after the
# interactive check is shell-prompt territory and is skipped for scripts.

# --------------------------------------------------------------- every shell

# Locale, for non-login shells. /etc/profile.d/locale.sh only runs at login, so
# bash started by SSH lands in the C locale, where printf emits \u and \U
# escapes literally instead of the character.
if [[ -z ${LANG:-} ]]; then
  [[ -r /etc/locale.conf ]] && . /etc/locale.conf
  LANG="${LANG:-C.UTF-8}"
  export LANG LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY \
    LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT \
    LC_IDENTIFICATION
fi

# ~/.local/bin holds the archy-* scripts, and the keybinds call them by
# absolute path so they work regardless — but a shell that cannot find them on
# PATH cannot be typed at interactively.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$PATH:$HOME/.local/bin" ;;
esac

# If not running interactively, nothing below applies. Leave this above the
# rest so a script pays only for the two blocks above.
[[ $- != *i* ]] && return

# --------------------------------------------------------------- environment

# Editor for anything that shells out to $EDITOR.
export EDITOR="${EDITOR:-code --wait}"
export SUDO_EDITOR="$EDITOR"

export BAT_THEME=ansi

# Colored man pages. col strips the bold/underline, bat does the colorizing.
export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# ------------------------------------------------------------------- prompt

# starship first: the blank-line hook below is registered through a variable
# starship reads, and it has to exist before starship initializes.
if command -v starship &> /dev/null; then
  __starship_first_prompt=1
  starship_precmd_user_func=__starship_blankline

  # A blank line between commands, but not before the first prompt.
  #
  # The clear/reset skip is the part that matters: clear wipes the screen, and
  # a blank line printed after it lands the prompt on row 2 with a dead row 1
  # above it, which looks like a rendering bug every time.
  __starship_blankline() {
    if [[ ${__starship_first_prompt:-1} -eq 1 ]]; then
      __starship_first_prompt=0
      return
    fi

    local _last
    _last=$(HISTTIMEFORMAT= history 1 2>/dev/null | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//') || _last=""

    if [[ $_last =~ ^[[:space:]]*(command[[:space:]]+|builtin[[:space:]]+)?(clear|reset)([[:space:];|&]|$) ]]; then
      return
    fi

    printf '\n'
  }

  # Only for a real terminal. TERM=dumb is a pipe or a script, and the escape
  # sequences would end up in the output.
  [[ ${TERM:-} != "dumb" ]] && eval "$(starship init bash)"
fi

# zoxide learns directories, and this makes cd into it.
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init bash)"

  # zd is the plain version: zoxide handles a path that exists, and falls back
  # to a search when it does not. The function exists to print the new directory
  # after a jump, which the init hook does not do.
  zd() {
    if (( $# == 0 )); then
      builtin cd ~ || return
    elif [[ -d $1 ]]; then
      builtin cd "$1" || return
    else
      if ! z "$@"; then
        echo "Error: Directory not found"
        return
      fi
      printf "\U000F17A9 "
      pwd
    fi
  }
fi

# mise pins tool versions per directory.
if command -v mise &> /dev/null; then
  eval "$(mise activate bash)"
fi

# fzf ships its own completions and key bindings. Sourced from the package,
# which is where the package puts them.
if [[ -f /usr/share/fzf/completion.bash ]]; then
  source /usr/share/fzf/completion.bash
fi
if [[ -f /usr/share/fzf/key-bindings.bash ]]; then
  source /usr/share/fzf/key-bindings.bash
fi

# ------------------------------------------------------------------ aliases

# Filesystem. eza when it is there, so the aliases do not resolve to a command
# that is not installed and fail on the first press.
if command -v eza &> /dev/null; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

# fzf over files. The kitty branch previews images inline, which is worth the
# extra case because this is the terminal in daily use.
if [[ $TERM == "xterm-kitty" ]]; then
  alias ff="fzf --preview 'case \$(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=\${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'"
else
  alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
fi

# Directories.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# open in the desktop's file handler, detached, so the shell is not held up.
open() (
  xdg-open "$@" >/dev/null 2>&1 &
)

# Daily tools.
alias d='docker'
alias t='tmux attach || tmux new -s Work'

# nvim as n. The function rather than an alias so the arguments pass through and
# nvim is still reachable under its real name.
n() {
  if [ "$#" -eq 0 ]; then
    command nvim .
  else
    command nvim "$@"
  fi
}

# Git.
alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'

# ----------------------------------------------------------------- functions

# Pick a file with fzf, then scp it somewhere.
sff() {
  if [ $# -eq 0 ]; then
    echo "Usage: sff <destination> (e.g. sff host:/tmp/)"
    return 1
  fi
  local file
  file=$(find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2- | ff) &&
    [ -n "$file" ] && scp "$file" "$1"
}

# ------------------------------------------------------ services, as aliases

# Docker. Start brings the socket and containerd up in the right order, which is
# the order that matters: docker.service alone fails to start the socket it is
# supposed to be listening on.
alias docker-start='sudo systemctl start docker.service'
alias docker-stop='sudo systemctl stop docker.socket docker.service containerd.service'
alias docker-status='systemctl is-active docker.service containerd.service'

# Postgres.
alias pg-start='sudo systemctl start postgresql.service'
alias pg-stop='sudo systemctl stop postgresql.service'
alias pg-status='systemctl is-active postgresql.service'

# ----------------------------------------------------------------- toolchain

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

export PATH="$HOME/.opencode/bin:$PATH"
export UV_INIT_BARE=1

# ------------------------------------------------------------------- aliases

command -v fastfetch &> /dev/null && alias f='fastfetch'
command -v bat &> /dev/null && alias cat='bat'
