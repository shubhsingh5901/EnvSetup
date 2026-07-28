#!/usr/bin/env bash
#
#   brush-superpowers installer
#   fish + tide ergonomics, on brush (a bash/POSIX-compatible shell in Rust)
#
#   Installs: brush · starship · atuin · fzf · zoxide · direnv · gh · kubectx
#   Deploys:  ~/.config/bash/superpowers.bash · ~/.config/starship*.toml
#             ~/.local/bin/gh-prompt · a starship-choices.json next to
#             this script (edit it and re-run --customize to change your
#             prompt without me hand-writing TOML)
#   Then offers to set your default login shell.
#
#   Nothing is installed until you have seen the full plan and approved it.
#
#   Usage:  bash install-brush-superpowers.sh [options]
#
#   Options:
#     -y, --yes           pre-approve everything (for CI / unattended runs)
#     -n, --dry-run       show what would happen, touch nothing
#     -a, --ask-each      prompt separately before every single package
#     -d, --doctor        check an existing install and exit; changes nothing
#         --customize     re-run the prompt wizard even if a preferences
#                         JSON already exists next to this script
#         --no-font       skip Nerd Font installation
#         --set-shell P   set default login shell to P without prompting
#         --config-only   skip package installation, just deploy configs
#     -h, --help          this text
#
#   Written for bash 3.2+ so it survives macOS's ancient system bash.
#

set -uo pipefail

# ══════════════════════════════════════════════════════════════════ options
DRY_RUN=0; ASSUME_YES=0; SKIP_FONT=0; CONFIG_ONLY=0; SET_SHELL=""; ASK_EACH=0
DOCTOR=0; CUSTOMIZE=0
APPROVE_MODE=""      # all | each | none   — decided by the consent gate
PLAN=""; PLAN_N=0

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)      ASSUME_YES=1 ;;
    -a|--ask-each) ASK_EACH=1 ;;
    -d|--doctor)   DOCTOR=1 ;;
    --customize)   CUSTOMIZE=1 ;;
    -n|--dry-run)  DRY_RUN=1 ;;
    --no-font)     SKIP_FONT=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    --set-shell)   SET_SHELL="${2:-}"; shift ;;
    --set-shell=*) SET_SHELL="${1#*=}" ;;
    -h|--help)     sed -n '3,26p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# ═══════════════════════════════════════════════════════════════════ colour
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  R=$'\033[0m';  B=$'\033[1m';   D=$'\033[2m';   I=$'\033[3m'
  RED=$'\033[38;5;203m';   GRN=$'\033[38;5;114m'; YEL=$'\033[38;5;221m'
  BLU=$'\033[38;5;111m';   MAG=$'\033[38;5;177m'; CYN=$'\033[38;5;80m'
  GRY=$'\033[38;5;245m';   WHT=$'\033[38;5;255m'
  BG_OK=$'\033[48;5;114m\033[38;5;16m'; BG_ERR=$'\033[48;5;203m\033[38;5;16m'
else
  R= B= D= I= RED= GRN= YEL= BLU= MAG= CYN= GRY= WHT= BG_OK= BG_ERR=
fi

# ══════════════════════════════════════════════════════════════════ logging
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bash-superpowers"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
: > "$LOG" 2>/dev/null || LOG=/dev/null

log()  { printf '%s\n' "$*" >> "$LOG" 2>/dev/null; }
hr()   { printf '%s%s%s\n' "$D$GRY" "$(printf '─%.0s' $(seq 1 ${COLS:-68}))" "$R"; }
h1()   { printf '\n%s%s▌ %s%s\n\n' "$B" "$MAG" "$1" "$R"; }
ok()   { printf '  %s✔%s %s\n' "$GRN" "$R" "$1"; log "OK   $1"; }
warn() { printf '  %s▲%s %s\n' "$YEL" "$R" "$1"; log "WARN $1"; WARNINGS=$((WARNINGS+1)); }
bad()  { printf '  %s✘%s %s\n' "$RED" "$R" "$1"; log "FAIL $1"; FAILURES=$((FAILURES+1))
         FAILED_STEPS="${FAILED_STEPS}${1%%  *}
"; }
note() { printf '  %s•%s %s%s%s\n' "$BLU" "$R" "$GRY" "$1" "$R"; }
skip() { printf '  %s∘%s %s%s%s\n' "$GRY" "$R" "$GRY" "$1" "$R"; log "SKIP $1"; }

WARNINGS=0; FAILURES=0; INSTALLED=""; FELLBACK=""; FAILED_STEPS=""
COLS=$(tput cols 2>/dev/null || echo 76); [ "$COLS" -gt 76 ] && COLS=76

banner() {
  printf '\n'
  printf '%s%s   ██████╗  █████╗ ███████╗██╗  ██╗%s\n'      "$B" "$MAG" "$R"
  printf '%s%s   ██╔══██╗██╔══██╗██╔════╝██║  ██║%s\n'      "$B" "$MAG" "$R"
  printf '%s%s   ██████╔╝███████║███████╗███████║%s   %ssuperpowers%s\n' "$B" "$BLU" "$R" "$B$WHT" "$R"
  printf '%s%s   ██╔══██╗██╔══██║╚════██║██╔══██║%s   %sfish + tide ergonomics,%s\n' "$B" "$BLU" "$R" "$GRY" "$R"
  printf '%s%s   ██████╔╝██║  ██║███████║██║  ██║%s   %son a real POSIX shell%s\n'   "$B" "$CYN" "$R" "$GRY" "$R"
  printf '%s%s   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝%s\n\n'    "$B" "$CYN" "$R"
}

FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin() {
  local pid=$1 msg=$2 i=0
  tput civis 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 10 ))
    printf '\r  %s%s%s %s%s%s' "$CYN" "${FRAMES[$i]}" "$R" "$GRY" "$msg" "$R"
    sleep 0.08
  done
  tput cnorm 2>/dev/null
  printf '\r\033[2K'
}

# run_step "human label" cmd args...
run_step() {
  local msg=$1; shift
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  %s◌%s %s %s(dry-run: %s)%s\n' "$D" "$R" "$msg" "$D" "$1" "$R"
    return 0
  fi
  log "── $msg"; log "\$ $*"
  local rc=0
  if [ -t 1 ]; then
    ( "$@" >>"$LOG" 2>&1 ) & local pid=$!
    spin "$pid" "$msg"
    wait "$pid"; rc=$?
  else
    "$@" >>"$LOG" 2>&1; rc=$?
  fi
  [ "$rc" -eq 0 ] && ok "$msg" || bad "$msg  ${D}(details: $LOG)${R}"
  return $rc
}

have()    { command -v "$1" >/dev/null 2>&1; }
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ -t 0 ] || return 1
  local a; printf '  %s?%s %s %s[y/N]%s ' "$YEL" "$R" "$1" "$D" "$R"
  read -r a; case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ════════════════════════════════════════════════════════════════ platform
OS=""; PKG=""; DISTRO=""
detect_platform() {
  case "$(uname -s)" in
    Darwin) OS=macos; DISTRO="macOS $(sw_vers -productVersion 2>/dev/null)" ;;
    Linux)  OS=linux
            if [ -r /etc/os-release ]; then
              # shellcheck disable=SC1091
              DISTRO=$(. /etc/os-release; printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}")
            else DISTRO=Linux; fi ;;
    *)      OS=unknown; DISTRO=$(uname -s) ;;
  esac
  if   have brew;    then PKG=brew
  elif have apt-get; then PKG=apt
  elif have dnf;     then PKG=dnf
  elif have pacman;  then PKG=pacman
  elif have zypper;  then PKG=zypper
  elif have apk;     then PKG=apk
  else PKG=none; fi
}

SUDO=""
ensure_sudo() {
  [ "$(id -u)" -eq 0 ] && { SUDO=""; return 0; }
  have sudo || { SUDO=""; return 1; }
  SUDO=sudo
  [ "$DRY_RUN" -eq 1 ] && return 0
  if ! sudo -n true 2>/dev/null; then
    printf '  %s🔑%s sudo is needed to install system packages.\n' "$YEL" "$R"
    sudo -v || return 1
  fi
  # keep the ticket warm so the spinner never hides a password prompt
  ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
  return 0
}

pkg_refresh_done=0
pkg_refresh() {
  [ "$pkg_refresh_done" -eq 1 ] && return 0
  pkg_refresh_done=1
  case "$PKG" in
    apt)    run_step "refreshing apt index" $SUDO apt-get update -qq ;;
    pacman) run_step "refreshing pacman db" $SUDO pacman -Sy --noconfirm ;;
    brew)   run_step "refreshing homebrew"  brew update ;;
  esac
}

# pkg_install <generic-name>  → 0 on success
pkg_install() {
  local g=$1
  local p="$g"
  case "$PKG:$g" in
    apt:gh)          p=gh ;;
    apt:kubectx)     p=kubectx ;;
    dnf:gh)          p=gh ;;
    dnf:kubectx)     p=kubectx ;;
    pacman:gh)       p=github-cli ;;
    pacman:kubectx)  p=kubectx ;;
    brew:gh)         p=gh ;;
    zypper:gh)       p=gh ;;
    apk:gh)          p=github-cli ;;
  esac
  pkg_refresh
  case "$PKG" in
    brew)   run_step "installing $g"       brew install "$p" ;;
    apt)    run_step "installing $g (apt)" env DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$p" ;;
    dnf)    run_step "installing $g (dnf)" $SUDO dnf install -y -q "$p" ;;
    pacman) run_step "installing $g (pacman)" $SUDO pacman -S --needed --noconfirm "$p" ;;
    zypper) run_step "installing $g (zypper)" $SUDO zypper --non-interactive install "$p" ;;
    apk)    run_step "installing $g (apk)" $SUDO apk add --quiet "$p" ;;
    *)      return 1 ;;
  esac
}

fallback() { [ "$DRY_RUN" -eq 1 ] || FELLBACK="$FELLBACK $1"; }
mark()     { [ "$DRY_RUN" -eq 1 ] || INSTALLED="$INSTALLED $1"; }

# ═══════════════════════════════════════════════════════════════ consent
plan_add() { PLAN="$PLAN $1"; PLAN_N=$((PLAN_N + 1)); }

method_for() {
  case "$1" in
    starship)
      if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then echo "$PKG"
      else echo "vendor script — starship.rs/install.sh"; fi ;;
    atuin)
      if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then echo "$PKG"
      else echo "vendor script — setup.atuin.sh"; fi ;;
    zoxide)   echo "$PKG, else vendor script" ;;
    kubectx)  echo "$PKG, else raw scripts → ~/.local/bin" ;;
    gh)       if [ "$PKG" = apt ]; then echo "apt — adds the cli.github.com repo"
              else echo "$PKG"; fi ;;
    brush)    if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then echo "$PKG"
              else echo "cargo binstall brush-shell (prebuilt), else cargo install"; fi ;;
    font)     if [ "$OS" = macos ]; then echo "brew cask"
              else echo "GitHub release → ~/.local/share/fonts"; fi ;;
    *)        echo "$PKG" ;;
  esac
}

# want <tool> → 0 if this tool is approved for installation
want() {
  case "$APPROVE_MODE" in
    all)  return 0 ;;
    none) skip "$1 — declined"; return 1 ;;
    each)
      if confirm "install ${B}$1${R}?  ${D}($(method_for "$1"))${R}"; then return 0
      else skip "$1 — declined"; return 1; fi ;;
    *)    return 1 ;;
  esac
}

consent_gate() {
  h1 "Nothing has been installed yet"

  if [ "$CONFIG_ONLY" -eq 1 ]; then
    printf '  %s--config-only%s: no packages will be touched.\n\n' "$B" "$R"
  elif [ "$PLAN_N" -eq 0 ]; then
    printf '  Every tool is already present — nothing to install.\n\n'
  else
    printf '  This would install %s%d%s thing(s):\n\n' "$B$WHT" "$PLAN_N" "$R"
    local t
    for t in $PLAN; do
      printf '    %s+%s %-12s %s%s%s\n' "$GRN" "$R" "$t" "$D" "$(method_for "$t")" "$R"
    done
    printf '\n'
  fi

  printf '  And write these files %s(existing ones are backed up first)%s:\n\n' "$D" "$R"
  printf '    %s~/.config/bash/superpowers.bash%s\n' "$CYN" "$R"
  printf '    %s~/.config/starship.toml%s %s(copied from CONFIG_LOCAL below)%s\n' "$CYN" "$R" "$D" "$R"
  printf '    %s%s%s %s(a small prompt-preferences wizard runs first time; edit%s\n' "$CYN" "$CHOICES_FILE" "$R" "$D" "$R"
  printf '    %sthis file and re-run with --customize instead of hand-editing TOML)%s\n' "$D" "$R"
  printf '    %s~/.local/bin/gh-prompt%s\n'          "$CYN" "$R"
  printf '    %s~/.local/bin/ghacct-prompt%s\n'      "$CYN" "$R"
  printf '    %s~/.bashrc%s %s— appends a 3-line source hook%s\n\n' "$CYN" "$R" "$D" "$R"
  printf '  %sOutside your home directory nothing changes,%s except /etc/shells —\n' "$D" "$R"
  printf '  %sand only if you pick a new login shell at the end, which is also asked.%s\n' "$D" "$R"
  printf '  %sYour fish setup is never read, moved, or deleted.%s\n' "$D" "$R"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n'; note "dry run — proceeding without asking, but writing nothing"
    APPROVE_MODE=all; return 0
  fi
  if [ "$ASSUME_YES" -eq 1 ]; then
    printf '\n'; note "--yes given — treating all of the above as approved"
    APPROVE_MODE=all; return 0
  fi
  if [ ! -t 0 ]; then
    printf '\n'; bad "no terminal available to ask for your consent"
    note "re-run with --yes if you have read the plan above and accept it"
    exit 1
  fi
  if [ "$CONFIG_ONLY" -eq 1 ]; then
    if confirm "Write those config files?"; then APPROVE_MODE=none; return 0; fi
    warn "declined — nothing was written"; exit 0
  fi
  if [ "$PLAN_N" -eq 0 ]; then
    if confirm "Write those config files?"; then APPROVE_MODE=all; return 0; fi
    warn "declined — nothing was written"; exit 0
  fi
  if [ "$ASK_EACH" -eq 1 ]; then APPROVE_MODE=each; return 0; fi

  printf '\n'
  printf '    %sa%s  install everything above\n'                    "$B$CYN" "$R"
  printf '    %ss%s  ask me separately before each package\n'        "$B$CYN" "$R"
  printf '    %sc%s  configs only — install no packages\n'           "$B$CYN" "$R"
  printf '    %sq%s  quit, change nothing\n\n'                       "$B$CYN" "$R"
  local a
  printf '  %s?%s your choice %s[a/s/c/q]%s ' "$YEL" "$R" "$D" "$R"
  read -r a
  case "$a" in
    a|A)       APPROVE_MODE=all ;;
    s|S)       APPROVE_MODE=each ;;
    c|C)       APPROVE_MODE=none ;;
    ''|q|Q|*)  printf '\n'; note "nothing was changed. run again any time."; exit 0 ;;
  esac
}

# ══════════════════════════════════════════════════════════ tool installers
install_homebrew() {
  have brew && return 0
  [ "$OS" = macos ] || return 1
  confirm "Homebrew is missing and macOS needs it. Install Homebrew?" || return 1
  run_step "installing Homebrew" bash -c \
    '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' || return 1
  for p in /opt/homebrew/bin /usr/local/bin; do
    [ -x "$p/brew" ] && { eval "$("$p/brew" shellenv)"; PKG=brew; }
  done
}


install_brush() {
  have brush && { skip "brush already present"; return 0; }
  want brush || return 0
  if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then
    pkg_install brush && { mark brush; return 0; }
  fi
  fallback brush
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install brush via cargo-binstall, falling back to cargo install"
    return 0
  fi
  if have cargo-binstall; then
    run_step "installing brush (cargo binstall, prebuilt)" cargo binstall --no-confirm brush-shell \
      && { mark brush; return 0; }
  fi
  have cargo || { bad "brush needs cargo (no cargo-binstall, no brew/pacman package here)"; \
                  note "install Rust via https://rustup.rs, then re-run this script"; return 1; }
  run_step "installing brush (cargo install, this compiles from source)" cargo install --locked brush-shell \
    && mark brush
}

install_starship() {
  have starship && { skip "starship already present"; return 0; }
  want starship || return 0
  if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then
    pkg_install starship && { mark starship; return 0; }
  fi
  fallback starship
  run_step "installing starship (vendor script)" bash -c \
    'curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"' \
    && mark starship
}

install_atuin() {
  have atuin && { skip "atuin already present"; return 0; }
  want atuin || return 0
  if [ "$PKG" = brew ] || [ "$PKG" = pacman ]; then
    pkg_install atuin && { mark atuin; return 0; }
  fi
  fallback atuin
  run_step "installing atuin (vendor script)" bash -c \
    'curl --proto "=https" --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --no-modify-path' \
    && mark atuin
}

install_zoxide() {
  have zoxide && { skip "zoxide already present"; return 0; }
  want zoxide || return 0
  pkg_install zoxide && { mark zoxide; return 0; }
  fallback zoxide
  run_step "installing zoxide (vendor script)" bash -c \
    'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh' \
    && mark zoxide
}

install_gh() {
  have gh && { skip "gh already present"; return 0; }
  want gh || return 0
  if [ "$PKG" = apt ]; then
    run_step "adding GitHub CLI apt repository" bash -c '
      set -e
      out=/etc/apt/keyrings/githubcli-archive-keyring.gpg
      '"$SUDO"' mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | '"$SUDO"' tee "$out" >/dev/null
      '"$SUDO"' chmod go+r "$out"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=$out] https://cli.github.com/packages stable main" \
        | '"$SUDO"' tee /etc/apt/sources.list.d/github-cli.list >/dev/null'
    pkg_refresh_done=0
  fi
  pkg_install gh && mark gh
}

install_kubectx() {
  if have kubectx && have kubens; then skip "kubectx/kubens already present"; return 0; fi
  want kubectx || return 0
  pkg_install kubectx && { mark kubectx; return 0; }
  fallback kubectx
  run_step "installing kubectx/kubens (raw scripts)" bash -c '
    set -e; mkdir -p "$HOME/.local/bin"
    base=https://raw.githubusercontent.com/ahmetb/kubectx/master
    curl -fsSL "$base/kubectx" -o "$HOME/.local/bin/kubectx"
    curl -fsSL "$base/kubens"  -o "$HOME/.local/bin/kubens"
    chmod +x "$HOME/.local/bin/kubectx" "$HOME/.local/bin/kubens"' \
    && mark kubectx
}

install_font() {
  [ "$SKIP_FONT" -eq 1 ] && { skip "Nerd Font (--no-font)"; return 0; }
  if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    skip "JetBrainsMono Nerd Font already installed"; return 0
  fi
  want font || return 0
  if [ "$OS" = macos ]; then
    run_step "installing JetBrainsMono Nerd Font" brew install --cask font-jetbrains-mono-nerd-font \
      && mark font
  else
    run_step "installing JetBrainsMono Nerd Font" bash -c '
      set -e
      dir="$HOME/.local/share/fonts"; mkdir -p "$dir"
      url=https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
      tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
      curl -fsSL "$url" -o "$tmp/f.zip"
      unzip -oq "$tmp/f.zip" -d "$dir/JetBrainsMonoNerd"
      fc-cache -f >/dev/null 2>&1 || true' \
      && mark font
  fi
}

# ══════════════════════════════════════════════════════════ config payloads
CFG_DIR="$HOME/.config/bash"
BASHRC_MARK_A='# >>> bash-superpowers >>>'
BASHRC_MARK_B='# <<< bash-superpowers <<<'

backup() {
  [ -e "$1" ] || return 0
  local b="$1.bak.$(date +%Y%m%d-%H%M%S)"
  [ "$DRY_RUN" -eq 1 ] && { note "would back up $1 → $(basename "$b")"; return 0; }
  cp -a "$1" "$b" && note "backed up $(basename "$1") → $(basename "$b")"
}

write_superpowers_bash() {
  mkdir -p "$CFG_DIR"
  [ "$DRY_RUN" -eq 1 ] && { note "would write $CFG_DIR/superpowers.bash"; return 0; }
  cat > "$CFG_DIR/superpowers.bash" <<'SP_EOF'
# ~/.config/bash/superpowers.bash — managed by install-brush-superpowers.sh
# brush reads this the same way bash does (it processes .bashrc). No ble.sh
# here: brush ships its own syntax highlighting and auto-suggestions.

# ── PATH ────────────────────────────────────────────────────────────────
# Deliberately ABOVE the interactive guard: login shells that run a command
# (bash -lc '...') are not interactive but still need a correct PATH.
# The sentinel stops PATH growing every time this file is re-sourced.
if [ -z "${__SUPERPOWERS_PATH:-}" ]; then
  export __SUPERPOWERS_PATH=1

  # Homebrew. On macOS this is what puts brush (and a modern bash) ahead of
  # the system tools. Your fish config had this; a bare shell does not
  # inherit it.
  for __brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$__brew" ]; then eval "$("$__brew" shellenv)"; break; fi
  done
  unset __brew

  export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$HOME/.cargo/bin:$PATH"

  # ── Version managers ──────────────────────────────────────────────────
  # Anything you set up in fish lives in ~/.config/fish/config.fish and does
  # NOT carry over. Uncomment whichever you actually use.
  # command -v mise    >/dev/null && eval "$(mise activate bash)"
  # command -v pyenv   >/dev/null && eval "$(pyenv init -)"
  # command -v rbenv   >/dev/null && eval "$(rbenv init - bash)"
  # [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"
  # [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
  # . "$HOME/.asdf/asdf.sh" 2>/dev/null
fi

case $- in *i*) ;; *) return ;; esac      # everything below is interactive-only

# ────────────────────────────────────────────────────────────────── history
HISTSIZE=-1
HISTFILESIZE=-1
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T '
shopt -s histappend cmdhist 2>/dev/null
shopt -s autocd cdspell dirspell globstar checkwinsize 2>/dev/null
bind 'set completion-ignore-case on' 2>/dev/null
bind 'set show-all-if-ambiguous on' 2>/dev/null
bind 'set colored-stats on' 2>/dev/null

# ─────────────────────────────────────────────────────────────────── prompt
command -v starship >/dev/null && eval "$(starship init bash)"

# ────────────────────────────────────────────────────────── reverse search
command -v atuin >/dev/null && eval "$(atuin init bash)"
# want plain ↑ to stay vanilla bash?  use:  atuin init bash --disable-up-arrow

# ────────────────────────────────────────────────────────────────────  fzf
if command -v fzf >/dev/null; then
  if fzf --bash >/dev/null 2>&1; then eval "$(fzf --bash)"
  else
    [ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
    [ -f /usr/share/fzf/key-bindings.bash ] && . /usr/share/fzf/key-bindings.bash
  fi
  # atuin owns Ctrl-R; re-assert it after fzf grabs the binding
  command -v atuin >/dev/null && bind -x '"\C-r": __atuin_history' 2>/dev/null
fi

# ─────────────────────────────────────────────────────────── jump & env
command -v zoxide >/dev/null && eval "$(zoxide init bash)"
command -v direnv >/dev/null && eval "$(direnv hook bash)"

# ────────────────────────────────────────────────────────── infra aliases
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'
alias tf='terraform'
alias tg='terragrunt'
if command -v kubectl >/dev/null; then
  source <(kubectl completion bash) 2>/dev/null
  complete -o default -F __start_kubectl k 2>/dev/null
fi

# Give this shell its own kubeconfig so `kubectx` in one tab can't repoint another.
kube-isolate() {
  local tmp; tmp=$(mktemp "${TMPDIR:-/tmp}/kubeconfig.XXXXXX")
  cp "${KUBECONFIG:-$HOME/.kube/config}" "$tmp" && export KUBECONFIG="$tmp"
  echo "this shell now uses $tmp"
}

# ──────────────────────────────────────────────────────────────── attach
[ -n "${BLE_VERSION-}" ] && ble-attach
SP_EOF
  ok "wrote $CFG_DIR/superpowers.bash"
}

hook_bashrc() {
  local rc="$HOME/.bashrc"
  if [ -f "$rc" ] && grep -qF "$BASHRC_MARK_A" "$rc" 2>/dev/null; then
    skip ".bashrc already hooked"; return 0
  fi
  [ "$DRY_RUN" -eq 1 ] && { note "would append source hook to ~/.bashrc"; return 0; }
  backup "$rc"
  {
    printf '\n%s\n' "$BASHRC_MARK_A"
    printf '%s\n' '[ -f "$HOME/.config/bash/superpowers.bash" ] && source "$HOME/.config/bash/superpowers.bash"'
    printf '%s\n' "$BASHRC_MARK_B"
  } >> "$rc"
  ok "hooked ~/.bashrc"

  # macOS Terminal starts login shells, which read .bash_profile, not .bashrc
  if [ "$OS" = macos ] && ! grep -q 'bashrc' "$HOME/.bash_profile" 2>/dev/null; then
    backup "$HOME/.bash_profile"
    printf '\n[ -f ~/.bashrc ] && source ~/.bashrc\n' >> "$HOME/.bash_profile"
    ok "chained ~/.bash_profile → ~/.bashrc (macOS login shells)"
  fi
}

# ═══════════════════════════════════════════════════ starship: preferences
# Earlier version of this script hand-built the TOML in bash -- and every
# hand-typed icon was a chance to reintroduce the exact bug that bit us
# already (silently-blank symbols, locale-dependent escapes). Starship ships
# its own tested presets and generates config with `starship preset <name>
# -o <file>`, so that's what actually writes the TOML now; this script only
# orchestrates the choice and remembers it.
#
# The generated file lives at $CONFIG_LOCAL, next to this script (or next to
# a small state dir if run piped, same fallback as before) -- not buried in
# ~/.config -- so you can open it, diff it, or hand-edit it directly. A tiny
# JSON alongside it just remembers which preset you picked, so a re-run can
# ask "reuse the same one?" instead of re-asking from scratch.

resolve_choices_file() {
  [ -n "${CHOICES_FILE:-}" ] && return 0
  local dir
  dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
  if [ -n "$dir" ] && [ -w "$dir" ]; then
    CHOICES_FILE="$dir/starship-choices.json"
    CONFIG_LOCAL="$dir/starship.toml"
  else
    # Piped execution (curl | bash) has no real script path to sit next to.
    mkdir -p "$HOME/.config/bash-superpowers"
    CHOICES_FILE="$HOME/.config/bash-superpowers/starship-choices.json"
    CONFIG_LOCAL="$HOME/.config/bash-superpowers/starship.toml"
    note "running piped, so there's no script file to sit next to;"
    note "the config and its cache will live in $(dirname "$CHOICES_FILE") instead"
  fi
}

# Best-effort, not authoritative: starship's own `--list` output format isn't
# a stable contract, so if parsing it looks empty or wrong we fall back to
# this hand-maintained list rather than showing the person a broken menu.
FALLBACK_PRESETS="nerd-font-symbols plain-text-symbols pastel-powerline tokyo-night gruvbox-rainbow catppuccin-powerline bracketed-segments pure-preset jetpack no-runtime-versions no-empty-icons no-nerd-font"

list_presets() {
  local live
  live=$(starship preset --list 2>/dev/null | grep -oE '^[a-z0-9][a-z0-9-]*$')
  if [ -n "$live" ]; then printf '%s
' "$live"; else printf '%s
' $FALLBACK_PRESETS; fi
}

preset_menu() {
  local -a names=()
  local n
  while IFS= read -r n; do [ -n "$n" ] && names+=("$n"); done < <(list_presets)

  printf '
  %s0)%s none            -- Starship'"'"'s bare built-in defaults, no preset
' "$B$CYN" "$R"
  local i=1
  for n in "${names[@]}"; do
    printf '  %s%d)%s %-16s' "$B$CYN" "$i" "$R" "$n"
    (( i % 2 == 0 )) && printf '
'
    i=$((i+1))
  done
  (( (i-1) % 2 != 0 )) && printf '
'
  printf '
  preview any of them first:  starship preset <name> -o - | less
'
  printf '
  choice %s[0-%d]%s ' "$D" "${#names[@]}" "$R"

  local pick; read -r pick
  case "$pick" in
    0|'') SELECTED_PRESET=""; return 0 ;;
    *[!0-9]*) warn "not a number — using Starship's bare defaults"; SELECTED_PRESET=""; return 0 ;;
  esac
  if [ "$pick" -ge 1 ] && [ "$pick" -le "${#names[@]}" ]; then
    SELECTED_PRESET="${names[$((pick-1))]}"
  else
    warn "out of range — using Starship's bare defaults"; SELECTED_PRESET=""
  fi
}

starship_customize_flow() {
  resolve_choices_file
  mkdir -p "$HOME/.config"

  if ! have starship; then
    warn "starship isn't installed (declined earlier?) — skipping prompt customization"
    return 0
  fi

  local cached_preset=""
  if [ -f "$CHOICES_FILE" ]; then
    cached_preset=$(jq -r '.preset // ""' "$CHOICES_FILE" 2>/dev/null)
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would ask about the prompt preset here (skipped for --dry-run)"
    return 0
  fi

  local REUSE_EXISTING=0
  if [ -f "$CHOICES_FILE" ] && [ -f "$CONFIG_LOCAL" ] && [ "$CUSTOMIZE" -ne 1 ]; then
    if [ ! -t 0 ]; then
      note "no terminal to ask on; reusing $CONFIG_LOCAL as-is (preset was '${cached_preset:-none}')"
      REUSE_EXISTING=1
    else
      printf '
  Found a saved prompt config from before (%s%s%s), preset: %s%s%s
'         "$D" "$CHOICES_FILE" "$R" "$B" "${cached_preset:-none}" "$R"
      printf '  reuse it as-is? %s[Y/n]%s ' "$D" "$R"
      local a; read -r a
      case "$a" in
        [nN]*) h1 "Prompt preset"
               printf '  Pick a preset -- Starship generates the actual TOML, not me.\n'
               preset_menu ;;
        *) REUSE_EXISTING=1
           ok "reusing $(basename "$CONFIG_LOCAL") unchanged -- any hand edits you made are kept" ;;
      esac
    fi
  elif [ ! -t 0 ]; then
    note "no terminal and no cache yet; using Starship's bare defaults (edit $CHOICES_FILE and --customize later)"
    SELECTED_PRESET=""
  else
    h1 "Prompt preset"
    printf '  Pick a preset -- Starship generates the actual TOML, not me.\n'
    preset_menu
  fi

  if [ "$REUSE_EXISTING" -ne 1 ]; then
    if [ -n "$SELECTED_PRESET" ]; then
      backup "$CONFIG_LOCAL"
      run_step "generating prompt config from preset '$SELECTED_PRESET'" \
        starship preset "$SELECTED_PRESET" -o "$CONFIG_LOCAL" --force \
        || { bad "unknown preset '$SELECTED_PRESET'? see: starship preset --list"; return 1; }
    else
      backup "$CONFIG_LOCAL"
      printf '# ~/.config/starship.toml -- intentionally minimal (no preset chosen).\n# Add modules yourself, or re-run this script with --customize to pick one.\n"$schema" = '"'"'https://starship.rs/config-schema.json'"'"'\n' > "$CONFIG_LOCAL"
      ok "wrote a minimal config (no preset)"
    fi

    cat > "$CHOICES_FILE" <<JSON_EOF
{
  "preset": "$SELECTED_PRESET"
}
JSON_EOF
    ok "saved preference → $CHOICES_FILE"
  fi

  backup "$HOME/.config/starship.toml"
  cp "$CONFIG_LOCAL" "$HOME/.config/starship.toml"
  ok "installed $(basename "$CONFIG_LOCAL") → ~/.config/starship.toml"
  note "edit $CONFIG_LOCAL directly any time -- it's a plain file next to this script."
  note "a plain re-run offers to reuse it as-is; only --customize regenerates it from a preset."
}

write_starship_toml() { starship_customize_flow; }

write_gh_prompt() {
  local f="$HOME/.local/bin/gh-prompt"
  mkdir -p "$HOME/.local/bin"
  [ "$DRY_RUN" -eq 1 ] && { note "would write $f"; return 0; }
  cat > "$f" <<'GH_EOF'
#!/usr/bin/env bash
# gh-prompt — GitHub PR + CI state, served from cache so the prompt never blocks.
set -uo pipefail
TTL=${GH_PROMPT_TTL:-90}
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gh-prompt"

command -v gh >/dev/null 2>&1 || exit 0
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0

key=$(printf '%s@%s' "$repo_root" "$branch" | cksum | cut -d' ' -f1)
cache="$CACHE_DIR/$key"
mkdir -p "$CACHE_DIR"

refresh() {
  local out
  out=$(gh pr view --json number,state,isDraft,reviewDecision,statusCheckRollup 2>/dev/null) \
    || { : > "$cache"; return; }
  printf '%s' "$out" | jq -r '
    ([.statusCheckRollup[]? | (.conclusion // .state // "")]) as $c
    | (if   ($c | length) == 0                                     then ""
       elif ($c | index("FAILURE")) or ($c | index("ERROR"))       then "✗"
       elif ($c | index("PENDING")) or ($c | index("IN_PROGRESS")) then "●"
       else "✓" end) as $ci
    | (if   .isDraft                                then "draft"
       elif .reviewDecision == "APPROVED"           then "✔"
       elif .reviewDecision == "CHANGES_REQUESTED"  then "✎"
       else "" end) as $rv
    | [ "#\(.number)", $ci, $rv ] | map(select(. != "")) | join(" ")
  ' > "$cache" 2>/dev/null || : > "$cache"
}

[ -s "$cache" ] && cat "$cache"

now=$(date +%s)
mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
if [ $(( now - mtime )) -gt "$TTL" ]; then
  lock="$cache.lock"
  if mkdir "$lock" 2>/dev/null; then
    ( trap 'rmdir "$lock" 2>/dev/null' EXIT; refresh ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi
exit 0
GH_EOF
  chmod 755 "$f"
  ok "wrote ~/.local/bin/gh-prompt"
}

write_ghacct_prompt() {
  local f="$HOME/.local/bin/ghacct-prompt"
  mkdir -p "$HOME/.local/bin"
  [ "$DRY_RUN" -eq 1 ] && { note "would write $f"; return 0; }
  cat > "$f" <<'GHACCT_EOF'
#!/usr/bin/env bash
# ghacct-prompt — prints the ghacct alias (which GitHub account/workspace)
# governs the current directory, by matching $PWD against each account's
# registered `dir=` in ~/.config/ghacct/accounts/*.conf (same registry
# ghacct.sh itself manages). Longest matching dir wins, so nested account
# folders (e.g. personal inside a broader work tree) resolve correctly.
set -uo pipefail

ACCT_DIR="${GHACCT_HOME:-$HOME/.config/ghacct}/accounts"
[ -d "$ACCT_DIR" ] || exit 0

cwd=$(pwd -P) || exit 0
best_alias=""
best_len=-1

for f in "$ACCT_DIR"/*.conf; do
  [ -f "$f" ] || continue
  alias_="" dir=""
  while IFS='=' read -r k v; do
    case "$k" in
      alias) alias_="$v" ;;
      dir)   dir="$v" ;;
    esac
  done < "$f"
  [ -n "$dir" ] || continue
  dir="${dir/#\~/$HOME}"
  case "$cwd" in
    "$dir"|"$dir"/*)
      len=${#dir}
      [ "$len" -gt "$best_len" ] && { best_len=$len; best_alias="$alias_"; }
      ;;
  esac
done

[ -n "$best_alias" ] && printf '%s' "$best_alias"
GHACCT_EOF
  chmod 755 "$f"
  ok "wrote ~/.local/bin/ghacct-prompt"
}

import_fish_history() {
  have atuin || return 0
  [ -f "$HOME/.local/share/fish/fish_history" ] || return 0
  confirm "Import your fish history into atuin? ${D}(reads ~/.local/share/fish)${R}" \
    || { skip "history import — declined"; return 0; }
  run_step "importing shell history into atuin" atuin import auto
}

# ═════════════════════════════════════════════════════════════ shell chooser
choose_default_shell() {
  h1 "Default login shell"

  local me; me="${USER:-$(id -un 2>/dev/null)}"
  local current; current=$(getent passwd "$me" 2>/dev/null | cut -d: -f7)
  [ -z "$current" ] && current=$(dscl . -read "/Users/$me" UserShell 2>/dev/null | awk '{print $2}')
  [ -z "$current" ] && current="${SHELL:-unknown}"
  printf '  current: %s%s%s\n\n' "$B$WHT" "$current" "$R"

  local cands=() labels=()
  local b
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
    if [ -x "$b" ]; then
      local ver; ver=$("$b" --version 2>/dev/null | head -n1 | sed -n 's/.*version \([0-9.]*\).*/\1/p')
      [ -z "$ver" ] && ver="?"
      cands+=("$b"); labels+=("bash $ver  ${D}$b${R}")
    fi
  done
  for b in "$(command -v zsh 2>/dev/null)" "$(command -v fish 2>/dev/null)"; do
    [ -n "$b" ] && [ -x "$b" ] && { cands+=("$b"); labels+=("$(basename "$b")  ${D}$b${R}"); }
  done

  if [ -n "$SET_SHELL" ]; then set_shell "$SET_SHELL"; return; fi
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    note "non-interactive: leaving your login shell unchanged"
    note "change it later with:  chsh -s \"\$(command -v bash)\""
    return
  fi

  local i=1 n=${#cands[@]}
  while [ "$i" -le "$n" ]; do
    local star=""
    [ "${cands[$((i-1))]}" = "$current" ] && star=" ${GRN}(current)${R}"
    printf '    %s%d%s) %b%b\n' "$B$CYN" "$i" "$R" "${labels[$((i-1))]}" "$star"
    i=$((i+1))
  done
  printf '    %s0%s) %sleave it alone%s\n\n' "$B$CYN" "$R" "$GRY" "$R"

  local pick; printf '  %s?%s choose a default shell %s[0-%d]%s ' "$YEL" "$R" "$D" "$n" "$R"
  read -r pick
  case "$pick" in
    ''|0) note "login shell unchanged"; return ;;
    *[!0-9]*) warn "not a number — login shell unchanged"; return ;;
  esac
  [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ] || { warn "out of range — unchanged"; return; }
  set_shell "${cands[$((pick-1))]}"
}

set_shell() {
  local target=$1
  [ -x "$target" ] || { bad "$target is not executable"; return 1; }
  if [ "$DRY_RUN" -eq 1 ]; then note "would chsh to $target"; return 0; fi

  if ! grep -qxF "$target" /etc/shells 2>/dev/null; then
    note "$target is not listed in /etc/shells"
    if confirm "Add it to /etc/shells? (needed before chsh will accept it)"; then
      printf '%s\n' "$target" | $SUDO tee -a /etc/shells >/dev/null \
        && ok "added $target to /etc/shells" \
        || { bad "could not write /etc/shells"; return 1; }
    else
      warn "skipped; chsh will likely refuse this shell"
    fi
  fi

  if chsh -s "$target" 2>>"$LOG"; then
    ok "default login shell set to $target"
    note "takes effect on your next login — open a fresh terminal to verify"
  else
    bad "chsh failed (see $LOG)"
    note "try manually:  chsh -s $target"
  fi
}

# ════════════════════════════════════════════════════════════ verification
# Independent of what the install steps *claimed* — this checks reality.
check() {   # check <label> <test-cmd...>
  if "${@:2}" >/dev/null 2>&1; then
    printf '  %s✔%s %s\n' "$GRN" "$R" "$1"
    log "VERIFY ok      $1"
  else
    printf '  %s✘%s %-34s %s%s%s\n' "$RED" "$R" "$1" "$D" "${VERIFY_HINT:-}" "$R"
    log "VERIFY MISSING $1${VERIFY_HINT:+  — hint: $VERIFY_HINT}"
    VERIFY_BAD=$((VERIFY_BAD + 1))
    VERIFY_MISSING="${VERIFY_MISSING}$1
"
  fi
  VERIFY_HINT=""
}

# The question is not "which brush is on PATH right now" — it's whether your
# NEXT login shell actually resolves to it, since that's what decides whether
# typing `brush` (or setting it as your default shell) gets you the one you
# just installed rather than a stale one earlier in PATH.
verify_brush() {
  local resolved=""
  if have brush; then
    resolved=$(bash -lc 'command -v brush' 2>/dev/null | tail -n1)
    if [ -n "$resolved" ] && [ -x "$resolved" ]; then
      local ver; ver=$("$resolved" --version 2>/dev/null | head -n1)
      printf '  %s✔%s next login shell resolves brush → %s %s(%s)%s\n' \
        "$GRN" "$R" "$resolved" "$D" "${ver:-unknown version}" "$R"
      return 0
    fi
  fi
  printf '  %s✘%s %-34s %sbrush is on PATH now but a fresh login shell can'"'"'t find it%s\n' \
    "$RED" "$R" "login shell finds brush" "$D" "$R"
  log "VERIFY MISSING login shell can't resolve brush"
  VERIFY_MISSING="${VERIFY_MISSING}login shell can't resolve brush (check PATH / brew shellenv)
"
  VERIFY_BAD=$((VERIFY_BAD + 1))
  return 1
}

# The font FILE being on disk says nothing about whether your terminal
# APPLICATION has been told to draw with it. That second step is manual —
# no script can reach into a GUI app's preferences — so make it unmissable.
glyph_check() {
  [ -t 1 ] || return 0
  printf '\n  %sdo these render as icons, or as boxes/question marks?%s\n\n' "$D" "$R"
  # Literal UTF-8 bytes, not \u escapes: bash only resolves \uHHHH under a
  # UTF-8 locale, and silently prints it back as literal text otherwise —
  # which looks exactly like a font problem but isn't one.
  printf '      ☸         󱁢      \n\n'
  printf '  %sIf they look like boxes:%s the font file is installed but your\n' "$B" "$R"
  printf '  %sterminal app%s is not drawing with it yet — a settings change, not a bug.\n\n' "$B" "$R"

  local app="${TERM_PROGRAM:-unknown}"
  case "$app" in
    iTerm.app)
      printf '  %siTerm2:%s Settings → Profiles → Text → Font → set to\n' "$B" "$R"
      printf '          %sJetBrainsMono Nerd Font%s (or any "...Nerd Font" variant)\n' "$CYN" "$R" ;;
    Apple_Terminal)
      printf '  %sTerminal.app:%s Settings → Profiles → Font → Change...\n' "$B" "$R"
      printf '                choose %sJetBrainsMono Nerd Font%s\n' "$CYN" "$R" ;;
    vscode)
      printf '  %sVS Code integrated terminal:%s add to settings.json:\n' "$B" "$R"
      printf '      %s"terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"%s\n' "$CYN" "$R" ;;
    WarpTerminal)
      printf '  %sWarp:%s Settings → Appearance → Text → Font →\n' "$B" "$R"
      printf '        %sJetBrainsMono Nerd Font%s\n' "$CYN" "$R" ;;
    *)
      printf '  %sfont not found automatically for terminal: %s%s\n' "$B" "$app" "$R"
      printf '  Look for Preferences/Settings → Profile/Appearance → Font,\n'
      printf '  and pick %sJetBrainsMono Nerd Font%s. Common apps:\n' "$CYN" "$R"
      printf '    kitty:   font_family JetBrainsMono Nerd Font   (in kitty.conf, then ctrl+shift+F5)\n'
      printf '    Alacritty: font.normal.family: "JetBrainsMono Nerd Font"  (alacritty.toml)\n'
      printf '    GNOME Terminal / Windows Terminal: Profile → Text/Appearance → Font\n' ;;
  esac
  printf '\n  After changing it, %sclose and reopen the terminal window%s (a new tab is not enough).\n' "$B" "$R"
}

verify() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  h1 "Verification"
  VERIFY_BAD=0; VERIFY_HINT=""; VERIFY_MISSING=""

  check "brush installed"         have brush
  check "starship on PATH"        command -v starship
  check "atuin on PATH"           command -v atuin
  check "fzf on PATH"             command -v fzf
  check "zoxide on PATH"          command -v zoxide
  check "direnv on PATH"          command -v direnv
  check "gh on PATH"              command -v gh
  check "kubectx on PATH"         command -v kubectx
  check "jq on PATH"              command -v jq
  check "superpowers.bash written" test -f "$CFG_DIR/superpowers.bash"
  check "starship.toml written"    test -f "$HOME/.config/starship.toml"
  check "preset choice cached"     test -f "$CHOICES_FILE"
  check "local config present"     test -f "$CONFIG_LOCAL"
  check "preferences cache saved"  test -f "$CHOICES_FILE"
  check "gh-prompt executable"     test -x "$HOME/.local/bin/gh-prompt"
  check "ghacct-prompt executable" test -x "$HOME/.local/bin/ghacct-prompt"
  check ".bashrc hooked"           grep -qF "$BASHRC_MARK_A" "$HOME/.bashrc"

  VERIFY_HINT="brew install --cask font-jetbrains-mono-nerd-font"
  if [ "$SKIP_FONT" -eq 0 ]; then
    if [ "$OS" = macos ]; then
      check "Nerd Font FILE present" bash -c 'ls ~/Library/Fonts /Library/Fonts 2>/dev/null | grep -qi jetbrainsmono'
    else
      check "Nerd Font FILE present" bash -c 'fc-list | grep -qi "JetBrainsMono Nerd"'
    fi
    glyph_check
  fi

  verify_brush

  printf '\n'
  if [ "$VERIFY_BAD" -eq 0 ]; then
    ok "every component is in place"
  else
    warn "$VERIFY_BAD component(s) missing:"
    printf '%s' "$VERIFY_MISSING" | while IFS= read -r line; do
      [ -n "$line" ] && printf '      %s·%s %s\n' "$RED" "$R" "$line"
    done
    note "re-run with --doctor any time to re-check"
  fi
}

# ═══════════════════════════════════════════════════════════════ preflight
preflight() {
  h1 "Preflight"
  printf '  %-14s %s\n' "platform"  "$DISTRO ${D}($(uname -m))${R}"
  printf '  %-14s %s\n' "pkg mgr"   "${PKG}"
  printf '  %-14s %s\n' "bash"      "${BASH_VERSION%%(*}"
  printf '  %-14s %s\n' "log"       "${D}$LOG${R}"
  [ "$DRY_RUN" -eq 1 ] && printf '  %-14s %s\n' "mode" "${YEL}dry run — nothing will be modified${R}"
  printf '\n'

  local t
  for t in git curl jq unzip make brush starship atuin fzf zoxide direnv gh kubectx; do
    if have "$t"; then
      local v; v=$("$t" --version 2>/dev/null | head -n1 | cut -c1-38)
      printf '  %s✔%s %-11s %s%s%s\n' "$GRN" "$R" "$t" "$D" "${v:-present}" "$R"
    else
      printf '  %s·%s %-11s %s%s%s\n' "$YEL" "$R" "$t" "$YEL" "candidate" "$R"
      [ "$CONFIG_ONLY" -eq 1 ] || plan_add "$t"
    fi
  done
  if [ "$SKIP_FONT" -eq 0 ] && [ "$CONFIG_ONLY" -eq 0 ] \
     && ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    printf '  %s·%s %-11s %s%s%s\n' "$YEL" "$R" "font" "$YEL" "candidate" "$R"
    plan_add font
  fi
  if have kubectl; then
    printf '  %s✔%s %-11s %s%s%s\n' "$GRN" "$R" "kubectl" "$D" "present, left alone" "$R"
  fi
  printf '\n'
  note "\"candidate\" is not a decision — you approve or reject the list next."
  note "kubectl / terraform / pulumi are never installed by this script;"
  note "the prompt just reads them if you already have them."
}

# ════════════════════════════════════════════════════════════════════ main
main() {
  banner
  detect_platform
  resolve_choices_file

  if [ "$DOCTOR" -eq 1 ]; then
    preflight
    verify
    printf '\n  %sfull log:%s %s\n\n' "$D" "$R" "$LOG"
    [ "${VERIFY_BAD:-0}" -eq 0 ] && exit 0 || exit 1
  fi

  preflight

  consent_gate

  if [ "$CONFIG_ONLY" -eq 0 ] && [ "$APPROVE_MODE" != none ]; then
    if [ "$PKG" = none ] && [ "$OS" = macos ]; then install_homebrew; fi
    if [ "$PKG" = none ]; then
      warn "no supported package manager found; only vendor scripts will run"
    fi
    [ "$PKG" != brew ] && [ "$(id -u)" -ne 0 ] && ensure_sudo

    h1 "Base tools"
    BASE_TOOLS="git curl jq unzip make"
    for t in $BASE_TOOLS; do
      have "$t" && { skip "$t already present"; continue; }
      want "$t" || continue
      pkg_install "$t" >/dev/null 2>&1 && ok "installing $t" || warn "could not install $t"
    done

    h1 "The shell and interactive layer"
    install_brush
    install_starship
    install_atuin
    if have fzf; then skip "fzf already present"
    elif want fzf; then pkg_install fzf && mark fzf; fi
    install_zoxide
    if have direnv; then skip "direnv already present"
    elif want direnv; then pkg_install direnv && mark direnv; fi

    h1 "Developer context"
    install_gh
    install_kubectx
    install_font
  else
    h1 "Packages"
    skip "installing nothing — you asked for configuration only"
  fi

  h1 "Configuration"
  write_superpowers_bash
  write_starship_toml
  write_gh_prompt
  write_ghacct_prompt
  hook_bashrc
  import_fish_history

  choose_default_shell

  # ───────────────────────────────────────────────────────────── summary
  verify

  h1 "Summary"
  [ -n "$INSTALLED" ] && printf '  %sinstalled%s %s\n' "$GRN" "$R" "$INSTALLED"
  [ -n "$FELLBACK" ] && printf '  %svendor script used for%s %s\n' "$BLU" "$R" "$FELLBACK"
  if [ "$FAILURES" -eq 0 ] && [ "${VERIFY_BAD:-0}" -gt 0 ]; then
    printf '\n  %s installed, with %d gap(s) %s  %ssee Verification above%s\n' \
      "$BG_ERR" "$VERIFY_BAD" "$R" "$D" "$R"
  elif [ "$FAILURES" -gt 0 ]; then
    printf '\n  %s %d step(s) failed %s\n\n' "$BG_ERR" "$FAILURES" "$R"
    printf '%s' "$FAILED_STEPS" | while IFS= read -r line; do
      [ -n "$line" ] && printf '    %s✘%s %s\n' "$RED" "$R" "$line"
    done
    printf '\n  full stderr for each:\n'
    printf '    %sgrep -A20 "^── %s" %s%s\n' "$D" "<step name>" "$LOG" "$R"
    printf '    %sgrep "^FAIL" %s%s\n' "$D" "$LOG" "$R"
  else
    printf '\n  %s all good %s\n' "$BG_OK" "$R"
  fi
  [ "$WARNINGS" -gt 0 ] && printf '  %s%d warning(s)%s — worth a glance above\n' "$YEL" "$WARNINGS" "$R"

  printf '\n%s  next steps%s\n' "$B$WHT" "$R"
  printf '   %s1.%s Set your terminal font to %sJetBrainsMono Nerd Font%s (skip if you chose plain icons).\n' "$CYN" "$R" "$B" "$R"
  printf '   %s2.%s Try it right now without switching your login shell:  %sbrush%s\n' "$CYN" "$R" "$B" "$R"
  printf '   %s3.%s %sgh auth login%s   — unlocks the PR segment in the prompt.\n' "$CYN" "$R" "$B" "$R"
  printf '   %s4.%s Change your mind on layout/icons/cloud later:  %s--customize%s (edits %s)\n' "$CYN" "$R" "$B" "$R" "$CHOICES_FILE"
  printf '   %s5.%s %sstarship timings%s — if the prompt ever feels slow, this names the culprit.\n' "$CYN" "$R" "$B" "$R"
  printf '   %s6.%s Your fish config still lives at ~/.config/fish — nothing was deleted.\n' "$CYN" "$R"
  printf '\n   %sTip:%s brush'"'"'s auto-suggestions accept with %s→%s; %sCtrl-R%s is now atuin;\n' \
    "$D" "$R" "$B" "$R" "$B" "$R"
  printf '        edit the config file next to this script any time; it'"'"'s plain TOML now.\n\n'

  [ -n "${SUDO_KEEPALIVE:-}" ] && kill "$SUDO_KEEPALIVE" 2>/dev/null
  return 0
}

main "$@"
