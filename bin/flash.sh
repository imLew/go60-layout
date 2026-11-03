#!/usr/bin/env bash
#
# flash-zmk.sh - wait for a ZMK split keyboard half in UF2 bootloader mode and
# flash it. Halves are identified by the bootloader volume label. Runs in a
# loop so you can do both halves in either order, and exits as soon as the
# LEFT half has been flashed.
#
# Usage: flash.sh --source local|gh
#   local  flash the locally built firmware (./combined/go60.uf2)
#   gh     download the firmware from the latest successful GitHub Actions
#          "Build" run on the current branch (falls back to main) and flash it

set -uo pipefail

##### ---- configure me ------------------------------------------------------

LOCAL_UF2=./combined/go60.uf2     # --source local
GH_WORKFLOW=build.yml             # --source gh: workflow that builds the firmware
GH_ARTIFACT=go60.uf2              # --source gh: artifact (and file) name
GH_FALLBACK_BRANCH=main           # --source gh: used if the current branch has no successful run
WORK_DIR=./firmwares              # scratch dir holding the file that gets flashed
FIRMWARE_UF2=$WORK_DIR/go60.uf2

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

usage() {
  printf 'usage: %s --source local|gh\n' "${0##*/}" >&2
  exit 2
}

SOURCE=""
while (($#)); do
  case $1 in
  --source)
    [[ $# -ge 2 ]] || usage
    SOURCE=$2
    shift 2
    ;;
  --source=*)
    SOURCE=${1#--source=}
    shift
    ;;
  -h | --help) usage ;;
  *) usage ;;
  esac
done
case $SOURCE in
local | gh) ;;
*) usage ;;
esac

fetch_local() {
  [[ -f $LOCAL_UF2 ]] || die "no such file: $LOCAL_UF2 (run 'make compile' first)"
  cp -- "$LOCAL_UF2" "$FIRMWARE_UF2"
  chmod u+w "$FIRMWARE_UF2"
}

fetch_gh() {
  local branch run_id
  command -v gh >/dev/null || die "gh not found"
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  run_id=""
  for b in "$branch" "$GH_FALLBACK_BRANCH"; do
    [[ -n $b && $b != HEAD ]] || continue
    run_id=$(gh run list --workflow "$GH_WORKFLOW" --branch "$b" --status success \
      --limit 1 --json databaseId --jq '.[0].databaseId // empty') || die "gh run list failed"
    if [[ -n $run_id ]]; then
      printf '>> Downloading %s from run %s (branch %s)\n' "$GH_ARTIFACT" "$run_id" "$b"
      break
    fi
  done
  [[ -n $run_id ]] || die "no successful $GH_WORKFLOW run found"
  rm -rf -- "$WORK_DIR/gh-download"
  gh run download "$run_id" --name "$GH_ARTIFACT" --dir "$WORK_DIR/gh-download" ||
    die "download failed"
  mv -- "$WORK_DIR/gh-download/$GH_ARTIFACT" "$FIRMWARE_UF2" || die "artifact missing $GH_ARTIFACT"
  rm -rf -- "$WORK_DIR/gh-download"
}

mkdir -p "$WORK_DIR"
"fetch_$SOURCE"
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

rm -f -- "$FIRMWARE_UF2"
