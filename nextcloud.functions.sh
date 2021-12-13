#!/usr/bin/env bash

#
# nextcloud functions
#
# (c) 2017-2021, Hetzner Online GmbH
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
  local i="$2"
  if [[ -n "$i" ]]; then
    occ config:system:get "$config_parameter" "$i"
  else
    occ config:system:get "$config_parameter"
  fi
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
  local i="$2"
  local value="$3"
  if [[ -z "$value" ]]; then
    value="$i"
    i=
  fi
  if [[ -n "$i" ]]; then
    occ config:system:set "$config_parameter" "$i" --value "$value" &> /dev/null
  else
    occ config:system:set "$config_parameter" --value "$value" &> /dev/null
  fi
  [[ "$(get_nextcloud_config_parameter "$config_parameter" "$i")" == "$value" ]]
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

add_ips_to_trusted_domains() {
  debug '# add ips to trusted domains'
  i=0
  while read d; do
    ipv6_addr_is_link_local_unicast_addr "$d" && continue
    [[ "$d" =~ : ]] && d="[$d]"
    echo "add trusted_domain $d" | debugoutput
    set_nextcloud_config_parameter trusted_domains "$i" "$d" < /dev/null || return 1
    ((i+=1))
  done < <(ip -j a s | jq -r '.[].addr_info[].local')
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
  randomize_nextcloud_secret || return 1
  execute_command_wo_debug chown -R www-data:www-data /var/www/nextcloud || return 1
  # trusted_domains * does not match ipv6 addrs
  add_ips_to_trusted_domains
}

# vim: ai:ts=2:sw=2:et
