#!/usr/bin/env bash

#
# phpmyadmin functions
#
# (c) 2008-2017, Hetzner Online GmbH
#

randomize_phpmyadmin_mysql_password() {
  local new_phpmyadmin_mysql_password="$(generate_password)"
  local phpmyadmin_dbconfig="$FOLD/hdd/etc/dbconfig-common/phpmyadmin.conf"
  debug '# randomize phpmyadmin mysql password'
  set_mysql_password phpmyadmin "$new_phpmyadmin_mysql_password" || return 1
  grep -q '^ *dbc_dbpass *=.*$' "$phpmyadmin_dbconfig" || return 1
  sed -i "s/^ *dbc_dbpass *=.*$/dbc_dbpass='$new_phpmyadmin_mysql_password'/g" "$phpmyadmin_dbconfig" || return 1
  if installed_os_uses_systemd && ! systemd_nspawn_booted; then
    boot_systemd_nspawn || return 1
  fi
  execute_command dpkg-reconfigure -f noninteractive phpmyadmin || return 1
  local phpmyadmin_mysql_password_from_debconf="$(echo 'get phpmyadmin/mysql/app-pass' | execute_command_wo_debug debconf-communicate -f noninteractive)"
  if [[ "$phpmyadmin_mysql_password_from_debconf" == "0 $new_phpmyadmin_mysql_password" ]]; then
    :
  elif [[ "$phpmyadmin_mysql_password_from_debconf" == '0 ' ]]; then
    :
  else
    return 1
  fi
  grep -q "^ *\$dbpass *=.*$new_phpmyadmin_mysql_password.*$" "$FOLD/hdd/etc/phpmyadmin/config-db.php"
}

randomize_phpmyadmin_blowfish_secret() {
  local phpmyadmin_blowfish_secret_file="$FOLD/hdd/var/lib/phpmyadmin/blowfish_secret.inc.php"
  local new_phpmyadmin_blowfish_secret="$(generate_random_string 32)"
  debug '# randomize phpmyadmin blowfish secret'
  grep -q "^ *\$cfg\['blowfish_secret'\]  *= .*" "$phpmyadmin_blowfish_secret_file" || return 1
  sed -i "s/^ *\$cfg\['blowfish_secret'\]  *= .*/\$cfg['blowfish_secret'] = '$new_phpmyadmin_blowfish_secret';/g" "$phpmyadmin_blowfish_secret_file"
}

setup_phpmyadmin() {
  debug '# setup phpmyadmin'
  randomize_phpmyadmin_mysql_password || return 1
  randomize_phpmyadmin_blowfish_secret
}

# vim: ai:ts=2:sw=2:et
