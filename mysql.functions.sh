#!/usr/bin/env bash

#
# mysql functions
#
# (c) 2016, Hetzner Online GmbH
#

# mysql_is_running()
# checks whether mysql is running
mysql_is_running() {
  if is_systemd_system; then
    systemd_nspawn_container_is_running || return 1
    execute_nspawn_command 'systemctl --quiet is-active mysql' no > /dev/null || return 1
  else
    execute_chroot_command_wo_debug '/etc/init.d/mysql status' &> /dev/null || return 1
  fi
}

# ping_mysql() <max_checks>
# shellcheck disable=SC2120
ping_mysql() {
  local max_checks=${1:-30}
  for ((check=1; check<=max_checks; check++)); do
    execute_chroot_command_wo_debug 'mysqladmin ping' &> /dev/null && break
    (( check == max_checks )) && return 1
    sleep 1
  done
}

# start_mysql()
# starts mysql
start_mysql() {
  debug '# starting mysql'
  if mysql_is_running; then
    debug 'mysql is already running'
    return 0
  fi
  if is_systemd_system; then
    execute_nspawn_command 'systemctl start mysql' > /dev/null || return 1
    # execute_nspawn_command 'systemctl status mysql' > /dev/null
  else
    execute_chroot_command '/etc/init.d/mysql start' || return 1
    # execute_chroot_command '/etc/init.d/mysql status'
  fi
  # shellcheck disable=SC2119
  ping_mysql || return 1
  debug 'started mysql'
}

# stop_mysql()
stop_mysql() {
  debug '# stopping mysql'
  if ! mysql_is_running; then
    debug 'mysql is not running'
    return 0
  fi
  if is_systemd_system; then
    execute_nspawn_command 'systemctl stop mysql' > /dev/null || return 1
    # execute_nspawn_command 'systemctl status mysql' > /dev/null
  else
    execute_chroot_command '/etc/init.d/mysql stop' || return 1
    # execute_chroot_command '/etc/init.d/mysql status'
  fi
  debug 'stopped mysql'
}

# execute_mysql_command() <command> <user> <password>
# executes a mysql command
# $1 <command>  the command to execute
# for convenience, the command can also be passed via stdin
# $2 <user>     optional
# $3 <password> optional
execute_mysql_command() {
  local command="${1}"
  local user="${2}"
  local password="${3}"
  # merge stdin
  [[ -t 0 ]] || command+="$(cat)"
  local temp_file; temp_file=$(chroot_mktemp)

  # shellcheck disable=SC2119
  ping_mysql || return 1
  echo "${command}" > "${FOLD}/hdd/${temp_file}"
  if ! mysql_is_running; then start_mysql || return 1; fi
  {
    echo -n 'mysql '
    [[ -n "${user}" ]] && echo -n "--user='${user}' "
    [[ -n "${password}" ]] && echo -n "--password='${password}'"
    echo
  } | execute_chroot_command_wo_debug "cat ${temp_file} | $(cat)" &> /dev/null || return 1
}

# check_mysql_password() <user> <password>
# $1 <user>
# $2 <password>
check_mysql_password() {
  local user="${1}"
  local password="${2}"

  debug "# checking mysql password for ${user}"
  execute_mysql_command "QUIT" "${user}" "${password}" || return 1
  debug "OK"
}

# # reset_mysql_password() <user> <new_password>
# # $1 <user>
# # $2 <new_password>
reset_mysql_password() {
  local user="${1}"
  local new_password="${2}"
  local config_file=
  local config_files=(
    ${FOLD}/hdd/etc/my.cnf
    ${FOLD}/hdd/etc/mysql/my.cnf
    ${FOLD}/hdd/usr/etc/my.cnf
  )
  local temp_file; temp_file="${FOLD}/hdd/$(chroot_mktemp)"
  local init_file; init_file="$(chroot_mktemp)"
  local installimage_config_file; installimage_config_file=$(chroot_mktemp)

  debug "# resetting mysql password for ${user}"

  for file in "${config_files[@]}"; do
    if [[ -f "${file}" ]]; then
      config_file=${file}
      break
    fi
  done
  [[ -f "${config_file}" ]] || return 1

  mv "${config_file}" "${temp_file}"
  cp "${temp_file}" "${config_file}"

  {
    echo
    echo "### ${COMPANY} installimage"
    echo "!include ${installimage_config_file}"
  } >> "${config_file}"

  {
    echo "### ${COMPANY} installimage"
    echo 'USE mysql;'
    echo "UPDATE user SET password=PASSWORD('${new_password}') WHERE user='${user}';"
    echo 'FLUSH PRIVILEGES;'
  } > "${FOLD}/hdd/${init_file}"

  {
    echo "### ${COMPANY} installimage"
    echo '[mysqld]'
    echo "init-file = ${init_file}"
  } > "${FOLD}/hdd/${installimage_config_file}"

  chmod 644 "${FOLD}/hdd/${init_file}" "${FOLD}/hdd/${installimage_config_file}"

  if mysql_is_running; then stop_mysql || return 1; fi
  start_mysql || return 1

  check_mysql_password "${user}" "${new_password}" || return 1

  mv "${temp_file}" "${config_file}"

  debug "reset mysql password for ${user}"
}

# generate_my_cnf() <user> <password>
# $1 <user>
# $2 <password>
generate_my_cnf() {
  local user="${1}"
  local password="${2}"

  echo '[client]'
  echo "user=${user}"
  echo "password=${password}"
}

# set_mysql_password() <user> <new_password>
# $1 <user>
# $2 <new_password>
set_mysql_password() {
  local user="${1}"
  local new_password="${2}"

  debug "# setting mysql password for ${user}"
  {
    echo 'USE mysql;'
    echo "UPDATE user SET password=PASSWORD('${new_password}') WHERE user='${user}';"
    echo 'FLUSH PRIVILEGES;'
  } | execute_mysql_command || return 1
  check_mysql_password "${user}" "${new_password}" || return 1
  debug "set mysql password for ${user}"
}

# vim: ai:ts=2:sw=2:et
