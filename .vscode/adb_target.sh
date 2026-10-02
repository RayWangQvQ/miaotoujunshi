#!/bin/bash
#
# adb_target.sh - resolve the single adb device this workspace should talk to.
#
# Why this exists
# ---------------
# This handset advertises two wireless-debugging listeners, so adb can hold two
# transports for the same phone at once - one named
# "adb-<serial>-<token>._adb-tls-connect._tcp" and a second named
# "adb-<serial>-<token> (2)._adb-tls-connect._tcp" (adb appends " (N)" when a
# service name is seen again). Which of the two is the live listener is not
# stable, so the name alone says nothing about which transport to trust.
#
# With two transports attached, every plain `adb` call aborts with "more than
# one device/emulator", and Gradle installs the APK once per transport. This
# helper picks exactly one transport and prints its serial on stdout; callers
# export that value as ANDROID_SERIAL, which both adb and the Android Gradle
# Plugin treat as a hard filter (Gradle then fails loudly instead of installing
# everywhere).
#
# Selection rules, in order
# -------------------------
#   1. ANDROID_SERIAL, when set, wins (it must be attached).
#   2. Exactly one device attached -> that one.
#   3. Several devices but exactly one physical handset -> the handset, so that
#      a running emulator does not block real-device debugging.
#   4. Anything else is ambiguous -> exit 2 and make the caller pick.
# Within the chosen device the transports are tried in a stable order - wired
# or emulator before wireless, canonical name before the " (N)" one - and the
# first one that answers is used, so a stale entry cannot be picked blindly.
#
# This script only reads adb state; it never disconnects or installs anything.
# `adb disconnect` cannot clean this up anyway: the phone re-advertises the
# second listener, so adb adds the duplicate transport back. To get rid of it
# permanently, toggle wireless debugging off and on again on the handset.
#
# Usage
# -----
#   adb_target.sh            print the chosen serial on stdout
#   adb_target.sh --verbose  also print the candidate table (stderr)
#
# stdout carries nothing but the serial and every diagnostic goes to stderr,
# so the script is safe inside "$( ... )".
#
# Exit codes
# ----------
#   0  a single target was resolved
#   1  no device is in the "device" state
#   2  several candidate devices - the caller must pick one
#   3  the resolved target is not usable
#
# Environment
# -----------
#   ADB             adb binary to use (default: PATH, then ANDROID_HOME /
#                   ANDROID_SDK_ROOT / ~/Library/Android/sdk)
#   ANDROID_SERIAL  when set it wins, provided the transport is attached

set -u

log() { printf '%s\n' "$*" >&2; }

resolve_adb() {
  if [ -n "${ADB:-}" ] && [ -x "${ADB}" ]; then printf '%s\n' "$ADB"; return 0; fi
  if [ -n "${ADB:-}" ] && command -v "$ADB" >/dev/null 2>&1; then command -v "$ADB"; return 0; fi
  if command -v adb >/dev/null 2>&1; then command -v adb; return 0; fi
  for root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
    [ -n "$root" ] || continue
    if [ -x "$root/platform-tools/adb" ]; then printf '%s\n' "$root/platform-tools/adb"; return 0; fi
  done
  return 1
}

ADB_BIN="$(resolve_adb)" || { log "adb not found - put it on PATH or set ADB / ANDROID_HOME"; exit 3; }

# `adb devices` separates the serial from the state with a tab; the serial
# itself may contain spaces ("... (2)._adb-tls-connect._tcp"), so split on tab.
attached_serials() {
  "$ADB_BIN" devices 2>/dev/null | awk -F'\t' 'NR > 1 && $2 ~ /^device$/ { print $1 }'
}

is_mdns() {
  case "$1" in
    *._adb-tls-connect._tcp|*._adb-tls-pairing._tcp|*._adb._tcp) return 0 ;;
    *) return 1 ;;
  esac
}

kind_of() {
  case "$1" in
    emulator-*) printf 'emulator' ;;
    *) printf 'physical' ;;
  esac
}

# Fallback identity for transports whose ro.serialno cannot be read: strip the
# mDNS decoration and the per-pairing token so that duplicates collapse.
identity_of() {
  case "$1" in
    *._adb-tls-connect._tcp|*._adb-tls-pairing._tcp|*._adb._tcp)
      printf '%s' "$1" \
        | sed -E 's/\._adb(-tls-connect|-tls-pairing)?\._tcp$//' \
        | sed -E 's/^adb-//' \
        | sed -E 's/ \([0-9]+\)$//' \
        | sed -E 's/-[A-Za-z0-9]+$//'
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# 0 = wired or emulator, 1 = canonical wireless name, 2 = the " (N)" duplicate
rank_of() {
  if ! is_mdns "$1"; then printf '0'; return; fi
  case "$1" in
    *" ("*")"._adb*) printf '2' ;;
    *) printf '1' ;;
  esac
}

usable() {
  [ "$("$ADB_BIN" -s "$1" get-state 2>/dev/null)" = "device" ]
}

# The handset behind a transport. Two transports reporting the same ro.serialno
# are the same device reached twice; distinct values mean distinct devices.
hardware_identity() {
  serialno="$("$ADB_BIN" -s "$1" shell getprop ro.serialno 2>/dev/null | tr -d '\r\n ')"
  if [ -n "$serialno" ]; then printf '%s' "$serialno"; else identity_of "$1"; fi
}

VERBOSE=0
case "${1:-}" in
  --verbose|-v) VERBOSE=1 ;;
  "") ;;
  *) log "unknown option: $1"; exit 3 ;;
esac

serials="$(attached_serials)"
count="$(printf '%s\n' "$serials" | grep -c .)"

if [ "$count" -eq 0 ]; then
  log "no device in the 'device' state; adb sees:"
  "$ADB_BIN" devices -l >&2
  exit 1
fi

if [ -n "${ANDROID_SERIAL:-}" ]; then
  if printf '%s\n' "$serials" | grep -Fxq "$ANDROID_SERIAL"; then
    log "honouring ANDROID_SERIAL=$ANDROID_SERIAL"
    printf '%s\n' "$ANDROID_SERIAL"
    exit 0
  fi
  log "ANDROID_SERIAL=$ANDROID_SERIAL is not attached; unset it or correct it"
  printf '%s\n' "$serials" | sed 's/^/  attached: /' >&2
  exit 3
fi

if [ "$count" -eq 1 ]; then
  if ! usable "$serials"; then
    log "the only attached transport '$serials' is not usable"
    "$ADB_BIN" devices -l >&2
    exit 3
  fi
  printf '%s\n' "$serials"
  exit 0
fi

# identity <TAB> kind <TAB> rank <TAB> serial
table="$(mktemp "${TMPDIR:-/tmp}/adb_target.XXXXXX")"
trap 'rm -f "$table"' EXIT

while IFS= read -r line; do
  [ -n "$line" ] || continue
  printf '%s\t%s\t%s\t%s\n' \
    "$(hardware_identity "$line")" "$(kind_of "$line")" "$(rank_of "$line")" "$line" >> "$table"
done <<EOF
$serials
EOF

if [ "$VERBOSE" = 1 ]; then
  log "candidate transports (identity / kind / rank / serial):"
  awk -F'\t' '{ printf "  %s  %s  [rank %s]  %s\n", $1, $2, $3, $4 }' "$table" >&2
fi

devices="$(cut -f1 "$table" | sort -u | grep -c .)"
handsets="$(awk -F'\t' '$2 == "physical" { print $1 }' "$table" | sort -u | grep -c .)"

target_id=""
if [ "$handsets" -eq 1 ]; then
  target_id="$(awk -F'\t' '$2 == "physical" { print $1 }' "$table" | sort -u)"
  if [ "$devices" -gt 1 ]; then
    log "preferring physical device $target_id; set ANDROID_SERIAL to override"
  fi
elif [ "$devices" -eq 1 ]; then
  target_id="$(cut -f1 "$table" | sort -u)"
fi

if [ -z "$target_id" ]; then
  log "several candidate devices are attached; export ANDROID_SERIAL to pick one:"
  awk -F'\t' '{ printf "  %-14s %-9s %s\n", $1, $2, $4 }' "$table" >&2
  exit 2
fi

chosen=""
while IFS= read -r line; do
  serial="$(printf '%s' "$line" | cut -f4)"
  if usable "$serial"; then chosen="$serial"; break; fi
  log "skipping unusable transport: $serial"
done <<EOF
$(awk -F'\t' -v id="$target_id" '$1 == id' "$table" | sort -k3,3n)
EOF

if [ -z "$chosen" ]; then
  log "none of the transports of device $target_id is usable"
  "$ADB_BIN" devices -l >&2
  exit 3
fi

if [ "$VERBOSE" = 1 ]; then
  log "target device: $chosen"
fi

printf '%s\n' "$chosen"
exit 0
