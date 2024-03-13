#!/usr/bin/env bash

#
# cpanel functions
#
# (c) 2008-2024, Hetzner Online GmbH
#

# is_cpanel_install()
# is this a cpanel install?
is_cpanel_install() {
  [[ "${OPT_INSTALL,,}" == cpanel ]] || [[ "${IMAGENAME,,}" == *cpanel ]]
}

# cpanel_setup_mainip()
cpanel_setup_mainip() {
  local mainip_file=/var/cpanel/mainip

  local v4_main_ip
  v4_main_ip="$(v4_main_ip)"
  if [[ -n "$v4_main_ip" ]]; then
    debug "# setting up ${mainip_file}"
    echo -n "$(ip_addr_without_suffix "$v4_main_ip")" > "${FOLD}/hdd/${mainip_file}"
    return
  fi

  debug "fatal: no IPv4 main IP: not setting up $mainip_file"
  return 1
}

# cpanel_setup_wwwacct_conf()
cpanel_setup_wwwacct_conf() {
  local wwwacct_conf; wwwacct_conf=/etc/wwwacct.conf

  local v4_main_ip
  v4_main_ip="$(v4_main_ip)"
  if [[ -z "$v4_main_ip" ]]; then
    debug "fatal: no IPv4 main IP: can not set up $wwwacct_conf"
    return 1
  fi

  debug "# setting up ${wwwacct_conf}"

  sed --expression='/^ADDR\s/d' \
    --expression='/^HOST\s/d' \
    --expression='/^NS[[:digit:]]*\s/d' \
    --in-place "${FOLD}/hdd/${wwwacct_conf}"
  {
    echo
    echo "### ${COMPANY} installimage"
    echo "ADDR $(ip_addr_without_suffix "$v4_main_ip")"
    echo "HOST ${NEWHOSTNAME}"
    echo "NS ${AUTH_DNS1}"
    echo "NS2 ${AUTH_DNS2}"
    echo "NS3 ${AUTH_DNS3}"
    echo 'NS4'
  } >> "${FOLD}/hdd/${wwwacct_conf}"
}

# randomize_cpanel_passwords()
randomize_cpanel_passwords() {
  debug '# randomizing cpanel passwords'

  # passwords of the following database users must be randomized
  # * root
  # * cphulkd
  # * eximstats
  # * leechprotect
  # * modsec
  # * roundcube

  local root_password; root_password=$(generate_password)
  local cphulkd_password; cphulkd_password=$(generate_password)
  local eximstats_password; eximstats_password=$(generate_password)
  local leechprotect_password; leechprotect_password=$(generate_password)
  local roundcube_password; roundcube_password=$(generate_password)

  reset_mysql_root_password "$root_password" || return 1

  set_mysql_password cphulkd "${cphulkd_password}" || return 1
  set_mysql_password eximstats "${eximstats_password}" || return 1
  set_mysql_password leechprotect "${leechprotect_password}" || return 1
  set_mysql_password roundcube "${roundcube_password}" || return 1

  echo "${cphulkd_password}" > "${FOLD}/hdd/var/cpanel/hulkd/password"
  echo "${eximstats_password}" > "${FOLD}/hdd/var/cpanel/eximstatspass"
  echo "${leechprotect_password}" > "${FOLD}/hdd/var/cpanel/leechprotectpass"
  echo "${roundcube_password}" > "${FOLD}/hdd/var/cpanel/roundcubepass"

  systemd_nspawn /usr/local/cpanel/bin/updateeximstats || return 1
  systemd_nspawn /usr/local/cpanel/bin/updateleechprotect || return 1
  systemd_nspawn /usr/local/cpanel/bin/modsecpass || return 1
  systemd_nspawn /usr/local/cpanel/bin/update-roundcube --force || return 1

  poweroff_systemd_nspawn

  debug 'randomized cpanel passwords'
}

# setup_cpanel()
setup_cpanel() {
  debug '# setting up cpanel'
  cpanel_setup_mainip
  cpanel_setup_wwwacct_conf || return 1
  randomize_cpanel_passwords || return 1
  debug 'set up cpanel'
}

workaround_alma_linux_cpanel_missing_ea4_repo_issue() {
  debug '# workarounding cpanel EA4.repo missing issue'
  execute_chroot_command 'yum -y clean all' || return 1
  debug '# downloading https://securedownloads.cpanel.net/EA4/EA4.repo file'
  curl -L -o "$FOLD/hdd/etc/yum.repos.d/EA4.repo" -s https://securedownloads.cpanel.net/EA4/EA4.repo || return 1
  execute_chroot_command 'yum -y update' || return 1
  execute_chroot_command 'yum makecache'
}

prevent_outdated_keyring_issues() {
  execute_chroot_command 'yum -y clean all' || return 1
  execute_chroot_command 'yum -y update' || return 1
  execute_chroot_command 'yum makecache'
}

install_ubuntu_2004_cpanel_depenencies() {
  execute_chroot_command 'apt-get update' || return 1
  execute_chroot_command 'apt-get -y install dirmngr libfindbin-libs-perl' || return 1
}

# install_cpanel()
install_cpanel() {
  if [[ "$IAM" == 'almalinux' ]]; then
    if ((IMG_VERSION >= 80)); then
      workaround_alma_linux_cpanel_missing_ea4_repo_issue || return 1
    else
      prevent_outdated_keyring_issues || return 1
    fi
  fi

  local temp_file="/cpanel-installer"

  debug "# downloading cpanel installer ${CPANEL_INSTALLER_SRC}/${IMAGENAME}"
  curl --location --output "${FOLD}/hdd/${temp_file}" --silent --write-out '%{response_code}' "${CPANEL_INSTALLER_SRC}/${IMAGENAME}" \
    | grep --quiet 200 || return 1
  chmod a+x "${FOLD}/hdd/${temp_file}"
  debug 'downloaded cpanel installer'

  if rhel_based_image; then
    execute_chroot_command 'yum check-update' # || return 1
    execute_chroot_command 'yum -y install yum-utils' || return 1
  fi

  if [[ "$IAM" == 'ubuntu' ]] && (( IMG_VERSION == 2004 )); then
    install_ubuntu_2004_cpanel_depenencies || return 1
  fi

  if [[ -e "$FOLD/hdd/usr/bin/needs-restarting" ]]; then
    mv "$FOLD/hdd/usr/bin/needs-restarting" "$FOLD/hdd/usr/bin/needs-restarting.bak"
    {
      echo '#!/usr/bin/env bash'
      echo '/usr/bin/needs-restarting.bak | grep -v systemd_nspawn-runner'
    } > "$FOLD/hdd/usr/bin/needs-restarting"
    chmod 755 "$FOLD/hdd/usr/bin/needs-restarting"
  fi

  debug '# installing cpanel'
  local command="${temp_file} --force"
  if installed_os_uses_systemd && ! systemd_nspawn_booted; then
    boot_systemd_nspawn || return 1
  fi

  execute_command "${command}" || return 1
  systemd_nspawn_booted && poweroff_systemd_nspawn

  if [[ -e "$FOLD/hdd/usr/bin/needs-restarting.bak" ]]; then
    mv "$FOLD/hdd/usr/bin/needs-restarting.bak" "$FOLD/hdd/usr/bin/needs-restarting"
  fi

  debug '# setting up cpanel'
  cpanel_setup_wwwacct_conf || return 1
  debug 'set up cpanel'
  debug 'installed cpanel'
}

# vim: ai:ts=2:sw=2:et
