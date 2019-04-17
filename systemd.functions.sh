#!/usr/bin/env bash

#
# systemd functions
#
# (c) 2017-2018, Hetzner Online GmbH
#

# get installed os systemd version
installed_os_systemd_version() {
  # does not work for centos: Failed to get D-Bus connection: Operation not permitted
  # [[ "$(execute_chroot_command_wo_debug 'systemctl show --property=Version')" =~ ^Version=([0-9]+)$ ]] && echo "${BASH_REMATCH[1]}"
  [[ "$(execute_chroot_command_wo_debug 'systemctl --version')" =~ systemd\ ([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
}

# check whether installed os uses systemd
installed_os_uses_systemd() {
  installed_os_systemd_version &> /dev/null
}

# vim: ai:ts=2:sw=2:et
