#!/usr/bin/env bash

#
# plesk functions
#
# (c) 2007-2016, Hetzner Online GmbH
#

# is_plesk_install()
# is this a plesk install?
is_plesk_install() {
  [[ "${OPT_INSTALL,,}" == plesk* ]]
}

# install_plesk() <version>
# $1 <version>
install_plesk() {
  local version="${1^^}"
  local temp_file="/plesk-installer"

  debug '# preparing plesk installation'
  if [[ "${IAM}" == centos ]]; then
    # debug '# installing mysql'
    # execute_chroot_command 'yum -y install mysql mysql-server' || return 1
    # debug 'installed mysql'
    debug '# installing openssl'
    execute_chroot_command 'yum -y install openssl' # || return 1
    debug 'installed openssl'
  fi
  [[ "${IAM}" == debian ]] && (( IMG_VERSION >= 70 )) && mkdir --parents "${FOLD}/hdd/run/lock"

  # enable ip_nonlocal_bind for natted plesk installations
  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    ((${#ipv4_addrs[@]} == 0)) && continue
    if ! ipv4_addr_is_private "${ipv4_addrs[0]}" || ! isVServer; then
      continue
    fi
    {
      echo 'net.ipv4.ip_nonlocal_bind = 1'
      echo 'net.ipv6.ip_nonlocal_bind = 1'
    } >> "$FOLD/hdd/etc/sysctl.d/99-hetzner.conf"
    break
  done < <(physical_network_interfaces)

  debug "# downloading plesk installer ${PLESK_INSTALLER_SRC}/${IMAGENAME}"
  curl --location --output "${FOLD}/hdd/${temp_file}" --silent --write-out '%{response_code}' "${PLESK_INSTALLER_SRC}/${IMAGENAME}" \
    | grep --quiet 200 || return 1
  chmod a+x "${FOLD}/hdd/${temp_file}"
  debug 'downloaded plesk installer'

  [[ "${version}" == PLESK ]] && version="${PLESK_STD_VERSION}"
  if ! echo "${version}" | egrep --quiet "^PLESK_[[:digit:]]+_[[:digit:]]+_[[:digit:]]+$"; then
    version="$(
      execute_chroot_command_wo_debug "${temp_file} --select-product-id plesk --show-releases 2> /dev/null" \
        | tail -n +2 \
        | grep "^${version}" \
        | head -n 1 \
        | awk '{ print $2 }'
    )"
  fi
  [[ -z "${version}" ]] && return 1
  #[[ "${version}" =~ ^PLESK_17_ ]] && PLESK_COMPONENTS=(${PLESK_COMPONENTS[@]/#pmm/pmm-old})

  debug "# installing plesk ${version}"
  local command="${temp_file} "
  command+="--source ${PLESK_MIRROR} "
  command+='--select-product-id plesk '
  command+="--select-release-id ${version} "
  command+="--download-retry-count ${PLESK_DOWNLOAD_RETRY_COUNT} "
  command+="${PLESK_COMPONENTS[*]/#/--install-component }"

  if installed_os_uses_systemd && ! systemd_nspawn_booted; then
    boot_systemd_nspawn || return 1
  fi
  execute_command "${command}" || return 1
  systemd_nspawn_booted && poweroff_systemd_nspawn
  debug "installed plesk ${version}"

  return 0
}

# vim: ai:ts=2:sw=2:et
