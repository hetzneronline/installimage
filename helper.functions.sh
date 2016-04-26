#!/usr/bin/env bash

#
# helper functions
#
# (c) 2016, Hetzner Online GmbH
#

# chroot_mktemp() <options>
# create a temp file within the installed system
# $@ <options>
chroot_mktemp() {
  local options="${*}"
  local temp_file; temp_file="$(execute_chroot_command_wo_debug "TMPDIR=/ mktemp ${options}")"
  TEMP_FILES+=("${FOLD}/hdd/${temp_file}")
  echo "${temp_file}"
}

# generate_password() <length>
# generates a password
# $1 <length> default: 16
generate_password() {
  local length="${1:-16}"
  local password=''
  # ensure that the password contains at least one lower case letter, an upper
  # case letter and a number
  until echo "${password}" | grep "[[:lower:]]" | grep "[[:upper:]]" | grep --quiet "[[:digit:]]"; do
    password="$(tr --complement --delete '[:alnum:][:digit:]' < /dev/urandom | head --bytes "${length}")"
  done
  echo "${password}"
}

execute_command() {
  if is_systemd_system; then
    execute_nspawn_command "${@}"
  else
    execute_chroot_command "${@}"
  fi
}

# vim: ai:ts=2:sw=2:et
