#!/usr/bin/env bash

#
# plesk functions
#
# (c) 2007-2018, Hetzner Online GmbH
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
    debug '# installing openssl'
    execute_chroot_command 'yum -y install openssl' # || return 1
  fi

  [[ "${IAM}" == debian ]] && (( IMG_VERSION >= 70 )) && mkdir --parents "${FOLD}/hdd/run/lock"

  if [[ "$IAM" == 'almalinux' ]]; then
    debug '# installing chkconfig'
    execute_chroot_command 'yum -y install chkconfig'
  fi

  if debian_bullseye_image; then
    debug '# plesk does not support debian bullseye backports:'
    cp "$FOLD/hdd/etc/apt/sources.list" "$FOLD/sources.list"
    local i=0
    while read line; do
      ((i=i+1))
      egrep -q '(^\s*#|^\s*$)' <<< "$line" && continue
      local dist
      read _ _ dist _ <<< "$line"
      [[ "$dist" == 'bullseye-backports' ]] || continue
      echo -e "# Plesk does not support Debian Bullseye Backports\n# $line" | sed -e "$i{/.*/{r /dev/stdin" -e 'd;}}' -i "$FOLD/hdd/etc/apt/sources.list"
    done < "$FOLD/sources.list"
    diff -Naur "$FOLD/sources.list" "$FOLD/hdd/etc/apt/sources.list" | debugoutput
  fi

  # enable ip_nonlocal_bind for natted plesk installations
  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    ((${#ipv4_addrs[@]} == 0)) && continue
    if ! ipv4_addr_is_private "${ipv4_addrs[0]}" || ! is_virtual_machine; then
      continue
    fi
    {
      echo 'net.ipv4.ip_nonlocal_bind = 1'
      echo 'net.ipv6.ip_nonlocal_bind = 1'
    } >> "$FOLD/hdd/etc/sysctl.d/99-hetzner.conf"
    break
  done < <(physical_network_interfaces)

  if [[ "$IAM" == ubuntu ]] && ((IMG_VERSION == 1804)); then
    debug '# disabling apt-daily timers'
    for timer in apt-daily apt-daily-upgrade; do
      systemd_nspawn "systemctl disable $timer.timer" || return 1
    done
  fi

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

  if [[ "$IAM" == ubuntu ]] && ((IMG_VERSION == 1804)); then
    debug '# reenabling apt-daily timers'
    for timer in apt-daily apt-daily-upgrade; do
      systemd_nspawn "systemctl enable $timer.timer" || return 1
    done
  fi

  return 0
}

# vim: ai:ts=2:sw=2:et
