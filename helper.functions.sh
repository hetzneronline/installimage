#!/usr/bin/env bash

#
# helper functions
#
# (c) 2016-2017, Hetzner Online GmbH
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

# vim: ai:ts=2:sw=2:et
