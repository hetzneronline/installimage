#!/usr/bin/env bash

#
# mysql functions
#
# (c) 2016-2021, Hetzner Online GmbH
#

mysql_running() { execute_command_wo_debug mysqladmin ping &> /dev/null; }

start_mysql() {
  if installed_os_uses_systemd; then
    if ! systemd_nspawn_booted; then
      boot_systemd_nspawn || return 1
    fi
    systemd_nspawn_wo_debug systemctl start mysql &> /dev/null || return 1
  else
    execute_chroot_command_wo_debug service mysql start &> /dev/null || return 1
  fi
  until mysql_running; do :; done
}

stop_mysql() {
  start_mysql || return 1
  if installed_os_uses_systemd; then
    systemd_nspawn_wo_debug systemctl stop mysql &> /dev/null || return 1
  else
    execute_chroot_command_wo_debug service mysql stop &> /dev/null || return 1
  fi
  while mysql_running; do :; done
}

query_mysql() {
  if ! mysql_running; then
    start_mysql || return 1
  fi
  echo "$@" | execute_command_wo_debug mysql -N
  return "${PIPESTATUS[1]}"
}

mysql_version() {
  # shellcheck disable=SC1001
  [[ "$(query_mysql 'SELECT VERSION();')" =~ ^([0-9]*\.[0-9]*\.[0-9]*)\- ]] && echo "${BASH_REMATCH[1]}"
}

mysql_version_ge() {
  local other="$1"
  [[ "$(echo -e "$(mysql_version)\n$other" | sort -V | head -n 1)" == "$other" ]]
}

set_mysql_password() {
  local user="$1"
  local password="$2"
  if mysql_version_ge 5.7.6; then
    if ! [[ "$(query_mysql "SELECT plugin FROM mysql.user WHERE user = '${user//\'/\\\'}';")" =~ ^mysql_native_password$|^unix_socket$|^auth_socket$ ]]; then
      local password_field='password'
    else
      local password_field='authentication_string'
    fi
  else
    local password_field='password'
  fi
  query_mysql "UPDATE mysql.user SET password_last_changed = NOW() WHERE user = '${user//\'/\\\'}';" &> /dev/null
  query_mysql "UPDATE mysql.user SET $password_field = PASSWORD('${password//\'/\\\'}') WHERE user = '${user//\'/\\\'}';" |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) || return 1
  query_mysql 'FLUSH PRIVILEGES;' |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) || return 1
  echo QUIT | execute_command_wo_debug mysql -u "$user" -p"$password" |& debugoutput
  return "${PIPESTATUS[1]}"
}

reset_mysql_root_password() {
  local new_root_password="$1"
  if ! mysql_running; then
    start_mysql || return 1
  fi
  stop_mysql || return 1
  execute_command_wo_debug mkdir -p /var/run/mysqld || return 1
  execute_command_wo_debug chown mysql:mysql /var/run/mysqld || return 1

  # work around INSTALL PLUGIN ERROR 1030 (HY000) at line 1: Got error 1 from storage engine
  execute_command_wo_debug 'mysqld_safe --skip-grant-tables &> /dev/null &'
  until mysql_running; do :; done
  local add_args
  if [[ "$(query_mysql "SELECT plugin FROM mysql.user WHERE user = 'root';")" =~ ^auth_socket$ ]]; then
    if ! query_mysql 'SHOW PLUGINS' | grep -q '^auth_socket[[:space:]]'; then
      add_args+=' --plugin-load-add=auth_socket.so'
    fi
  fi
  execute_command_wo_debug mysqladmin shutdown &> /dev/null || return 1
  while mysql_running; do :; done

  execute_command_wo_debug "mysqld_safe --skip-grant-tables $add_args &> /dev/null &"
  until mysql_running; do :; done
  set_mysql_password root "$new_root_password" || return 1
  {
    echo '[client]'
    echo 'user=root'
    echo "password=$new_root_password"
  } > "$FOLD/hdd/root/.my.cnf"
  query_mysql QUIT || return 1
  execute_command_wo_debug mysqladmin shutdown &> /dev/null || return 1
  while mysql_running; do :; done
}

mysql_user_exists() {
  local mysql_user="$1"
  [[ "$(query_mysql "SELECT COUNT(*) FROM mysql.user WHERE user = '${mysql_user//\'/\\\'}';")" == '0' ]] && return 1
  return
}

create_mysql_user() {
  local user="$1"
  local password="$2"
  query_mysql "CREATE USER '${user//\'/\\\'}'@'localhost' IDENTIFIED BY '${password//\'/\\\'}';" |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) || return 1
  query_mysql "GRANT ALL ON *.* TO '${user//\'/\\\'}'@'localhost' WITH GRANT OPTION;" |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) || return 1
  query_mysql "FLUSH PRIVILEGES;" |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) || return 1
  echo QUIT | execute_command_wo_debug mysql -u "$user" -p"$password" |& debugoutput
  return "${PIPESTATUS[1]}"
}

# vim: ai:ts=2:sw=2:et
