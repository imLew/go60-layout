#!/usr/bin/env bash
#
# flash-zmk.sh - wait for a ZMK split keyboard half in UF2 bootloader mode and
# flash it. Halves are identified by the bootloader volume label. Runs in a
# loop so you can do both halves in either order, and exits as soon as the
# LEFT half has been flashed.

set -uo pipefail

##### ---- configure me ------------------------------------------------------

FIRMWARE_UF2=./firmwares/go60.uf2

# Bootloader volume labels, one per half. See `lsblk -o NAME,LABEL` with a
# half plugged in and in bootloader mode. These must be different from each
# other or the script cannot tell the halves apart.
LEFT_LABEL="GO60LHBOOT"
RIGHT_LABEL="GO60RHBOOT"

POLL=0.5             # seconds between polls
DISAPPEAR_TIMEOUT=60 # how long to wait for a board to reboot after flashing

##### -------------------------------------------------------------------------

MNT=""
MNT_MANUAL=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -n $FIRMWARE_UF2 ]] || die "set FIRMWARE_UF2 at the top of this script"
[[ -f $FIRMWARE_UF2 ]] || die "no such file: $FIRMWARE_UF2"
[[ $LEFT_LABEL != "$RIGHT_LABEL" ]] || die "LEFT_LABEL and RIGHT_LABEL are identical - the halves cannot be told apart by label"
command -v lsblk >/dev/null || die "lsblk not found"
command -v findmnt >/dev/null || die "findmnt not found"

# Print "<devnode> <label>" for the first partition matching either label.
find_bootloader() {
  local name label
  while read -r name label; do
    case $label in
    "$LEFT_LABEL" | "$RIGHT_LABEL")
      printf '/dev/%s %s\n' "$name" "$label"
      return 0
      ;;
    esac
  done < <(lsblk -rno NAME,LABEL 2>/dev/null)
  return 1
}

# Block until a matching device shows up, then print "<devnode> <label>".
wait_for_bootloader() {
  local found
  until found=$(find_bootloader); do
    sleep "$POLL"
  done
  sleep 1 # let udev / the desktop automounter settle
  printf '%s\n' "$found"
}

# Sets MNT (and MNT_MANUAL=1 if we did the mounting ourselves).
ensure_mounted() {
  local dev=$1
  MNT_MANUAL=0
  MNT=$(findmnt -nfro TARGET -S "$dev" 2>/dev/null || true)
  [[ -n $MNT ]] && return 0

  if command -v udisksctl >/dev/null 2>&1; then
    udisksctl mount -b "$dev" >/dev/null 2>&1 || true
    MNT=$(findmnt -nfro TARGET -S "$dev" 2>/dev/null || true)
    [[ -n $MNT ]] && return 0
  fi

  return 1
}

flash_half() {
  local dev=$1 side=$2 deadline

  ensure_mounted "$dev" || die "could not mount $dev"
  printf '   mounted at %s, copying %s\n' "$MNT" "${FIRMWARE_UF2##*/}"

  # The board reboots the instant the UF2 lands, so I/O errors here are normal.
  cp -- "$FIRMWARE_UF2" "$MNT/"

  printf '   waiting for the %s half to reboot...\n' "$side"
  deadline=$((SECONDS + DISAPPEAR_TIMEOUT))
  while [[ -e $dev ]]; do
    if ((SECONDS > deadline)); then
      printf '   still present after %ss - unplug it before continuing\n' "$DISAPPEAR_TIMEOUT"
      break
    fi
    sleep "$POLL"
  done

  printf '>> %s half flashed.\n\n' "$side"
}

while true; do
  printf '>> Waiting for a half in bootloader mode (double-tap reset)...\n'
  read -r dev label < <(wait_for_bootloader)

  if [[ $label == "$LEFT_LABEL" ]]; then
    side="LEFT"
  else
    side="RIGHT"
  fi
  printf '   found %s half at %s (label %s)\n' "$side" "$dev" "$label"

  flash_half "$dev" "$side"

  if [[ $side == "LEFT" ]]; then
    printf 'Left half flashed - done.\n'
    break
  fi
done

rm firmwares/go60.uf2
