#!/usr/bin/env bash

#
# chroot functions
#
# (c) 2007-2023, Hetzner Online GmbH
#

execute_chroot_command_wo_debug() {
  local dirs=(/{dev,dev/pts,dev/shm,proc,run,sys})
  for dir in "${dirs[@]}"; do
    mkdir -p "$FOLD/hdd/$dir"
    mount --bind "$dir" "$FOLD/hdd/$dir"
  done
  TMPDIR= unshare -f -p chroot "$FOLD/hdd" /usr/bin/env bash -c "$@"
  local r=$?
  for ((i=${#dirs[@]}-1; i>=0; i--)); do
    until umount -fl "$FOLD/hdd/${dirs[i]}"; do :; done
  done
  return $r
}

execute_chroot_command() {
  debug "# chroot: $*"
  execute_chroot_command_wo_debug "$@" |& debugoutput
  return "${PIPESTATUS[0]}"
}

# vim: ai:ts=2:sw=2:et
