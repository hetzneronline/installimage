#!/usr/bin/env bash

#
# lamp functions
#
# (c) 2008-2016, Hetzner Online GmbH
#

# is_lamp_install()
# is this a lamp install?
is_lamp_install() {
  [[ "${IMAGENAME,,}" == *lamp ]]
}

# setup_password_txt()
setup_password_txt() {
  local password_txt='/password.txt'
  local password_note_file="/etc/profile.d/99-$C_SHORT.sh"
  local erase_password_note_script='/usr/local/bin/erase_password_note'

  cat > "${FOLD}/hdd/${password_txt}"
  chmod 600 "${FOLD}/hdd/${password_txt}"

  {
    echo '#!/usr/bin/env bash'
    echo "### ${COMPANY} installimage"
    echo 'echo'
    echo "echo -e '\e[1;32mYour database passwords were stored in ${password_txt}. Run erase_password_note in order to remove this note.\e[0m'"
    echo 'echo'
  } > "${FOLD}/hdd/${password_note_file}"
  chmod 755 "${FOLD}/hdd/${password_note_file}"

  {
    echo '#!/usr/bin/env bash'
    echo "### ${COMPANY} installimage"
    echo "rm -f ${password_note_file} ${erase_password_note_script}"
  } > "${FOLD}/hdd/${erase_password_note_script}"
  chmod 755 "${FOLD}/hdd/${erase_password_note_script}"
}

# randomize_lamp_passwords()
randomize_lamp_passwords() {
  debug '# randomizing LAMP passwords'

  # passwords of the following database users must be randomized
  # * root
  # * debian-sys-maint
  # * phpmyadmin

  # generate passwords
  local root_password; root_password="$(generate_password)"
  local debian_sys_maint_password; debian_sys_maint_password="$(generate_password)"
  local phpmyadmin_password; phpmyadmin_password="$(generate_password)"

  # reset root password
  reset_mysql_password root "${root_password}" || return 1

  # generate .my.cnf
  generate_my_cnf root "${root_password}" > "${FOLD}/hdd/root/.my.cnf"

  # set passwords
  set_mysql_password debian-sys-maint "${debian_sys_maint_password}" || return 1
  set_mysql_password phpmyadmin "${phpmyadmin_password}" || return 1

  debug '# setting up config files'

  # set debian-sys-maint password in debian.cnf
  local mysql_debian_cnf_file="${FOLD}/hdd/etc/mysql/debian.cnf"
  safe_replace \
    "^password = .+$" \
    "password = ${debian_sys_maint_password}" \
    "${mysql_debian_cnf_file}" \
    || return 1

  # set phpmyadmin password in phpmyadmin.conf
  local phpmyadmin_dbconfig_file="${FOLD}/hdd/etc/dbconfig-common/phpmyadmin.conf"
  safe_replace \
    "^dbc_dbpass='[^']*'$" \
    "dbc_dbpass='${phpmyadmin_password}'" \
    "${phpmyadmin_dbconfig_file}" \
    || return 1

  # reconfiguring phpmyadmin should write /etc/phpmyadmin/config-db.php
  local phpmyadmin_config_db_file="${FOLD}/hdd/etc/phpmyadmin/config-db.php"
  # empty config-db.php
  echo -n > "${phpmyadmin_config_db_file}"
  execute_command 'dpkg-reconfigure --frontend noninteractive phpmyadmin' || return 1
  # check if config-db.php has been refilled
  [[ -s "${phpmyadmin_config_db_file}" ]] && return 1

  debug 'set up config files'

  # IPADDR or <your-servers-IP>
  local host="${IPADDR:-<your-servers-IP>}"
  {
    echo "### ${COMPANY} installimage"
    echo
    echo "Webmin URL:     https://${host}:10000/"
    echo "phpMyAdmin URL: http://${host}/phpmyadmin/"
    echo
    echo "MySQL root password: ${root_password}"
  } | setup_password_txt

  debug 'randomized LAMP passwords'
}

# randomize_lamp_secrets()
randomize_lamp_secrets() {
  debug '# randomizing LAMP secrets'

  debug '# randomizing phpmyadmin blowfish secret'
  local phpmyadmin_blowfish_secret_file="${FOLD}/hdd/var/lib/phpmyadmin/blowfish_secret.inc.php"
  if [[ -f "${phpmyadmin_blowfish_secret_file}" ]]; then
    local phpmyadmin_blowfish_secret; phpmyadmin_blowfish_secret="$(generate_password 48)"
    safe_replace \
      "^\\\$cfg\['blowfish_secret'\] = '[^']*';$" \
      "\$cfg['blowfish_secret'] = '${phpmyadmin_blowfish_secret}';" \
      "${phpmyadmin_blowfish_secret_file}" \
      || return 1
    debug 'OK'
  else
    debug "WARN: ${phpmyadmin_blowfish_secret_file} does not exist"
  fi

  debug 'randomized LAMP secrets'
}

# setup_lamp()
setup_lamp() {
  debug '# setting up LAMP'
  randomize_lamp_secrets || return 1
  randomize_lamp_passwords || return 1
  debug 'set up LAMP'
}

# vim: ai:ts=2:sw=2:et
