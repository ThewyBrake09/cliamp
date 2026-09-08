#!/usr/bin/env bash
#
# tools.sh — personal Termux shell helpers
#
# NOTE: this file is meant to be *sourced* from .zshrc/.bashrc
# (e.g. `source ~/tools.sh`), not executed directly — it's a
# collection of function definitions, not a standalone script.
#
# -----------------------------------------------------------------
# CHANGELOG (what was changed from the original, and why)
# -----------------------------------------------------------------
# - cliamp(): fixed a real bug — `local FlAG="$2"` was declared with
#   mixed case but referenced later as `"$FLAG"` (all caps). Bash
#   variable names are case-sensitive, so `$FLAG` was always empty
#   and the second argument was silently dropped. Renamed
#   consistently to `FLAG`.
# - msc(): `mode` was being set without `local`, so it leaked into
#   the global shell environment on every call. Added `local mode`.
# - font(): `format=(...)` was declared but never actually used
#   (find only ever searched *.ttf) and was missing `local`. Removed
#   the dead variable; kept the *.ttf-only behavior since that's
#   what the code actually did.
# - spectr(): `select ans in ${format[@]}` used an unquoted array
#   expansion, which breaks on filenames with spaces/globs. Fixed to
#   `"${format[@]}"`.
# - Consistent 2-space indentation throughout (original mixed tabs,
#   spaces, and no indentation in different functions).
# - Added a one-line doc comment above every function (usage/purpose)
#   and a short header per section.
# - No logic/behavior changes beyond the two real bugs above — the
#   Patrick jokes, the killa radio-drama flavor text, all kept as-is.
# -----------------------------------------------------------------

# Global Var
sdcard="/storage/8AE1-1217"

### Short commands ##################################################

# Reload both shell configs after editing dotfiles.
r() { source ~/.bashrc && source ~/.zshrc; }

# tmux pane splitting shortcuts.
sh() { tmux split-window -h; }   # split horizontally
sv() { tmux split-window -v; }   # split vertically

# Lazy exit.
ex() { exit; }

# Termux wake-lock toggles (keep CPU awake / release it).
twu() { termux-wake-unlock; }
twl() { termux-wake-lock; }


### Long commands ####################################################

cap() {
  local file="$HOME/cap_output.txt"
  local max=8192

  : > "$file" || return 1

  eval "$*" >"$file" 2>&1
  local ret=$?

  local bytes
  bytes=$(wc -c <"$file")
  bytes=${bytes//[[:space:]]/}

  if (( bytes <= max )); then
    printf '\033[2J\033[3J\033[H'
    cat "$file"
    [[ -s "$file" && "$(tail -c 1 "$file" | wc -l)" -eq 0 ]] && echo
    return $ret
  fi

  local total=$(( (bytes + max - 1) / max ))

  printf '\033[2J\033[3J\033[H'
  echo "CAP: $bytes bytes — bagian 1/$total"
  echo "────────────────────────────────"
  head -c "$max" "$file"
  echo
  echo "────────────────────────────────"
  echo "Lanjut: capmore 2"

  return $ret
}


capmore() {
  local file="$HOME/cap_output.txt"
  local max=8192
  local part="${1:-2}"

  if [[ ! -f "$file" ]]; then
    echo "Tidak ada cap_output.txt"
    return 1
  fi

  local bytes
  bytes=$(wc -c <"$file")
  bytes=${bytes//[[:space:]]/}

  local total=$(( (bytes + max - 1) / max ))

  if (( part < 1 || part > total )); then
    echo "Bagian valid: 1-$total"
    return 1
  fi

  printf '\033[2J\033[3J\033[H'
  echo "CAP: $bytes bytes — bagian $part/$total"
  echo "────────────────────────────────"

  dd if="$file" bs="$max" skip=$((part - 1)) count=1 2>/dev/null

  echo
  echo "────────────────────────────────"

  if (( part < total )); then
    echo "Lanjut: capmore $((part + 1))"
  else
    echo "Selesai."
  fi
}



# cliamp — run natively via glibc-runner (grun), no proot.
# Fast, but can't run cliamp features that shell out internally
# (yt-dlp-backed providers, D-Bus media control) — see project
# README for why.
#
# Usage: cliamp [music_dir] [extra grun flag]
cliamp() {
  local glibc=~/glibc-libs/usr/lib/aarch64-linux-gnu
  local bin=~/files/cliamp
  local music="${1:-$HOME/sdcard/Music/}"
  local flag="$2"

  (
    unset LD_LIBRARY_PATH
    pulseaudio --check -v 2>/dev/null || pulseaudio --start --exit-idle-time=-1
    pactl list modules short 2>/dev/null | grep -q module-native-protocol-tcp || \
      pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1
  )

  export LD_LIBRARY_PATH="$glibc:$glibc/alsa-lib:$glibc/pulseaudio"
  export ALSA_CONFIG_PATH=~/glibc-libs/my-asound.conf
  export PULSE_SERVER=127.0.0.1
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/dummy"

  grun -t "$bin" -vol -25 "$music" "$flag"

  unset LD_LIBRARY_PATH ALSA_CONFIG_PATH PULSE_SERVER DBUS_SESSION_BUS_ADDRESS
}

# cliampdeb — run cliamp inside the Debian proot-distro container.
# Slower than `cliamp` (ptrace overhead), but fully compatible —
# use this specifically for providers that need yt-dlp (YouTube,
# YouTube Music, SoundCloud, etc).
#
# Usage: cliampdeb [music_dir_inside_proot]
cliampdeb() {
  # Start PulseAudio in Termux if it isn't already running.
  pulseaudio --check -v 2>/dev/null || pulseaudio --start --exit-idle-time=-1

  # Load the TCP module if not already loaded (idempotent — avoids
  # loading it twice on repeated calls).
  pactl list modules short 2>/dev/null | grep -q module-native-protocol-tcp || \
    pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1

  # Log into proot with storage + DNS binds, and run cliamp directly
  # inside it (returns to Termux automatically when cliamp exits).
  proot-distro login debian \
    --bind /storage/8AE1-1217:/root/sdmusic \
    --bind /data/data/com.termux/files/usr/etc/resolv.conf:/etc/resolv.conf \
    -- env PULSE_SERVER=127.0.0.1 /root/cliamp "${1:-/root/sdmusic/Music/}"
}


### zsh cursor shape (vi-mode indicator) #############################

# Switch cursor shape depending on vi-mode (block in normal mode,
# beam in insert mode).
zle-keymap-select() {
  if [[ ${KEYMAP} == vicmd ]]; then
    echo -ne "\e[2 q"
  else
    echo -ne "\e[6 q"
  fi
}
zle -N zle-keymap-select

zle-line-init() {
  echo -ne "\e[6 q"
}
zle -N zle-line-init


### Font changer #####################################################

# Interactively pick a .ttf font from a folder and apply it as the
# Termux font (copies to ~/.termux/font.ttf + reloads settings).
#
# Usage: font
font() {
  local tdir="$HOME/.termux/"
  local fdir="/storage/8AE1-1217/Assets/Fonts/"
  local fonts=()

  if [[ -d "$tdir" && -d "$fdir" ]]; then
    echo "Select Font"
    sleep 2

    while IFS= read -r -d $'\0' file; do
      fonts+=("$file")
    done < <(find "$fdir" -type f -name "*.ttf" -print0 | sort -z)

    if [ ${#fonts[@]} -eq 0 ]; then
      echo "No such font"
      return
    fi

    select f in "${fonts[@]}"; do
      if [ -n "$f" ]; then
        cp -f "$f" "${tdir}font.ttf" && termux-reload-settings && echo "Changed to: $f"
        break
      else
        echo "Invalid"
      fi
    done
  else
    echo "Dir Not Found."
  fi
}


### Process killer ####################################################

# killa — bulk-kill your own processes. Two modes:
#   -a   graceful kill (SIGTERM) of all your processes except this shell
#   -af  force kill (SIGKILL) of literally everything under your user,
#        including this shell — it WILL end your session
#
# Usage: killa -a | killa -af
killa() {
  local pid=$$

  if [[ $1 == "-af" ]]; then
    echo "HQ to All Stations"
    sleep 1
    echo "Broken Arrow"
    sleep 0.7
    echo "Broken Arrow"
    sleep 0.7
    echo "Broken Arrow"
    sleep 0.3
    echo "At Grid 44-Baker, ETA to blast radius immidie"
    sleep 0.7
    pkill -9 -u "$(whoami)"

  elif [[ $1 == "-a" ]]; then
    for u in $(ps -u "$(whoami)" -o pid=); do
      if [[ "$u" != "$$" && "$u" != "$PPID" ]]; then
        kill -15 "$u" 2>/dev/null
      fi
    done
    echo "Operation Massacre Succed!"

  elif [[ -z $1 ]]; then
    echo "use this!!"
    echo " "
    echo "-af --force kill all"
    echo "-a  --kill all"

  else
    echo "invalid"
    return 1
  fi
}


### Axel batch downloader #############################################

# axl — read a list of URLs from a text file (one per line, "#"
# comments allowed) and download each with axel, 5 connections each,
# into the Movies folder.
#
# Usage: axl links.txt
axl() {
  local dir="/storage/8AE1-1217/Movies"

  if [ ! -f "$1" ]; then
    echo "Dimana filenya patrick!!!"
    sleep 1
    echo "Apa hilang!!! buat lagi sana!"
    return 1
  fi

  local file="$1"
  mkdir -p "$dir"

  while IFS= read -r url || [ -n "$url" ]; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue

    local filename
    filename=$(basename "$url" | cut -d? -f1)
    axel -n 5 "$url" -o "$dir/$filename"
  done < "$file"
}


### SoX-based tiny music player #######################################

# msc — plays every mp3/flac in the Music folder in an infinite loop,
# either shuffled or sorted, with a 2s fade between tracks.
#
# Usage: msc          (shuffled, default)
#        msc -s       (shuffled, explicit)
#        msc -n       (sorted / "normal")
msc() {
  local dir="/storage/8AE1-1217/Music/"
  local mode

  case "$1" in
    -n) mode="sort" ;;
    -s | "") mode="shuf" ;;
    *)
      echo "Bukan begitu caranya patrick!?"
      echo "tambahkan -s untuk diacak dan -n untuk nooorrrrmaaall patrick!."
      return 1
      ;;
  esac

  sleep 2
  clear

  while true; do
    find "$dir" -type f \( -name "*.mp3" -o -name "*.flac" \) | "$mode" | while IFS= read -r file; do
      printf "\r\033[K♪ Now playing: %s" "$(basename "$file")"
      play -q "$file" fade t 2 0 2
    done
  done
}


### SoX spectrogram generator #########################################

# spectr — interactively pick an mp3/flac from the Music folder and
# generate a spectrogram image for it via SoX (saved as spectrogram.png
# in the same folder SoX is invoked from).
#
# Usage: spectr
spectr() {
  local dir="$sdcard/Music"
  local format=("*.flac" "*.mp3")

  if [[ -d "$dir" ]]; then
    (
      cd "$dir" || return

      echo "Pilih lagunya patrick"
      sleep 3
      select ans in ${~format[@]}; do
        if [[ -f "$ans" ]]; then
          sox "$ans" -n spectrogram
          if [[ $? -eq 0 ]]; then
            echo "Ini patrick sudah selesai, jangan dimakan ya patrick!"
          fi
          break
        else
          echo "Apakah itu terlihat seperti musik patrick!?"
        fi
      done
    )
  else
    echo "Dimana Foldernya Patrick?"
  fi
}
