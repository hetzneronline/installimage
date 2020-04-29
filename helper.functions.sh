#!/usr/bin/env bash

#
# helper functions
#
# (c) 2016-2018, Hetzner Online GmbH
#

execute_command_wo_debug() {
  if installed_os_uses_systemd; then
    systemd_nspawn_wo_debug "$@"
    return $?
  fi
  execute_chroot_command_wo_debug "$@"
}

execute_command() {
  if installed_os_uses_systemd; then
    systemd_nspawn "$@"
    return $?
  fi
  execute_chroot_command "$@"
}

grub_install_devices() {
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    [[ "$SWRAID" == '0' ]] && ((i != 1)) && continue
    eval echo "\$DRIVE$i"
  done
}

# Hetzner images come with an empty resume file
disable_resume() {
  if [[ -s "$FOLD/hdd/etc/initramfs-tools/conf.d/resume" ]]; then
    debug '# disable resume'
    echo 'RESUME=none' > "$FOLD/hdd/etc/initramfs-tools/conf.d/resume"
    return 0
  fi
  debug '# not disabling resume, /etc/initramfs-tools/conf.d/resume not empty'
}

# vim: ai:ts=2:sw=2:et
