#!/usr/bin/env bash
# ghacct - multi GitHub account manager
#
# Manages, per account:
#   * an ed25519 SSH key pair            -> ~/.ssh/id_ed25519_<alias>
#   * a Host alias block                 -> ~/.ssh/config      (github.com-<alias>)
#   * a git identity profile             -> ~/.gitconfig-<alias>
#   * a conditional include              -> ~/.gitconfig       (includeIf gitdir:...)
#   * a registry entry                   -> ~/.config/ghacct/accounts/<alias>.conf
#
# Every block written into shared files is fenced with markers so it can be
# updated or removed cleanly:
#   # >>> ghacct:<alias> >>>   ...   # <<< ghacct:<alias> <<<
#
# Usage:
#   ./ghacct.sh                 # interactive menu
#   ./ghacct.sh list
#   ./ghacct.sh add
#   ./ghacct.sh show    <alias>
#   ./ghacct.sh edit    <alias>
#   ./ghacct.sh rm      <alias>
#   ./ghacct.sh test    <alias>
#   ./ghacct.sh key     <alias>            # print / copy public key
#   ./ghacct.sh clone   <alias> <repo>     # repo = owner/name or full URL
#   ./ghacct.sh apply   <alias> [repo-dir] # bind an existing repo to an account
#   ./ghacct.sh doctor  [alias]
#   ./ghacct.sh notes                      # Zed / Copilot cheatsheet

set -uo pipefail

# ---------------------------------------------------------------- constants --
CFG_DIR="${GHACCT_HOME:-$HOME/.config/ghacct}"
ACCT_DIR="$CFG_DIR/accounts"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
GIT_CONFIG="$HOME/.gitconfig"
IS_MAC=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MAC=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[36m'
else
  C_RESET=""; C_DIM=""; C_B=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_RESET" "$*"; }
err()  { printf '%s✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hdr()  { printf '\n%s%s%s\n' "$C_B" "$*" "$C_RESET"; }

# ------------------------------------------------------------------ helpers --
ensure_dirs() {
  mkdir -p "$ACCT_DIR"
  mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
  [[ -f "$SSH_CONFIG" ]] || { : > "$SSH_CONFIG"; }
  chmod 600 "$SSH_CONFIG"
  [[ -f "$GIT_CONFIG" ]] || { : > "$GIT_CONFIG"; }
}

backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp "$f" "${f}.ghacct.bak"
}

expand_path() { local p="$1"; printf '%s' "${p/#\~/$HOME}"; }

tildify() {
  local p="$1"
  case "$p" in
    "$HOME"/*|"$HOME") printf '~%s' "${p#"$HOME"}" ;;
    *) printf '%s' "$p" ;;
  esac
}

valid_alias() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

account_file() { printf '%s/%s.conf' "$ACCT_DIR" "$1"; }
account_exists() { [[ -f "$(account_file "$1")" ]]; }

aliases() {
  [[ -d "$ACCT_DIR" ]] || return 0
  local f
  for f in "$ACCT_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    basename "$f" .conf
  done
}

count_accounts() { aliases | grep -c . ; }

prompt() { # prompt VARNAME "Question" ["default"]
  local __v="$1" q="$2" def="${3:-}" ans=""
  if [[ -n "$def" ]]; then
    read -r -p "  $q [$def]: " ans
  else
    read -r -p "  $q: " ans
  fi
  ans="${ans:-$def}"
  printf -v "$__v" '%s' "$ans"
}

confirm() { # confirm "Question" [y|n]
  local q="$1" def="${2:-n}" ans hint="y/N"
  [[ "$def" == "y" ]] && hint="Y/n"
  read -r -p "  $q ($hint): " ans
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

copy_clip() { # read stdin -> clipboard, return 0 if copied
  if   command -v pbcopy   >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy  >/dev/null 2>&1; then wl-copy
  elif command -v xclip    >/dev/null 2>&1; then xclip -selection clipboard
  elif command -v clip.exe >/dev/null 2>&1; then clip.exe
  else cat >/dev/null; return 1
  fi
}

# --------------------------------------------------------- registry (CRUD) --
# Fields: alias name email ghuser dir key host rewrite
save_account() {
  local f; f="$(account_file "$A_ALIAS")"
  {
    printf 'alias=%s\n'   "$A_ALIAS"
    printf 'name=%s\n'    "$A_NAME"
    printf 'email=%s\n'   "$A_EMAIL"
    printf 'ghuser=%s\n'  "$A_GHUSER"
    printf 'dir=%s\n'     "$A_DIR"
    printf 'key=%s\n'     "$A_KEY"
    printf 'host=%s\n'    "$A_HOST"
    printf 'rewrite=%s\n' "$A_REWRITE"
  } > "$f"
  chmod 600 "$f"
}

load_account() {
  local a="$1" f k v
  f="$(account_file "$a")"
  [[ -f "$f" ]] || return 1
  A_ALIAS=""; A_NAME=""; A_EMAIL=""; A_GHUSER=""; A_DIR=""; A_KEY=""; A_HOST=""; A_REWRITE="yes"
  while IFS='=' read -r k v; do
    case "$k" in
      alias)   A_ALIAS="$v" ;;
      name)    A_NAME="$v" ;;
      email)   A_EMAIL="$v" ;;
      ghuser)  A_GHUSER="$v" ;;
      dir)     A_DIR="$v" ;;
      key)     A_KEY="$v" ;;
      host)    A_HOST="$v" ;;
      rewrite) A_REWRITE="$v" ;;
    esac
  done < "$f"
  [[ -n "$A_ALIAS" ]]
}

# -------------------------------------------------- fenced block management --
remove_block() { # remove_block FILE ALIAS
  local file="$1" al="$2" tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)" || return 1
  awk -v s="# >>> ghacct:$al >>>" -v e="# <<< ghacct:$al <<<" '
    $0 == s { skip = 1 }
    skip != 1 { print }
    $0 == e { skip = 0 }
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

append_block() { # append_block FILE ALIAS  (body on stdin)
  local file="$1" al="$2"
  {
    printf '\n# >>> ghacct:%s >>>\n' "$al"
    cat
    printf '# <<< ghacct:%s <<<\n' "$al"
  } >> "$file"
}

write_ssh_block() {
  backup "$SSH_CONFIG"
  remove_block "$SSH_CONFIG" "$A_ALIAS"
  {
    printf 'Host %s\n' "$A_HOST"
    printf '  HostName github.com\n'
    printf '  User git\n'
    printf '  IdentityFile %s\n' "$(tildify "$A_KEY")"
    printf '  IdentitiesOnly yes\n'
    printf '  AddKeysToAgent yes\n'
    [[ $IS_MAC -eq 1 ]] && printf '  UseKeychain yes\n'
  } | append_block "$SSH_CONFIG" "$A_ALIAS"
  chmod 600 "$SSH_CONFIG"
  ok "ssh config updated  ($A_HOST -> $(tildify "$A_KEY"))"
}

write_git_profile() {
  local prof="$HOME/.gitconfig-$A_ALIAS"
  {
    printf '# Managed by ghacct - account "%s"\n' "$A_ALIAS"
    printf '[user]\n'
    printf '\tname = %s\n'  "$A_NAME"
    printf '\temail = %s\n' "$A_EMAIL"
    printf '[core]\n'
    printf '\tsshCommand = ssh -i %s -o IdentitiesOnly=yes\n' "$(tildify "$A_KEY")"
    if [[ "$A_REWRITE" == "yes" ]]; then
      printf '[url "git@%s:"]\n' "$A_HOST"
      printf '\tinsteadOf = git@github.com:\n'
      printf '[url "git@%s:"]\n' "$A_HOST"
      printf '\tinsteadOf = https://github.com/\n'
    fi
  } > "$prof"
  ok "identity profile written  ($(tildify "$prof"))"
}

write_git_include() {
  local dir; dir="$(tildify "$A_DIR")"
  [[ "$dir" == */ ]] || dir="$dir/"
  backup "$GIT_CONFIG"
  remove_block "$GIT_CONFIG" "$A_ALIAS"
  {
    printf '[includeIf "gitdir:%s"]\n' "$dir"
    printf '\tpath = %s\n' "$(tildify "$HOME/.gitconfig-$A_ALIAS")"
  } | append_block "$GIT_CONFIG" "$A_ALIAS"
  ok "conditional include added  (gitdir:$dir)"
}

apply_account_files() {
  mkdir -p "$A_DIR"
  write_ssh_block
  write_git_profile
  write_git_include
}

# ------------------------------------------------------------------- create --
gen_key() {
  local key="$A_KEY"
  if [[ -f "$key" ]]; then
    warn "key already exists, reusing: $(tildify "$key")"
    return 0
  fi
  mkdir -p "$(dirname "$key")"
  if confirm "Protect the key with a passphrase?" n; then
    ssh-keygen -t ed25519 -C "$A_EMAIL" -f "$key" || return 1
  else
    ssh-keygen -t ed25519 -C "$A_EMAIL" -f "$key" -N "" -q || return 1
  fi
  chmod 600 "$key"; chmod 644 "$key.pub"
  ok "key generated: $(tildify "$key")"
  if command -v ssh-add >/dev/null 2>&1; then
    if [[ $IS_MAC -eq 1 ]]; then
      ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add -K "$key" 2>/dev/null || ssh-add "$key" 2>/dev/null
    else
      ssh-add "$key" 2>/dev/null
    fi
  fi
}

cmd_add() {
  ensure_dirs
  hdr "Add a GitHub account"
  local al
  while :; do
    prompt al "Short alias (work, personal, client-x)"
    if ! valid_alias "$al"; then err "Use letters, digits, dot, dash, underscore."; continue; fi
    if account_exists "$al"; then err "Alias '$al' already exists. Use 'edit' instead."; continue; fi
    break
  done
  A_ALIAS="$al"
  prompt A_GHUSER "GitHub username"
  prompt A_NAME   "Commit author name" "$A_GHUSER"
  while :; do
    prompt A_EMAIL "Commit email"
    [[ "$A_EMAIL" == *@*.* ]] && break
    err "That does not look like an email address."
  done
  local d
  prompt d "Workspace folder for this account" "~/Development/$A_ALIAS"
  A_DIR="$(expand_path "$d")"
  local k
  prompt k "SSH key path" "~/.ssh/id_ed25519_$A_ALIAS"
  A_KEY="$(expand_path "$k")"
  A_HOST="github.com-$A_ALIAS"
  if confirm "Auto-rewrite plain github.com URLs inside that folder?" y; then
    A_REWRITE="yes"
  else
    A_REWRITE="no"
  fi

  hdr "Summary"
  printf '  alias      %s\n  user       %s\n  name       %s\n  email      %s\n  folder     %s\n  key        %s\n  ssh host   %s\n' \
    "$A_ALIAS" "$A_GHUSER" "$A_NAME" "$A_EMAIL" "$(tildify "$A_DIR")" "$(tildify "$A_KEY")" "$A_HOST"
  echo
  confirm "Create it?" y || { warn "Cancelled."; return 1; }

  gen_key || die "key generation failed"
  apply_account_files
  save_account
  ok "Account '$A_ALIAS' created."
  hdr "Next step - register the public key on GitHub"
  show_pubkey "$A_ALIAS"
  info "  Paste it at ${C_BLU}https://github.com/settings/ssh/new${C_RESET} while logged in as ${C_B}$A_GHUSER${C_RESET}"
  info "  Then run: ${C_B}$(basename "$0") test $A_ALIAS${C_RESET}"
}

# --------------------------------------------------------------------- read --
cmd_list() {
  ensure_dirs
  local n; n="$(count_accounts)"
  if [[ "$n" -eq 0 ]]; then
    warn "No accounts yet. Run 'add' to create one."
    return 0
  fi
  hdr "Configured accounts ($n)"
  printf '  %-12s %-18s %-28s %s\n' "ALIAS" "GITHUB USER" "EMAIL" "FOLDER"
  printf '  %-12s %-18s %-28s %s\n' "-----" "-----------" "-----" "------"
  local a
  while read -r a; do
    load_account "$a" || continue
    printf '  %-12s %-18s %-28s %s\n' "$A_ALIAS" "$A_GHUSER" "$A_EMAIL" "$(tildify "$A_DIR")"
  done < <(aliases)
  echo
}

cmd_show() {
  local a="${1:-}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  hdr "Account: $A_ALIAS"
  printf '  GitHub user   %s\n'  "$A_GHUSER"
  printf '  Commit name   %s\n'  "$A_NAME"
  printf '  Commit email  %s\n'  "$A_EMAIL"
  printf '  Workspace     %s\n'  "$(tildify "$A_DIR")"
  printf '  SSH key       %s\n'  "$(tildify "$A_KEY")"
  printf '  SSH host      %s\n'  "$A_HOST"
  printf '  URL rewrite   %s\n'  "$A_REWRITE"
  printf '  Profile file  %s\n'  "$(tildify "$HOME/.gitconfig-$A_ALIAS")"
  hdr "Clone syntax"
  printf '  git clone git@%s:%s/REPO.git\n' "$A_HOST" "$A_GHUSER"
  echo
}

show_pubkey() {
  local a="$1"
  load_account "$a" || die "No such account: $a"
  local pub="$A_KEY.pub"
  [[ -f "$pub" ]] || die "Public key missing: $(tildify "$pub")"
  echo
  printf '%s%s%s\n' "$C_DIM" "$(cat "$pub")" "$C_RESET"
  echo
  if copy_clip < "$pub"; then ok "Copied to clipboard."; else warn "No clipboard tool found - copy the line above."; fi
}

# ------------------------------------------------------------------- update --
cmd_edit() {
  local a="${1:-}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  hdr "Editing '$A_ALIAS' (Enter keeps the current value)"
  local d
  prompt A_GHUSER "GitHub username" "$A_GHUSER"
  prompt A_NAME   "Commit author name" "$A_NAME"
  prompt A_EMAIL  "Commit email" "$A_EMAIL"
  prompt d        "Workspace folder" "$(tildify "$A_DIR")"
  A_DIR="$(expand_path "$d")"
  prompt d        "SSH key path" "$(tildify "$A_KEY")"
  A_KEY="$(expand_path "$d")"
  prompt A_REWRITE "Auto-rewrite github.com URLs (yes/no)" "$A_REWRITE"
  echo
  confirm "Save changes and rewrite config blocks?" y || { warn "Cancelled."; return 1; }
  [[ -f "$A_KEY" ]] || { warn "Key not found at new path."; gen_key; }
  apply_account_files
  save_account
  ok "Account '$A_ALIAS' updated."
}

# ------------------------------------------------------------------- delete --
cmd_rm() {
  local a="${1:-}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  hdr "Delete account '$A_ALIAS'"
  info "  Removes: ssh config block, gitconfig include, $(tildify "$HOME/.gitconfig-$A_ALIAS"), registry entry."
  confirm "Proceed?" n || { warn "Cancelled."; return 1; }
  backup "$SSH_CONFIG"; remove_block "$SSH_CONFIG" "$A_ALIAS"
  backup "$GIT_CONFIG"; remove_block "$GIT_CONFIG" "$A_ALIAS"
  rm -f "$HOME/.gitconfig-$A_ALIAS"
  rm -f "$(account_file "$A_ALIAS")"
  ok "Config removed."
  if [[ -f "$A_KEY" ]] && confirm "Also delete the SSH key pair $(tildify "$A_KEY")?" n; then
    ssh-add -d "$A_KEY" >/dev/null 2>&1
    rm -f "$A_KEY" "$A_KEY.pub"
    ok "Key deleted."
  else
    warn "Key kept at $(tildify "$A_KEY")"
  fi
  warn "Repos already cloned with host '$A_HOST' will stop resolving - re-point their remotes."
}

# ------------------------------------------------------------------ actions --
cmd_test() {
  local a="${1:-}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  hdr "Testing $A_HOST"
  local out
  out="$(ssh -T -o StrictHostKeyChecking=accept-new "git@$A_HOST" 2>&1)"
  if printf '%s' "$out" | grep -q "successfully authenticated"; then
    local who; who="$(printf '%s' "$out" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')"
    ok "Authenticated as ${C_B}${who:-unknown}${C_RESET}"
    if [[ -n "$who" && -n "$A_GHUSER" && "$who" != "$A_GHUSER" ]]; then
      warn "Expected '$A_GHUSER' - this key belongs to a different account."
    fi
  else
    err "Authentication failed."
    printf '%s\n' "$out" | sed 's/^/    /'
    info "  Is the public key added to https://github.com/settings/keys for $A_GHUSER?"
    return 1
  fi
}

cmd_clone() {
  local a="${1:-}" repo="${2:-}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  [[ -n "$repo" ]] || prompt repo "Repo (owner/name or full URL)"
  [[ -n "$repo" ]] || die "No repo given."
  # normalise any input form to the aliased SSH URL
  local path
  case "$repo" in
    git@github.com:*)        path="${repo#git@github.com:}" ;;
    git@"$A_HOST":*)         path="${repo#git@"$A_HOST":}" ;;
    https://github.com/*)    path="${repo#https://github.com/}" ;;
    *) path="$repo" ;;
  esac
  path="${path%.git}"
  [[ "$path" == */* ]] || path="$A_GHUSER/$path"
  local url="git@$A_HOST:$path.git"
  local dest="$A_DIR/$(basename "$path")"
  mkdir -p "$A_DIR"
  hdr "Cloning"
  info "  $url"
  info "  -> $(tildify "$dest")"
  git clone "$url" "$dest" || return 1
  git -C "$dest" config user.name  "$A_NAME"
  git -C "$dest" config user.email "$A_EMAIL"
  ok "Cloned and pinned to $A_EMAIL"
}

cmd_apply() { # bind an existing repo to an account
  local a="${1:-}" dir="${2:-$PWD}"
  [[ -n "$a" ]] || a="$(pick_account)" || return 1
  load_account "$a" || die "No such account: $a"
  dir="$(expand_path "$dir")"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repo: $dir"
  git -C "$dir" config user.name  "$A_NAME"
  git -C "$dir" config user.email "$A_EMAIL"
  ok "Local identity set to $A_NAME <$A_EMAIL>"
  local remote path
  remote="$(git -C "$dir" remote get-url origin 2>/dev/null)"
  if [[ -n "$remote" ]]; then
    case "$remote" in
      git@github.com:*)     path="${remote#git@github.com:}" ;;
      https://github.com/*) path="${remote#https://github.com/}" ;;
      git@github.com-*:*)   path="${remote#*:}" ;;
      *) path="" ;;
    esac
    if [[ -n "$path" ]]; then
      git -C "$dir" remote set-url origin "git@$A_HOST:${path%.git}.git"
      ok "origin -> git@$A_HOST:${path%.git}.git"
    else
      warn "Remote '$remote' is not a GitHub URL - left untouched."
    fi
  else
    warn "No 'origin' remote found."
  fi
}

cmd_doctor() {
  ensure_dirs
  hdr "Environment"
  printf '  git         %s\n' "$(git --version 2>/dev/null || echo 'MISSING')"
  printf '  ssh         %s\n' "$(ssh -V 2>&1 || echo 'MISSING')"
  printf '  agent keys  %s\n' "$(ssh-add -l 2>/dev/null | wc -l | tr -d ' ')"

  local a list="${1:-}"
  if [[ -n "$list" ]]; then list="$list"; else list="$(aliases)"; fi
  while read -r a; do
    [[ -n "$a" ]] || continue
    load_account "$a" || { err "registry entry missing for '$a'"; continue; }
    hdr "Account: $A_ALIAS"
    [[ -f "$A_KEY" ]]     && ok "private key present" || err "private key missing: $(tildify "$A_KEY")"
    [[ -f "$A_KEY.pub" ]] && ok "public key present"  || err "public key missing"
    if [[ -f "$A_KEY" ]]; then
      local perm; perm="$(stat -c '%a' "$A_KEY" 2>/dev/null || stat -f '%Lp' "$A_KEY" 2>/dev/null)"
      [[ "$perm" == "600" ]] && ok "key permissions 600" || warn "key permissions are $perm (should be 600)"
    fi
    grep -q "^Host $A_HOST\$" "$SSH_CONFIG" && ok "ssh host alias present" || err "ssh host alias missing"
    grep -q "ghacct:$A_ALIAS" "$GIT_CONFIG" && ok "gitconfig include present" || err "gitconfig include missing"
    [[ -f "$HOME/.gitconfig-$A_ALIAS" ]] && ok "identity profile present" || err "identity profile missing"
    [[ -d "$A_DIR" ]] && ok "workspace exists" || warn "workspace missing: $(tildify "$A_DIR")"
  done <<< "$list"

  hdr "Effective identity in $(tildify "$PWD")"
  printf '  user.name   %s\n'  "$(git config user.name  2>/dev/null || echo '-')"
  printf '  user.email  %s\n'  "$(git config user.email 2>/dev/null || echo '-')"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '  origin      %s\n' "$(git remote get-url origin 2>/dev/null || echo '-')"
  else
    printf '  origin      %s\n' "(not a git repo)"
  fi
  echo
}

cmd_notes() {
  hdr "Zed: what each login controls"
  cat <<'EOF'
  Zed keeps three logins separate. Set them independently:

  1. Zed itself (settings sync, channels, Zed Pro)
     -> account menu, top-right corner. Sign in with your PRIMARY account.

  2. GitHub Copilot
     -> Command Palette (Cmd/Ctrl+Shift+P) -> "copilot: sign in"
     Can be a different GitHub account from #1.

  3. Git operations (clone / commit / push)
     -> NOT tied to either of the above. Driven by ~/.ssh/config and
        ~/.gitconfig, which is exactly what this script manages.

  Two accounts signed in at the same time:
     Install Zed Stable and Zed Preview side by side. Sign out of GitHub in
     your browser, log in as account A, authenticate Zed Stable; then swap the
     browser session to account B and authenticate Zed Preview.

  In Zed's built-in terminal, clone with the alias host:
     git clone git@github.com-work:org/repo.git
  Or just run:  ghacct clone work org/repo
EOF
  echo
}

# -------------------------------------------------------------------- menu --
pick_account() { # echoes chosen alias on stdout, prompts on stderr
  local n; n="$(count_accounts)"
  if [[ "$n" -eq 0 ]]; then err "No accounts configured yet."; return 1; fi
  local -a arr=(); local a i=1
  while read -r a; do arr+=("$a"); done < <(aliases)
  {
    printf '\n'
    for a in "${arr[@]}"; do
      load_account "$a"
      printf '   %2d) %-12s %s\n' "$i" "$a" "$A_EMAIL"
      i=$((i+1))
    done
    printf '\n'
  } >&2
  local sel
  read -r -p "  Select (number or alias): " sel </dev/tty
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#arr[@]} )); then
    printf '%s' "${arr[$((sel-1))]}"
  elif account_exists "$sel"; then
    printf '%s' "$sel"
  else
    err "Invalid selection."; return 1
  fi
}

menu() {
  ensure_dirs
  while :; do
    hdr "ghacct - multi GitHub account manager   ($(count_accounts) configured)"
    cat <<'EOF'
   1) List accounts            6) Test SSH connection
   2) Add account              7) Show / copy public key
   3) Show account details     8) Clone a repo as an account
   4) Edit account             9) Bind an existing repo to an account
   5) Delete account          10) Doctor - health check
                              11) Zed & Copilot notes
   0) Quit
EOF
    local c; read -r -p "  > " c
    echo
    case "$c" in
      1) cmd_list ;;
      2) cmd_add ;;
      3) cmd_show ;;
      4) cmd_edit ;;
      5) cmd_rm ;;
      6) cmd_test ;;
      7) local a; a="$(pick_account)" && show_pubkey "$a" ;;
      8) cmd_clone ;;
      9) local a d; a="$(pick_account)" || continue; prompt d "Repo folder" "$PWD"; cmd_apply "$a" "$d" ;;
      10) cmd_doctor ;;
      11) cmd_notes ;;
      0|q|quit|exit) info "Bye."; return 0 ;;
      *) err "Unknown option." ;;
    esac
    read -r -p "  [Enter] to continue " _
  done
}

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------- main --
main() {
  ensure_dirs
  local cmd="${1:-menu}"; shift || true
  case "$cmd" in
    menu)            menu ;;
    list|ls)         cmd_list ;;
    add|new|create)  cmd_add ;;
    show|info)       cmd_show "$@" ;;
    edit|update)     cmd_edit "$@" ;;
    rm|remove|del)   cmd_rm "$@" ;;
    test|check)      cmd_test "$@" ;;
    key|pubkey)      local a="${1:-}"; [[ -n "$a" ]] || a="$(pick_account)" || exit 1; show_pubkey "$a" ;;
    clone)           cmd_clone "$@" ;;
    apply|use)       cmd_apply "$@" ;;
    doctor|status)   cmd_doctor "$@" ;;
    notes|zed)       cmd_notes ;;
    -h|--help|help)  usage ;;
    *) err "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
