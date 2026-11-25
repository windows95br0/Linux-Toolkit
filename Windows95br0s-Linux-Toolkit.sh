#!/usr/bin/env bash
#
#  Windows95br0s-Linux-Toolkit
#  Installs a curated set of apps/tools on Debian-based Linux distros
#  (Debian, Ubuntu, Linux Mint, Pop!_OS, Kali, Zorin, elementary, ...).
#
#  Usage:
#    ./Windows95br0s-Linux-Toolkit.sh                 # interactive menu
#    ./Windows95br0s-Linux-Toolkit.sh vscode btop     # install specific apps
#    ./Windows95br0s-Linux-Toolkit.sh --list          # list available app IDs
#    ./Windows95br0s-Linux-Toolkit.sh --help
#
# install_*/verify_* functions are called dynamically; "A && B || die" is intentional.
# shellcheck disable=SC2317,SC2015,SC2016
set -uo pipefail

# sudo's secure_path often omits /usr/local/bin, where several tools install.
export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"

readonly TOOLKIT_NAME="Windows95br0s-Linux-Toolkit"
readonly TOOLKIT_VERSION="1.0.0"
LOG_FILE="/var/log/windows95br0s-linux-toolkit.log"
VERBOSE=0
FORCE=0
ASSUME_YES=0

# ---------------------------------------------------------------------------
#  App catalog:  id | category | name | description
#  Each id needs an install_<id> and verify_<id> function ("-" becomes "_").
# ---------------------------------------------------------------------------
readonly CATALOG=(
  "brave-stable|Browsers|Brave Browser (Release)|Stable channel - recommended"
  "brave-beta|Browsers|Brave Browser (Beta)|Preview of upcoming features"
  "brave-nightly|Browsers|Brave Browser (Nightly)|Bleeding edge daily builds"
  "vscode|Development|Visual Studio Code|Microsoft code editor (official .deb + repo)"
  "github-cli|Development|GitHub CLI|GitHub on the command line (gh)"
  "ollama|AI|Ollama|Run large language models locally"
  "discord|Communication|Discord|Voice, video and text chat"
  "steam|Gaming|Steam|Valve's gaming platform (enables i386 multiarch)"
  "vlc|Multimedia|VLC Media Player|Plays almost any audio/video format"
  "btop|System Monitoring|btop|Resource monitor (CPU, RAM, disks, net)"
  "nvtop|System Monitoring|nvtop|GPU monitor (NVIDIA, AMD, Intel)"
  "protonvpn-stable|Proton VPN|Proton VPN (Stable)|Official GUI app + CLI"
  "protonvpn-beta|Proton VPN|Proton VPN (Beta)|Beta GUI app + CLI (instead of Stable)"
  "protonvpn-tray|Proton VPN|Proton VPN Tray Icon Support|GNOME AppIndicator extension"
  "protonvpn-split|Proton VPN|Proton VPN Split Tunneling (Debian)|Kernel headers + systemd-resolved"
  "proton-mail|Proton Apps|Proton Mail|Encrypted email desktop app"
  "proton-mail-bridge|Proton Apps|Proton Mail Bridge|Use Proton Mail in Thunderbird/other IMAP clients"
  "proton-pass|Proton Apps|Proton Pass|Password manager desktop app"
  "proton-pass-cli|Proton Apps|Proton Pass CLI|Password manager command-line tool (pass-cli)"
  "proton-authenticator|Proton Apps|Proton Authenticator|2FA code generator desktop app"
  "proton-meet|Proton Apps|Proton Meet|Encrypted video calls desktop app"
  "proton-drive-cli|Proton Apps|Proton Drive CLI|Official Drive command-line tool (no Linux GUI yet)"
)

# ---------------------------------------------------------------------------
#  Output helpers
# ---------------------------------------------------------------------------
# Black & purple theme. C_RESET returns to the base purple-on-black style rather than
# the terminal default; red is kept only for failures so errors stand out.
if [[ -t 1 ]]; then
  C_RESET=$'\e[0;35;40m'     # purple on black (base text)
  C_BOLD=$'\e[1;95;40m'      # bold bright purple (headings)
  C_ACCENT=$'\e[1;95;40m'     # success
  C_DIM=$'\e[2;35;40m'       # secondary text
  C_YELLOW=$'\e[1;35;40m'    # warnings (bold purple)
  C_RED=$'\e[1;91;40m'       # errors only
  C_TERM_DEFAULT=$'\e[0m'
else
  C_RESET=""; C_BOLD=""; C_ACCENT=""; C_DIM=""; C_YELLOW=""; C_RED=""; C_TERM_DEFAULT=""
fi
C_BLUE=$C_BOLD
C_CYAN=$C_ACCENT

# whiptail (newt) black & purple theme
export NEWT_COLORS='
root=magenta,black
border=magenta,black
window=magenta,black
shadow=black,black
title=brightmagenta,black
roottext=brightmagenta,black
label=magenta,black
checkbox=magenta,black
actcheckbox=black,magenta
listbox=magenta,black
actlistbox=black,magenta
sellistbox=brightmagenta,black
actsellistbox=black,brightmagenta
textbox=magenta,black
acttextbox=black,magenta
entry=magenta,black
button=black,magenta
actbutton=black,brightmagenta
compactbutton=magenta,black
helpline=black,magenta
emptyscale=magenta,black
fullscale=black,magenta
'

apply_theme() {
  [[ -t 1 ]] || return 0
  # Set colors first so "clear" paints the whole screen black (background color erase).
  printf '%s' "$C_RESET"
  clear
}

restore_terminal() {
  [[ -t 1 ]] && printf '%s' "$C_TERM_DEFAULT"
  return 0
}

log()   { { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; } 2>/dev/null || true; }
info()  { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; log "INFO: $*"; }
ok()    { printf '  %s✔%s %s\n' "$C_ACCENT" "$C_RESET" "$*"; log "OK: $*"; }
warn()  { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; log "WARN: $*"; }
err()   { printf '  %s✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; log "ERROR: $*"; }
die()   { err "$*"; exit 1; }

banner() {
  printf '%s' "$C_BOLD"
  cat <<'EOF'
 __        ___           _                     ___  ____  _           ___
 \ \      / (_)_ __   __| | _____      _____  / _ \| ___|| |__  _ __ / _ \ 
  \ \ /\ / /| | '_ \ / _` |/ _ \ \ /\ / / __|| (_) |___ \| '_ \| '__| | | |
   \ V  V / | | | | | (_| | (_) \ V  V /\__ \ \__, |___) | |_) | |  | |_| |
    \_/\_/  |_|_| |_|\__,_|\___/ \_/\_/ |___/   /_/|____/|_.__/|_|   \___/
EOF
  printf '                      Linux Toolkit Alpha v%s%s\n\n' "$TOOLKIT_VERSION" "$C_RESET"
}

# Last failure message for the app currently being installed.
LAST_ERROR=""

# step "description" command [args...]
# Runs a command, logs its output, and records a readable error on failure.
step() {
  local desc="$1"; shift
  log "STEP: $desc :: $*"
  printf '    %s→%s %s ... ' "$C_CYAN" "$C_RESET" "$desc"
  local rc
  if (( VERBOSE )); then
    echo
    "$@" 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}
  else
    "$@" >>"$LOG_FILE" 2>&1
    rc=$?
  fi
  if (( rc == 0 )); then
    printf '%sdone%s\n' "$C_ACCENT" "$C_RESET"
  else
    printf '%sfailed (exit %d)%s\n' "$C_RED" "$rc" "$C_RESET"
    LAST_ERROR="$desc failed (exit code $rc)"
    log "FAILED: $LAST_ERROR"
  fi
  return "$rc"
}

fail() { LAST_ERROR="$*"; log "FAILED: $*"; return 1; }

# ---------------------------------------------------------------------------
#  System helpers
# ---------------------------------------------------------------------------
APT_OPTS=(-y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

apt_update()  { step "Refreshing package lists" env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update; }
apt_install() { step "Installing package(s): $*" env DEBIAN_FRONTEND=noninteractive apt-get install "${APT_OPTS[@]}" "$@"; }

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

pkg_available() {
  local candidate
  candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

download() {
  local url="$1" dest="$2"
  step "Downloading $(basename "$dest")" curl -fSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dest" "$url"
}

# checksum_ok <hex-digest> <file>  (SHA-256 or SHA-512, detected from digest length)
checksum_ok() {
  local sum="$1" file="$2" tool
  case ${#sum} in
    64)  tool=sha256sum ;;
    128) tool=sha512sum ;;
    *) echo "Unrecognised checksum: $sum"; return 1 ;;
  esac
  (cd "$(dirname "$file")" && echo "$sum  $(basename "$file")" | "$tool" --check -)
}

verify_download() {
  local sum="$1" file="$2"
  if [[ -n "$sum" && "$sum" != "null" ]]; then
    step "Verifying checksum of $(basename "$file")" checksum_ok "$sum" "$file"
  else
    warn "No checksum published for $(basename "$file"); relying on HTTPS download"
  fi
}

# json_query <url> <jq-filter> [jq args...]  -> sets JSON_RESULT, fails on empty/null
JSON_RESULT=""
json_query() {
  local url="$1" filter="$2"; shift 2
  local json
  json="$WORKDIR/$(basename "$url")"
  JSON_RESULT=""
  download "$url" "$json" || return 1
  JSON_RESULT=$(jq -r "$@" "$filter" "$json" 2>>"$LOG_FILE")
  if [[ -z "$JSON_RESULT" || "$JSON_RESULT" == *"null"* ]]; then
    fail "Could not find a matching download in $(basename "$url")"
    return 1
  fi
  log "Manifest result: $JSON_RESULT"
}

require_arch() {
  local a
  for a in "$@"; do [[ "$ARCH" == "$a" ]] && return 0; done
  fail "Unsupported architecture '$ARCH' (supported: $*)"
}

# Enable an extra Debian/Ubuntu component (e.g. contrib, universe) if a package isn't available.
ensure_component_for() {
  local pkg="$1"
  pkg_available "$pkg" && return 0

  if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ " $DISTRO_LIKE " == *" ubuntu "* ]]; then
    if have_cmd add-apt-repository; then
      step "Enabling 'universe' repository" add-apt-repository -y universe || return 1
    else
      apt_install software-properties-common || return 1
      step "Enabling 'universe' repository" add-apt-repository -y universe || return 1
    fi
  elif [[ "$DISTRO_ID" == "debian" ]]; then
    step "Enabling Debian 'contrib' component" enable_debian_contrib || return 1
  fi
  apt_update || return 1
  pkg_available "$pkg" || fail "Package '$pkg' is not available in your configured repositories"
}

enable_debian_contrib() {
  local f changed=0
  # deb822-style sources (Debian 12+/13 default)
  for f in /etc/apt/sources.list.d/*.sources; do
    [[ -f "$f" ]] || continue
    if grep -qE '^URIs:.*(deb\.debian\.org|security\.debian\.org|ftp\..*debian\.org)' "$f" \
       && grep -qE '^Components:' "$f" && ! grep -qE '^Components:.*\bcontrib\b' "$f"; then
      cp -a "$f" "$f.bak.$(date +%s)"
      sed -i -E '/^Components:/ s/$/ contrib/' "$f"
      changed=1
    fi
  done
  # Classic one-line sources.list
  if [[ -f /etc/apt/sources.list ]] && grep -qE '^deb .*debian' /etc/apt/sources.list \
     && grep -E '^deb .*debian' /etc/apt/sources.list | grep -vqE '\bcontrib\b'; then
    cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%s)"
    sed -i -E '/^deb(-src)? .*debian/ { /\bcontrib\b/! s/(\bmain\b)/\1 contrib/ }' /etc/apt/sources.list
    changed=1
  fi
  (( changed )) || echo "contrib appears to be enabled already"
  return 0
}

# ---------------------------------------------------------------------------
#  Brave Browser
# ---------------------------------------------------------------------------
install_brave_channel() {
  local channel="$1"   # release | beta | nightly
  local host="https://brave-browser-apt-${channel}.s3.brave.com"
  local keyring pkg
  if [[ "$channel" == "release" ]]; then
    keyring="brave-browser-archive-keyring.gpg"; pkg="brave-browser"
  else
    keyring="brave-browser-${channel}-archive-keyring.gpg"; pkg="brave-browser-${channel}"
  fi

  require_arch amd64 arm64 || return 1
  download "$host/$keyring" "/usr/share/keyrings/$keyring" || return 1
  download "$host/brave-browser.sources" "/etc/apt/sources.list.d/brave-browser-${channel}.sources" || return 1
  apt_update || return 1
  apt_install "$pkg"
}

install_brave_stable()  { install_brave_channel release; }
install_brave_beta()    { install_brave_channel beta; }
install_brave_nightly() { install_brave_channel nightly; }

verify_brave_stable()  { pkg_installed brave-browser && have_cmd brave-browser; }
verify_brave_beta()    { pkg_installed brave-browser-beta && have_cmd brave-browser-beta; }
verify_brave_nightly() { pkg_installed brave-browser-nightly && have_cmd brave-browser-nightly; }

# ---------------------------------------------------------------------------
#  Visual Studio Code
# ---------------------------------------------------------------------------
install_vscode() {
  local os
  case "$ARCH" in
    amd64) os="linux-deb-x64" ;;
    arm64) os="linux-deb-arm64" ;;
    armhf) os="linux-deb-armhf" ;;
    *) fail "Unsupported architecture '$ARCH' (supported: amd64 arm64 armhf)"; return 1 ;;
  esac
  # Let the package add Microsoft's apt repo so VS Code updates with the system.
  echo "code code/add-microsoft-repo boolean true" | debconf-set-selections 2>>"$LOG_FILE" || true
  download "https://code.visualstudio.com/sha/download?build=stable&os=${os}" "$WORKDIR/vscode.deb" || return 1
  apt_install "$WORKDIR/vscode.deb"
}
verify_vscode() { pkg_installed code && have_cmd code; }

# ---------------------------------------------------------------------------
#  GitHub CLI (official apt repo: cli.github.com)
# ---------------------------------------------------------------------------
install_github_cli() {
  local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  step "Creating /etc/apt/keyrings" install -d -m 0755 /etc/apt/keyrings || return 1
  download "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$keyring" || return 1
  chmod go+r "$keyring"
  step "Adding GitHub CLI repository" bash -c "echo 'deb [arch=$ARCH signed-by=$keyring] https://cli.github.com/packages stable main' > /etc/apt/sources.list.d/github-cli.list" || return 1
  apt_update || return 1
  apt_install gh
}
verify_github_cli() { pkg_installed gh && gh --version >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  Ollama
# ---------------------------------------------------------------------------
install_ollama() {
  require_arch amd64 arm64 || return 1
  download "https://ollama.com/install.sh" "$WORKDIR/ollama-install.sh" || return 1
  step "Running official Ollama installer" sh "$WORKDIR/ollama-install.sh"
}
verify_ollama() { have_cmd ollama && ollama --version >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  Discord
# ---------------------------------------------------------------------------
install_discord() {
  require_arch amd64 || return 1
  download "https://discord.com/api/download?platform=linux&format=deb" "$WORKDIR/discord.deb" || return 1
  apt_install "$WORKDIR/discord.deb"
}
verify_discord() { pkg_installed discord; }

# ---------------------------------------------------------------------------
#  Steam
# ---------------------------------------------------------------------------
install_steam() {
  require_arch amd64 || return 1
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    step "Enabling i386 multiarch" dpkg --add-architecture i386 || return 1
  fi
  apt_update || return 1
  download "https://cdn.akamai.steamstatic.com/client/installer/steam.deb" "$WORKDIR/steam.deb" || return 1
  apt_install "$WORKDIR/steam.deb" || return 1
  # Common 32-bit graphics libraries Steam needs on first launch (best effort).
  apt_install libgl1:i386 libgl1-mesa-dri:i386 || warn "Could not install 32-bit GL libraries; Steam will try on first launch"
  return 0
}
verify_steam() { { pkg_installed steam-launcher || pkg_installed steam-installer; } && have_cmd steam; }

# ---------------------------------------------------------------------------
#  btop / nvtop
# ---------------------------------------------------------------------------
install_btop() { apt_update && ensure_component_for btop && apt_install btop; }
verify_btop()  { pkg_installed btop && have_cmd btop; }

install_nvtop() { apt_update && ensure_component_for nvtop && apt_install nvtop; }
verify_nvtop()  { pkg_installed nvtop && have_cmd nvtop; }

# ---------------------------------------------------------------------------
#  Proton VPN
# ---------------------------------------------------------------------------
# Known checksums published by Proton; newer versions are used if found but can't be pre-verified.
declare -A PROTON_SHA256=(
  ["protonvpn-stable-release_1.0.10_all.deb"]="c8a9fffb4ebdd63db08ce7f11c9b0ac394064ae6a210feb9ab63a0f7d8d060a7"
  ["protonvpn-beta-release_1.0.10_all.deb"]="c8986b908898d06f9bdd3660718f1087282409a62c8d9059f67fc78b263bc6fb"
)

install_proton_channel() {
  local channel="$1"   # stable | beta
  local dist="stable" latest
  [[ "$channel" == "beta" ]] && dist="unstable"
  local base="https://repo.protonvpn.com/debian/dists/${dist}/main/binary-all"

  latest=$(curl -fsSL --retry 3 "$base/" 2>>"$LOG_FILE" \
           | grep -oE "protonvpn-${channel}-release_[0-9.]+_all\.deb" | sort -uV | tail -n1)
  [[ -n "$latest" ]] || latest="protonvpn-${channel}-release_1.0.10_all.deb"
  log "Proton VPN repo package: $latest"

  download "$base/$latest" "$WORKDIR/$latest" || return 1
  if [[ -n "${PROTON_SHA256[$latest]:-}" ]]; then
    verify_download "${PROTON_SHA256[$latest]}" "$WORKDIR/$latest" || return 1
  else
    warn "No known checksum for $latest (newer release); continuing - apt verifies the repo signature"
  fi
  local other="beta"
  [[ "$channel" == "beta" ]] && other="stable"
  # Stable and Beta repos can't coexist cleanly; switch channels by removing the other one.
  if pkg_installed "protonvpn-${other}-release"; then
    step "Removing Proton VPN ${other} repository (switching to ${channel})" \
      env DEBIAN_FRONTEND=noninteractive apt-get purge "${APT_OPTS[@]}" "protonvpn-${other}-release" || return 1
  fi

  apt_install "$WORKDIR/$latest" || return 1
  apt_update || return 1
  ensure_importlib_metadata_compat || return 1
  apt_install proton-vpn-gnome-desktop
}

# Proton's python3-proton-core still depends on python3-importlib-metadata, a backport
# that newer distros (e.g. Kali rolling, Debian testing on Python 3.12+) no longer ship.
# The code only uses the standard library's importlib.metadata, so when the backport is
# unavailable we build and install an empty package that "Provides" it.
ensure_importlib_metadata_compat() {
  pkg_available python3-importlib-metadata && return 0
  pkg_installed python3-importlib-metadata-compat && return 0
  apt-cache showpkg python3-importlib-metadata 2>/dev/null \
    | sed -n '/^Reverse Provides:/,$p' | tail -n +2 | grep -q '[a-z]' && return 0

  warn "python3-importlib-metadata isn't available on this distro; installing a compatibility package"
  local root="$WORKDIR/importlib-compat"
  mkdir -p "$root/DEBIAN"
  cat >"$root/DEBIAN/control" <<'EOF'
Package: python3-importlib-metadata-compat
Version: 1.0
Architecture: all
Maintainer: Windows95br0s-Linux-Toolkit <noreply@localhost>
Depends: python3 (>= 3.10)
Provides: python3-importlib-metadata
Section: python
Priority: optional
Description: Compatibility shim for Proton VPN on newer Python versions
 importlib.metadata is part of the Python 3 standard library. This empty
 package satisfies the outdated python3-importlib-metadata dependency of
 python3-proton-core. Installed by Windows95br0s-Linux-Toolkit.
EOF
  step "Building python3-importlib-metadata compatibility package" \
    dpkg-deb --root-owner-group --build "$root" "$WORKDIR/python3-importlib-metadata-compat_1.0_all.deb" || return 1
  apt_install "$WORKDIR/python3-importlib-metadata-compat_1.0_all.deb"
}

install_protonvpn_stable() { install_proton_channel stable; }
install_protonvpn_beta()   { install_proton_channel beta; }
verify_protonvpn_stable()  { pkg_installed protonvpn-stable-release && pkg_installed proton-vpn-gnome-desktop; }
verify_protonvpn_beta()    { pkg_installed protonvpn-beta-release && pkg_installed proton-vpn-gnome-desktop; }

install_protonvpn_tray() {
  apt_update || return 1
  apt_install gnome-shell-extension-appindicator || return 1
  if pkg_available gnome-shell-extension-prefs; then
    apt_install gnome-shell-extension-prefs || warn "Could not install gnome-shell-extension-prefs (optional)"
  fi
  warn "Log out/restart, then enable 'AppIndicator' in the Extensions app (Debian)"
  return 0
}
verify_protonvpn_tray() { pkg_installed gnome-shell-extension-appindicator; }

install_protonvpn_split() {
  apt_update || return 1
  if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ " $DISTRO_LIKE " == *" ubuntu "* ]]; then
    warn "Ubuntu-based system: split tunneling works out of the box, installing headers anyway"
  fi
  apt_install "linux-headers-$(uname -r)" systemd-resolved || return 1
  warn "Restart your computer to enable split tunneling in the Proton VPN app"
  return 0
}
verify_protonvpn_split() { pkg_installed "linux-headers-$(uname -r)" && pkg_installed systemd-resolved; }

# ---------------------------------------------------------------------------
#  Proton apps (Mail, Bridge, Pass, Pass CLI, Authenticator, Meet, Drive CLI)
#  Latest versions are resolved from Proton's official release manifests.
# ---------------------------------------------------------------------------
readonly PROTON_DL="https://proton.me/download"

# Desktop apps sharing the {"Releases":[{"CategoryName","File":[{Identifier,Url,Sha512CheckSum}]}]} format.
install_proton_desktop_deb() {
  local manifest="$1" url sum
  require_arch amd64 || return 1
  json_query "$manifest" \
    'first(.Releases[] | select(.CategoryName == "Stable")) | (.File // .Files)
     | map(select((.Identifier // "") | test("\\.deb"))) | first | "\(.Url) \(.Sha512CheckSum)"' || return 1
  read -r url sum <<<"$JSON_RESULT"
  local file
  file="$WORKDIR/$(basename "$url")"
  download "$url" "$file" || return 1
  verify_download "$sum" "$file" || return 1
  apt_install "$file"
}

install_proton_mail()          { install_proton_desktop_deb "$PROTON_DL/mail/linux/version.json"; }
install_proton_pass()          { install_proton_desktop_deb "$PROTON_DL/PassDesktop/linux/x64/version.json"; }
install_proton_authenticator() { install_proton_desktop_deb "$PROTON_DL/authenticator/linux/version.json"; }
install_proton_meet()          { install_proton_desktop_deb "$PROTON_DL/meet/linux/version.json"; }

verify_proton_mail()          { pkg_installed proton-mail; }
verify_proton_pass()          { pkg_installed proton-pass; }
verify_proton_authenticator() { pkg_installed proton-authenticator; }
verify_proton_meet()          { pkg_installed proton-meet; }

install_proton_mail_bridge() {
  local url
  require_arch amd64 || return 1
  json_query "$PROTON_DL/bridge/version_linux.json" \
    'first(.stable.Installers[] | select(test("_amd64\\.deb$")))' || return 1
  url="$JSON_RESULT"
  local file
  file="$WORKDIR/$(basename "$url")"
  download "$url" "$file" || return 1
  verify_download "" "$file"
  apt_install "$file"
}
verify_proton_mail_bridge() { pkg_installed protonmail-bridge; }

install_proton_pass_cli() {
  local key url sum
  case "$ARCH" in
    amd64) key="x86_64" ;;
    arm64) key="aarch64" ;;
    *) fail "Unsupported architecture '$ARCH' (supported: amd64 arm64)"; return 1 ;;
  esac
  json_query "$PROTON_DL/pass-cli/versions.json" \
    '.passCliVersions.urls.linux[$k] | "\(.url) \(.hash)"' --arg k "$key" || return 1
  read -r url sum <<<"$JSON_RESULT"
  download "$url" "$WORKDIR/pass-cli" || return 1
  verify_download "$sum" "$WORKDIR/pass-cli" || return 1
  step "Installing pass-cli to /usr/local/bin" install -m 0755 "$WORKDIR/pass-cli" /usr/local/bin/pass-cli
}
verify_proton_pass_cli() { [[ -x /usr/local/bin/pass-cli ]] && /usr/local/bin/pass-cli --version >/dev/null 2>&1; }

install_proton_drive_cli() {
  local platform url sum
  case "$ARCH" in
    amd64) platform="linux/x64" ;;
    arm64) platform="linux/arm64" ;;
    *) fail "Unsupported architecture '$ARCH' (supported: amd64 arm64)"; return 1 ;;
  esac
  json_query "$PROTON_DL/drive/cli/version.json" \
    'first(.Releases[] | select(.CategoryName == "Stable")) | .Files[]
     | select(.Platform == $p) | "\(.Url) \(.Sha512CheckSum)"' --arg p "$platform" || return 1
  read -r url sum <<<"$JSON_RESULT"
  download "$url" "$WORKDIR/proton-drive" || return 1
  verify_download "$sum" "$WORKDIR/proton-drive" || return 1
  step "Installing proton-drive to /usr/local/bin" install -m 0755 "$WORKDIR/proton-drive" /usr/local/bin/proton-drive
}
verify_proton_drive_cli() { [[ -x /usr/local/bin/proton-drive ]] && /usr/local/bin/proton-drive --version >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  VLC
# ---------------------------------------------------------------------------
install_vlc() { apt_update && ensure_component_for vlc && apt_install vlc; }
verify_vlc()  { pkg_installed vlc && have_cmd vlc; }

# ---------------------------------------------------------------------------
#  Internet speed test - Cloudflare (speed.cloudflare.com), nothing to install
# ---------------------------------------------------------------------------
readonly ST_BASE="https://speed.cloudflare.com"
readonly ST_DOWN_CHUNK=25000000   # Cloudflare rejects single downloads above ~50 MB
readonly ST_UP_CHUNK=10000000
readonly ST_STREAMS=4
ST_DURATION=10
ST_TMP=""
ST_PIDS=()

now_s() { date +%s.%N; }

st_remaining() { awk -v d="$1" -v n="$(now_s)" 'BEGIN { r = d - n; printf "%.2f", (r > 0 ? r : 0) }'; }

# st_worker <down|up> <start> <deadline> <outfile>
# Transfers until the deadline, then writes "<bytes> <seconds>" for this stream.
# Download counts every received byte. Upload counts only requests the server confirmed
# (curl's partial upload count includes data still sitting in the kernel send buffer),
# growing the request size from 256 KB so slow links still complete requests.
st_worker() {
  local mode="$1" start="$2" deadline="$3" out="$4" total=0 remain got res code
  local size=262144 confirmed=0 confirmed_at=0 partial=0
  while :; do
    remain=$(st_remaining "$deadline")
    awk -v r="$remain" 'BEGIN { exit !(r > 0.3) }' || break
    if [[ "$mode" == "down" ]]; then
      got=$(curl -s -o /dev/null --max-time "$remain" -w '%{size_download}' \
            "$ST_BASE/__down?bytes=$ST_DOWN_CHUNK" 2>/dev/null)
      got=${got%%.*}
      [[ "$got" =~ ^[0-9]+$ ]] || got=0
      (( got == 0 )) && break   # network error: stop instead of hammering the server
      total=$(( total + got ))
    else
      res=$(head -c "$size" "$ST_TMP/upload.bin" | curl -s -o /dev/null --max-time "$remain" -X POST \
            -H 'Content-Type: application/octet-stream' --data-binary @- \
            -w '%{http_code} %{size_upload}' "$ST_BASE/__up" 2>/dev/null)
      read -r code got <<<"$res"
      got=${got%%.*}
      [[ "$got" =~ ^[0-9]+$ ]] || got=0
      if [[ "$code" == "200" ]]; then
        confirmed=$(( confirmed + got ))
        confirmed_at=$(awk -v s="$start" -v n="$(now_s)" 'BEGIN { printf "%.3f", n - s }')
        (( size < ST_UP_CHUNK )) && size=$(( size * 2 > ST_UP_CHUNK ? ST_UP_CHUNK : size * 2 ))
      else
        partial=$got
        break
      fi
    fi
  done

  local elapsed
  elapsed=$(awk -v s="$start" -v n="$(now_s)" 'BEGIN { printf "%.3f", n - s }')
  if [[ "$mode" == "down" ]]; then
    echo "$total $elapsed" >"$out"
  elif (( confirmed > 0 )); then
    echo "$confirmed $confirmed_at" >"$out"
  else
    # Link too slow to finish even one request: fall back to curl's (optimistic) partial count.
    echo "$partial $elapsed" >"$out"
  fi
}

kill_tree() {
  local child
  for child in $(ps -o pid= --ppid "$1" 2>/dev/null); do kill_tree "$child"; done
  kill "$1" 2>/dev/null
}

st_stop_workers() {
  local p
  for p in "${ST_PIDS[@]}"; do kill_tree "$p"; done
  ST_PIDS=()
}

# st_phase <down|up> <label>: runs parallel streams for ST_DURATION seconds; sets ST_MBPS / ST_BYTES.
st_phase() {
  local mode="$1" label="$2" start deadline i f secs filled alive p
  local width=30
  start=$(now_s)
  deadline=$(awk -v s="$start" -v d="$ST_DURATION" 'BEGIN { printf "%.3f", s + d }')
  ST_PIDS=()
  trap 'st_stop_workers; rm -rf "$ST_TMP"; printf "\n"; exit 130' INT TERM
  for (( i = 0; i < ST_STREAMS; i++ )); do
    rm -f "$ST_TMP/$mode.$i"
    st_worker "$mode" "$start" "$deadline" "$ST_TMP/$mode.$i" &
    ST_PIDS+=("$!")
  done

  while :; do
    alive=0
    for p in "${ST_PIDS[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    (( alive )) || break
    if [[ -t 1 ]]; then
      secs=$(awk -v s="$start" -v n="$(now_s)" 'BEGIN { printf "%d", n - s }')
      (( secs > ST_DURATION )) && secs=$ST_DURATION
      filled=$(( secs * width / ST_DURATION ))
      printf '\r    %s→%s %-9s [%s%s] %2ds ' "$C_ACCENT" "$C_RESET" "$label" \
        "$(printf '%*s' "$filled" '' | tr ' ' '#')" "$(printf '%*s' $(( width - filled )) '' | tr ' ' '.')" "$secs"
    fi
    sleep 0.5
  done
  wait "${ST_PIDS[@]}" 2>/dev/null
  ST_PIDS=()
  trap - INT TERM

  local stats=""
  for (( i = 0; i < ST_STREAMS; i++ )); do
    f="$ST_TMP/$mode.$i"
    [[ -s "$f" ]] && stats+="$(<"$f")"$'\n'
  done
  # Total throughput = sum of each stream's bytes / that stream's measured time.
  read -r ST_BYTES ST_MBPS < <(awk 'NF == 2 { b += $1; if ($2 > 0) r += $1 * 8 / $2 }
                                    END { printf "%d %.2f\n", b, r / 1000000 }' <<<"$stats")
  [[ -t 1 ]] && printf '\r\e[K'
  printf '    %s→%s %-9s %s%s Mbps%s\n' "$C_ACCENT" "$C_RESET" "$label" "$C_BOLD" "$ST_MBPS" "$C_RESET"
}

# Ping = TCP handshake time (connect - DNS lookup); jitter = mean difference between samples.
st_latency() {
  local i t samples=()
  printf '    %s→%s %-9s ' "$C_ACCENT" "$C_RESET" "Ping"
  for (( i = 0; i < 10; i++ )); do
    t=$(curl -s -o /dev/null --max-time 5 -w '%{time_connect} %{time_namelookup}' "$ST_BASE/__down?bytes=0" 2>/dev/null) || continue
    samples+=("$(awk '{ printf "%.2f", ($1 - $2) * 1000 }' <<<"$t")")
  done
  if (( ${#samples[@]} == 0 )); then
    printf '%sfailed%s\n' "$C_RED" "$C_RESET"
    return 1
  fi
  ST_PING=$(printf '%s\n' "${samples[@]}" | sort -n \
    | awk '{ a[NR] = $1 } END { if (NR % 2) printf "%.1f", a[(NR + 1) / 2]; else printf "%.1f", (a[NR / 2] + a[NR / 2 + 1]) / 2 }')
  ST_JITTER=$(printf '%s\n' "${samples[@]}" \
    | awk 'NR > 1 { d = $1 - p; j += (d < 0 ? -d : d) } { p = $1 } END { printf "%.1f", (NR > 1 ? j / (NR - 1) : 0) }')
  printf '%s%s ms%s (jitter %s ms)\n' "$C_BOLD" "$ST_PING" "$C_RESET" "$ST_JITTER"
}

st_connection_info() {
  local trace info org
  trace=$(curl -s --max-time 5 "$ST_BASE/cdn-cgi/trace" 2>/dev/null)
  ST_IP=$(sed -n 's/^ip=//p' <<<"$trace")
  ST_COLO=$(sed -n 's/^colo=//p' <<<"$trace")
  info=$(curl -s --max-time 5 https://ipinfo.io/json 2>/dev/null)
  json_field() { sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" <<<"$info" | head -n1; }
  org=$(json_field org)
  # "AS6167 Verizon Business" -> "Verizon Business (AS6167)"
  if [[ "$org" =~ ^(AS[0-9]+)[[:space:]]+(.+)$ ]]; then
    ST_ISP="${BASH_REMATCH[2]} (${BASH_REMATCH[1]})"
  else
    ST_ISP="$org"
  fi
  ST_LOCATION=$(printf '%s, %s, %s' "$(json_field city)" "$(json_field region)" "$(json_field country)" | sed 's/^, //; s/, ,/,/g; s/, $//')
  [[ -n "$ST_IP" ]] || ST_IP=$(json_field ip)
}

# Sets ST_VPN to a description of an active VPN/tunnel, or empty.
st_detect_vpn() {
  local line name type
  ST_VPN=""
  if have_cmd nmcli; then
    while IFS=: read -r name type _; do
      [[ "$type" =~ (vpn|wireguard|tun) ]] && { ST_VPN="$name"; break; }
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)
  fi
  if [[ -z "$ST_VPN" ]]; then
    # proton0 = Proton VPN (WireGuard); tun/wg/tap = other VPN tunnels.
    while read -r line; do
      case "$line" in proton*|tun*|wg*|tap*) ST_VPN="interface $line"; break ;; esac
    done < <(ip -o link show up 2>/dev/null | awk -F': ' '{ sub(/@.*/, "", $2); print $2 }')
  fi
  if [[ -z "$ST_VPN" && "$ST_ISP" == *[Pp]roton* ]]; then
    ST_VPN="Proton VPN ($ST_ISP)"
  fi
  return 0
}

run_speedtest() {
  have_cmd curl || { err "curl is required for the speed test"; return 1; }
  ST_TMP=$(mktemp -d /tmp/w95br0-speedtest.XXXXXX) || { err "Cannot create temp dir"; return 1; }

  echo
  info "${C_BOLD}Internet Speed Test${C_RESET} (speed.cloudflare.com)"
  st_connection_info
  st_detect_vpn
  printf '    %-12s %s\n' "Public IP:" "${ST_IP:-unknown}" "ISP:" "${ST_ISP:-unknown}" \
    "Location:" "${ST_LOCATION:-unknown}" "Server:" "Cloudflare ${ST_COLO:-unknown}"

  if [[ -n "$ST_VPN" ]]; then
    if [[ "$ST_VPN" == *[Pp]roton* ]]; then
      warn "Proton VPN is connected ($ST_VPN)"
    else
      warn "A VPN/tunnel is active ($ST_VPN)"
    fi
    warn "Results will measure the VPN connection, not your raw ISP speed"
    if [[ -t 0 ]] && (( ! ASSUME_YES )); then
      local reply
      read -r -p "    Run the test through the VPN anyway? [Y/n] " reply
      if [[ "$reply" =~ ^([Nn]|[Nn][Oo])$ ]]; then
        echo "    Disconnect the VPN and run the speed test again."
        rm -rf "$ST_TMP"
        return 0
      fi
    fi
  fi
  echo

  if ! st_latency; then
    err "Can't reach speed.cloudflare.com - check your internet connection"
    rm -rf "$ST_TMP"
    return 1
  fi
  head -c "$ST_UP_CHUNK" /dev/urandom >"$ST_TMP/upload.bin"

  st_phase down "Download"
  local down_mbps=$ST_MBPS down_bytes=$ST_BYTES
  st_phase up "Upload"
  local up_mbps=$ST_MBPS up_bytes=$ST_BYTES
  rm -rf "$ST_TMP"

  local used
  used=$(awk -v b=$(( down_bytes + up_bytes )) 'BEGIN { printf "%.1f MB", b / 1000000 }')
  echo
  printf '%s%s%s\n' "$C_BOLD" "===================== Speed Test Results =====================" "$C_RESET"
  printf '    %-10s %s%s ms%s   (jitter %s ms)\n' "Ping" "$C_BOLD" "$ST_PING" "$C_RESET" "$ST_JITTER"
  printf '    %-10s %s%s Mbps%s\n' "Download" "$C_BOLD" "$down_mbps" "$C_RESET"
  printf '    %-10s %s%s Mbps%s\n' "Upload" "$C_BOLD" "$up_mbps" "$C_RESET"
  printf '    %-10s %s\n' "Data used" "$used"
  [[ -n "$ST_VPN" ]] && printf '    %-10s %s\n' "Note" "Measured through VPN: $ST_VPN"
  printf '%s%s%s\n\n' "$C_BOLD" "==============================================================" "$C_RESET"
  log "SPEEDTEST: ping=${ST_PING}ms jitter=${ST_JITTER}ms down=${down_mbps}Mbps up=${up_mbps}Mbps isp='${ST_ISP}' colo=${ST_COLO} vpn='${ST_VPN}'"

  if (( down_bytes == 0 && up_bytes == 0 )); then
    err "No data could be transferred - the test failed"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
#  Catalog helpers
# ---------------------------------------------------------------------------
field()     { local IFS='|'; read -r -a _f <<<"$1"; echo "${_f[$2]}"; }
app_entry() { local e; for e in "${CATALOG[@]}"; do [[ "${e%%|*}" == "$1" ]] && { echo "$e"; return 0; }; done; return 1; }
app_name()  { field "$(app_entry "$1")" 2; }
fn_id()     { echo "${1//-/_}"; }

list_apps() {
  local e last_cat="" id cat name desc
  for e in "${CATALOG[@]}"; do
    IFS='|' read -r id cat name desc <<<"$e"
    if [[ "$cat" != "$last_cat" ]]; then
      printf '\n%s%s%s\n' "$C_BOLD" "$cat" "$C_RESET"
      last_cat="$cat"
    fi
    printf '  %-21s %-36s %s%s%s\n' "$id" "$name" "$C_DIM" "$desc" "$C_RESET"
  done
  echo
}

# ---------------------------------------------------------------------------
#  Selection menus
# ---------------------------------------------------------------------------
SELECTED=()

menu_whiptail() {
  local args=() e id cat name desc status result
  for e in "${CATALOG[@]}"; do
    IFS='|' read -r id cat name desc <<<"$e"
    status=OFF
    "verify_$(fn_id "$id")" >/dev/null 2>&1 && name="$name (installed)"
    args+=("$id" "[$cat] $name - $desc" "$status")
  done
  local rows cols list_h
  rows=$(tput lines 2>/dev/null || echo 24); cols=$(tput cols 2>/dev/null || echo 80)
  (( rows > 40 )) && rows=40
  (( cols > 120 )) && cols=120
  list_h=$(( rows - 9 ))
  (( list_h > ${#CATALOG[@]} )) && list_h=${#CATALOG[@]}

  result=$(whiptail --title "$TOOLKIT_NAME v$TOOLKIT_VERSION" --separate-output \
           --checklist "SPACE = select, ENTER = confirm, ESC = cancel" \
           "$rows" "$cols" "$list_h" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
  mapfile -t SELECTED <<<"$result"
  [[ -z "${SELECTED[0]:-}" ]] && SELECTED=()
  return 0
}

menu_text() {
  local i=0 e id cat name desc last_cat="" mark ids=()
  echo "${C_BOLD}Select what to install:${C_RESET}"
  for e in "${CATALOG[@]}"; do
    IFS='|' read -r id cat name desc <<<"$e"
    if [[ "$cat" != "$last_cat" ]]; then
      printf '\n %s%s%s\n' "$C_BOLD$C_CYAN" "$cat" "$C_RESET"
      last_cat="$cat"
    fi
    i=$((i + 1)); ids+=("$id")
    mark=""
    "verify_$(fn_id "$id")" >/dev/null 2>&1 && mark=" ${C_ACCENT}(installed)${C_RESET}"
    printf '  %2d) %-36s %s%s%s%s\n' "$i" "$name" "$C_DIM" "$desc" "$C_RESET" "$mark"
  done
  echo
  local answer n
  read -r -p "Enter numbers separated by spaces (e.g. 1 4 8), 'a' for all, 'q' to quit: " answer
  case "$answer" in
    q|Q|"") return 1 ;;
    a|A) SELECTED=("${ids[@]}"); return 0 ;;
  esac
  for n in ${answer//,/ }; do
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ids[@]} )); then
      SELECTED+=("${ids[n-1]}")
    else
      warn "Ignoring invalid choice: $n"
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
$TOOLKIT_NAME v$TOOLKIT_VERSION
Install your favorite apps/tools on Debian-based Linux distros.

Usage: $(basename "$0") [options] [app-id ...]

Options:
  -l, --list       List available app IDs and exit
  -a, --all        Install everything (Proton VPN Beta excluded; Stable is used)
  -f, --force      Reinstall/upgrade apps that are already installed
  -y, --yes        Don't ask for confirmation
  -v, --verbose    Show full command output (always saved to the log)
      --log FILE   Log file (default: $LOG_FILE)
  -s, --speedtest  Run an internet speed test (Cloudflare) and exit; no root needed
      --duration N Seconds per download/upload phase (3-60, default: $ST_DURATION)
  -h, --help       Show this help

Without app IDs an interactive menu is shown.
EOF
}

# Top-level menu; sets MAIN_CHOICE to install | speedtest | exit.
main_menu() {
  MAIN_CHOICE="exit"
  if have_cmd whiptail && [[ -t 0 ]]; then
    MAIN_CHOICE=$(whiptail --title "$TOOLKIT_NAME v$TOOLKIT_VERSION" --menu "What would you like to do?" 14 64 3 \
      install   "Install apps & tools" \
      speedtest "Run internet speed test (Cloudflare)" \
      exit      "Exit" 3>&1 1>&2 2>&3) || MAIN_CHOICE="exit"
    return 0
  fi
  local answer
  echo "${C_BOLD}What would you like to do?${C_RESET}"
  echo "   1) Install apps & tools"
  echo "   2) Run internet speed test (Cloudflare)"
  echo "   3) Exit"
  read -r -p "Choose [1-3]: " answer
  case "$answer" in
    1) MAIN_CHOICE="install" ;;
    2) MAIN_CHOICE="speedtest" ;;
    *) MAIN_CHOICE="exit" ;;
  esac
}

preflight() {
  [[ -r /etc/os-release ]] || die "Cannot detect distribution (/etc/os-release missing)"
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_LIKE="${ID_LIKE:-}"
  DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
  if [[ "$DISTRO_ID" != "debian" && " $DISTRO_LIKE " != *" debian "* && " $DISTRO_LIKE " != *" ubuntu "* ]] \
     || ! have_cmd apt-get || ! have_cmd dpkg; then
    die "This toolkit supports Debian-based distros only (detected: $DISTRO_NAME)"
  fi
  ARCH=$(dpkg --print-architecture)
}

ensure_prereqs() {
  local need=() p
  for p in curl ca-certificates gpg jq; do pkg_installed "$p" || need+=("$p"); done
  if [[ -t 0 ]] && ! have_cmd whiptail; then need+=(whiptail); fi
  if (( ${#need[@]} )); then
    info "Installing prerequisites: ${need[*]}"
    apt_update && apt_install "${need[@]}" || die "Failed to install prerequisites (see $LOG_FILE)"
  fi
}

main() {
  trap restore_terminal EXIT
  local args=() select_all=0 speedtest_only=0
  while (( $# )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -l|--list) list_apps; exit 0 ;;
      -a|--all) select_all=1 ;;
      -f|--force) FORCE=1 ;;
      -y|--yes) ASSUME_YES=1 ;;
      -v|--verbose) VERBOSE=1 ;;
      -s|--speedtest) speedtest_only=1 ;;
      --duration)
        shift
        [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 3 && $1 <= 60 )) || die "--duration needs a number of seconds (3-60)"
        ST_DURATION="$1" ;;
      --log) shift; [[ -n "${1:-}" ]] || die "--log needs a file path"; LOG_FILE="$1" ;;
      -*) die "Unknown option: $1 (see --help)" ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  if (( speedtest_only )); then
    apply_theme
    banner
    run_speedtest
    exit $?
  fi

  preflight

  if (( EUID != 0 )); then
    have_cmd sudo || die "Please run as root (sudo is not installed)"
    echo "Root privileges are required - re-running with sudo..."
    local reexec=()
    (( select_all )) && reexec+=(--all)
    (( FORCE )) && reexec+=(--force)
    (( ASSUME_YES )) && reexec+=(--yes)
    (( VERBOSE )) && reexec+=(--verbose)
    reexec+=(--duration "$ST_DURATION")
    reexec+=(--log "$LOG_FILE")
    exec sudo bash "$(readlink -f "$0")" "${reexec[@]}" "${args[@]}"
  fi

  mkdir -p "$(dirname "$LOG_FILE")" && : >>"$LOG_FILE" || die "Cannot write log file $LOG_FILE"
  log "===== $TOOLKIT_NAME v$TOOLKIT_VERSION started on $DISTRO_NAME ($ARCH) ====="

  WORKDIR=$(mktemp -d /tmp/w95br0-toolkit.XXXXXX)
  # Allow the _apt user to read local .deb files (avoids apt "unsandboxed download" warnings).
  chmod 755 "$WORKDIR"
  trap 'rm -rf "$WORKDIR"; restore_terminal' EXIT

  apply_theme
  banner
  info "Detected: $DISTRO_NAME ($ARCH)"
  ensure_prereqs

  # --- Build selection ---
  if (( select_all )); then
    local e
    for e in "${CATALOG[@]}"; do SELECTED+=("${e%%|*}"); done
  elif (( ${#args[@]} )); then
    local a
    for a in "${args[@]}"; do
      app_entry "$a" >/dev/null || die "Unknown app id '$a' (see --list)"
      SELECTED+=("$a")
    done
  else
    while :; do
      main_menu
      case "$MAIN_CHOICE" in
        speedtest)
          apply_theme
          banner
          run_speedtest
          read -r -p "Press Enter to return to the menu..." _
          ;;
        install)
          if have_cmd whiptail && [[ -t 0 ]]; then
            menu_whiptail && break
          else
            menu_text && break
          fi
          ;;
        *) echo "Bye!"; exit 0 ;;
      esac
      apply_theme
      banner
    done
  fi

  # De-duplicate while keeping catalog order.
  local ordered=() e id s
  for e in "${CATALOG[@]}"; do
    id="${e%%|*}"
    for s in "${SELECTED[@]}"; do [[ "$s" == "$id" ]] && { ordered+=("$id"); break; }; done
  done
  SELECTED=("${ordered[@]}")

  # Proton VPN Stable and Beta use conflicting repo packages.
  if [[ " ${SELECTED[*]} " == *" protonvpn-stable "* && " ${SELECTED[*]} " == *" protonvpn-beta "* ]]; then
    (( select_all )) || warn "Proton VPN Stable and Beta can't both be installed - using Stable"
    local filtered=()
    for s in "${SELECTED[@]}"; do [[ "$s" != "protonvpn-beta" ]] && filtered+=("$s"); done
    SELECTED=("${filtered[@]}")
  fi

  (( ${#SELECTED[@]} )) || { echo "Nothing selected."; exit 0; }

  echo
  info "The following will be installed:"
  for id in "${SELECTED[@]}"; do echo "    - $(app_name "$id")"; done
  echo
  if (( ! ASSUME_YES )) && [[ -t 0 ]]; then
    local reply
    read -r -p "Continue? [Y/n] " reply
    [[ "$reply" =~ ^([Nn]|[Nn][Oo])$ ]] && { echo "Aborted."; exit 0; }
  fi

  # --- Install ---
  declare -A RESULT=() DETAIL=()
  local fid name
  for id in "${SELECTED[@]}"; do
    fid=$(fn_id "$id"); name=$(app_name "$id")
    echo
    info "${C_BOLD}$name${C_RESET}"
    LAST_ERROR=""

    if (( ! FORCE )) && "verify_$fid" >/dev/null 2>&1; then
      ok "$name is already installed - skipping (use --force to reinstall/upgrade)"
      RESULT[$id]="SKIPPED"; DETAIL[$id]="already installed"
      continue
    fi

    if "install_$fid"; then
      if "verify_$fid" >/dev/null 2>&1; then
        ok "$name installed and verified"
        RESULT[$id]="OK"; DETAIL[$id]="installed and verified"
      else
        err "$name: installer finished but verification failed"
        RESULT[$id]="FAILED"; DETAIL[$id]="installed but verification failed"
      fi
    else
      err "$name: ${LAST_ERROR:-installation failed}"
      RESULT[$id]="FAILED"; DETAIL[$id]="${LAST_ERROR:-installation failed}"
    fi
  done

  # --- Report ---
  local n_ok=0 n_fail=0 n_skip=0 color symbol
  echo
  printf '%s%s%s\n' "$C_BOLD" "==================== Installation Report ====================" "$C_RESET"
  for id in "${SELECTED[@]}"; do
    case "${RESULT[$id]}" in
      OK)      color=$C_ACCENT;  symbol="✔ OK     "; n_ok=$((n_ok + 1)) ;;
      SKIPPED) color=$C_YELLOW; symbol="• SKIPPED"; n_skip=$((n_skip + 1)) ;;
      *)       color=$C_RED;    symbol="✘ FAILED "; n_fail=$((n_fail + 1)) ;;
    esac
    printf '  %s%s%s  %-36s %s\n' "$color" "$symbol" "$C_RESET" "$(app_name "$id")" "${DETAIL[$id]}"
    log "RESULT: $id ${RESULT[$id]} - ${DETAIL[$id]}"
  done
  printf '%s%s%s\n' "$C_BOLD" "=============================================================" "$C_RESET"
  printf '  %d succeeded, %d failed, %d skipped\n' "$n_ok" "$n_fail" "$n_skip"
  printf '  Full log: %s\n\n' "$LOG_FILE"

  if (( n_fail )); then
    err "Some installations failed. Last log lines:"
    tail -n 15 "$LOG_FILE" | sed 's/^/      /' >&2
    exit 1
  fi
  exit 0
}

main "$@"
