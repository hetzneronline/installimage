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
  local temp_file; temp_file=$(chroot_mktemp)

  # debug '# preparing plesk installation'
  # if [[ "${IAM}" == centos ]]; then
  #   debug '# installing mysql'
  #   execute_chroot_command 'yum -y install mysql mysql-server' || return 1
  #   debug 'installed mysql'
  # fi
  [[ "${IAM}" == debian ]] && (( IMG_VERSION >= 70 )) && mkdir --parents "${FOLD}/hdd/run/lock"

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

  debug "# installing plesk ${version}"
  local command="${temp_file} "
  command+='--select-product-id plesk '
  command+="--select-release-id ${version} "
  command+="--download-retry-count ${PLESK_DOWNLOAD_RETRY_COUNT} "
  command+="${PLESK_COMPONENTS[*]/#/--install-component }"

  execute_command "${command}" || return 1
  stop_systemd_nspawn_container
  debug "installed plesk ${version}"
}

# vim: ai:ts=2:sw=2:et
