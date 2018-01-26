#!/usr/bin/env bash

#
# nextcloud functions
#
# (c) 2017, Hetzner Online GmbH
#

nextcloud_install() { [[ "${IMAGENAME,,}" =~ nextcloud$|nextcloud-beta$ ]]; }

update_nextcloud_activity_table_timestamps() {
  debug '# update nextcloud activity table timestamps'
  query_mysql 'UPDATE nextcloud.oc_activity SET timestamp = UNIX_TIMESTAMP();'
}

nextcloud_datadirectory() { get_nextcloud_config_parameter datadirectory; }

occ() {
  if installed_os_uses_systemd && ! systemd_nspawn_booted; then
    boot_systemd_nspawn || return 1
  fi
  if ! mysql_running; then start_mysql || return 1; fi
  execute_command_wo_debug sudo -u www-data OC_PASS="$OC_PASS" php /var/www/nextcloud/occ "$@"
}

update_nextcloud_datadirectory_timestamps() {
  local datadirectory="$FOLD/hdd/$(nextcloud_datadirectory)"
  debug '# update nextcloud datadirectory timestamps'
  [[ -e "$datadirectory" ]] || return 1
  find "$datadirectory" -exec touch {} \;
  occ files:scan --all &> /dev/null
}

get_nextcloud_config_parameter() {
  local config_parameter="$1"
  occ config:system:get "$config_parameter"
}

randomize_nextcloud_mysql_password() {
  local new_nextcloud_mysql_password="$(generate_password)"
  debug '# randomize nextcloud mysql password'
  occ config:system:set dbpassword --value "$new_nextcloud_mysql_password" &> /dev/null
  set_mysql_password nextcloud "$new_nextcloud_mysql_password" || return 1
  [[ "$(get_nextcloud_config_parameter dbpassword)" == "$new_nextcloud_mysql_password" ]]
}

nextcloud_root_password_hash() {
  query_mysql "SELECT password FROM nextcloud.oc_users WHERE uid = 'root';";
}

randomize_nextcloud_root_password() {
  local new_root_password="$(generate_password)"
  local old_root_password_hash="$(nextcloud_root_password_hash)"
  debug '# randomize nextcloud root password'
  OC_PASS="$new_root_password" occ user:resetpassword --password-from-env root &> /dev/null
  [[ "$(nextcloud_root_password_hash)" == "$old_root_password_hash" ]] && return 1
  echo "Nextcloud root password: $new_root_password" >> "$FOLD/hdd/password.txt"
}

generate_nextcloud_instanceid() { echo "oc$(generate_random_string 10)"; }

set_nextcloud_config_parameter() {
  local config_parameter="$1"
  local value="$2"
  occ config:system:set "$config_parameter" --value "$value" &> /dev/null
  [[ "$(get_nextcloud_config_parameter "$config_parameter")" == "$value" ]]
}

randomize_nextcloud_instanceid() {
  local old_instanceid="$(get_nextcloud_config_parameter instanceid)"
  local new_instanceid="$(generate_nextcloud_instanceid)"
  local datadirectory="$FOLD/hdd/$(nextcloud_datadirectory)"
  debug '# randomize nextcloud instanceid'
  set_nextcloud_config_parameter instanceid "$new_instanceid" || return 1
  if [[ -e "$datadirectory/appdata_$old_instanceid" ]]; then
    mv "$datadirectory/appdata_"{"$old_instanceid","$new_instanceid"} || return 1
  fi
  return 0
}

randomize_nextcloud_passwordsalt() {
  local new_passwordsalt="$(generate_random_string 30)"
  debug '# randomize nextcloud passwordsalt'
  set_nextcloud_config_parameter passwordsalt "$new_passwordsalt"
}

randomize_nextcloud_secret() {
  local new_secret="$(generate_random_string 48)"
  debug '# randomize nextcloud secret'
  set_nextcloud_config_parameter secret "$new_secret"
}

setup_nextcloud() {
  debug '# setup nextcloud'
  setup_lamp || return 1
  update_nextcloud_activity_table_timestamps || return 1
  update_nextcloud_datadirectory_timestamps || return 1
  randomize_nextcloud_mysql_password || return 1
  randomize_nextcloud_root_password || return 1
  randomize_nextcloud_instanceid || return 1
  randomize_nextcloud_passwordsalt || return 1
  randomize_nextcloud_secret
  execute_command_wo_debug chown -R www-data:www-data /var/www/nextcloud
}

# vim: ai:ts=2:sw=2:et
