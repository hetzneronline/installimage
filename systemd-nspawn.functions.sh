#!/usr/bin/env bash

#
# systemd-nspawn functions
#
# (c) 2015-2016, Hetzner Online GmbH
#

# is_systemd_system()
# checks whether both, the rescue system and the installed system, are using
# systemd
is_systemd_system() {
  readlink --canonicalize /sbin/init | grep --quiet systemd &&
    readlink --canonicalize "${FOLD}/hdd/sbin/init" | grep --quiet systemd
}

# systemd_nspawn_container_is_running()
# checks whether a systemd nspawn container is running
systemd_nspawn_container_is_running() {
  [[ -f "${SYSTEMD_NSPAWN_SERVICE_FILE}" ]] &&
    systemctl --quiet is-active "$(basename "${SYSTEMD_NSPAWN_SERVICE_FILE}")"
}

# start_systemd_nspawn_container()
# starts the installed system within a systemd nspawn container
start_systemd_nspawn_container() {
  SYSTEMD_NSPAWN_HELPER_SCRIPT="${SYSTEMD_NSPAWN_HELPER_SCRIPT:-$(chroot_mktemp)}"
  SYSTEMD_NSPAWN_FIFO_DIR="${SYSTEMD_NSPAWN_FIFO_DIR:-$(chroot_mktemp --directory)}"
  SYSTEMD_NSPAWN_IN_FIFO="${SYSTEMD_NSPAWN_FIFO_DIR}/in.fifo"
  SYSTEMD_NSPAWN_OUT_FIFO="${SYSTEMD_NSPAWN_FIFO_DIR}/out.fifo"
  SYSTEMD_NSPAWN_RETVAL_FIFO="${SYSTEMD_NSPAWN_FIFO_DIR}/retval.fifo"
  local temp_file; temp_file="$(mktemp)"
  TEMP_FILES+=("${temp_file}")

  debug '# starting the installed system within a systemd nspawn container'
  if systemd_nspawn_container_is_running; then
    debug 'the installed system is already running within a systemd nspawn container'
    return 0
  fi

  # we need to ensure that mount points that are in our blacklist are umounted
  # before a systemd nspawn container is started
  # for this we read /proc/mounts in reverse order, dissolve dependencies,
  # umount and file umounted /proc/mounts entries in order to be able to remount
  # umounted mount points later on
  debug '# temp. umounting blacklisted mount points before starting the systemd nspawn container:'
  touch "${SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST}"
  while read -r entry; do
    for blacklisted_mount_point in "${SYSTEMD_NSPAWN_BLACKLISTED_MOUNT_POINTS[@]}"; do
      while read -r subentry; do
        umount --verbose "$(echo "${subentry}" | awk '{ print $2 }')" &> /dev/null || return 1
        echo "${subentry}" | cat - "${SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST}" | uniq --unique > "${temp_file}"
        mv "${temp_file}" "${SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST}"
      done < <(echo "${entry}" | grep "${SYSTEMD_NSPAWN_ROOT_DIR}${blacklisted_mount_point}")
    done
  done < <(tac /proc/mounts)

  # we use fifos and a helper script as an interface
  # these are our general IO fifos
  for fifo in "${SYSTEMD_NSPAWN_IN_FIFO}" "${SYSTEMD_NSPAWN_OUT_FIFO}"; do
    [[ -p "${SYSTEMD_NSPAWN_ROOT_DIR}/${fifo}" ]] || mkfifo "${SYSTEMD_NSPAWN_ROOT_DIR}/${fifo}"
  done
  # $SYSTEMD_NSPAWN_RETVAL_FIFO is our return value fifo
  [[ -p "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_RETVAL_FIFO}" ]] || mkfifo "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_RETVAL_FIFO}"

  # the helper script mentioned executes any command piped in via the IN
  # fifo, redirects output and passes return values to the appropriate back
  # channels
  {
    echo '#!/usr/bin/env bash'
    echo "### ${COMPANY} installimage"
    echo 'while :; do'
    echo "  cat ${SYSTEMD_NSPAWN_IN_FIFO} | bash &> ${SYSTEMD_NSPAWN_OUT_FIFO}"
    echo "  echo \${?} > ${SYSTEMD_NSPAWN_RETVAL_FIFO}"
    echo 'done'
  } > "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_HELPER_SCRIPT}"
  chmod a+x "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_HELPER_SCRIPT}"

  {
    echo "### ${COMPANY} installimage"
    echo '[Unit]'
    echo 'After=network.target'
    echo '[Service]'
    echo "ExecStart=${SYSTEMD_NSPAWN_HELPER_SCRIPT}"
  } > "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_HELPER_SERVICE_FILE}"

  {
    echo "### ${COMPANY} installimage"
    echo '[Service]'
    echo "ExecStart=/usr/bin/systemd-nspawn \\"
    echo "  --boot \\"
    echo "  --directory=${SYSTEMD_NSPAWN_ROOT_DIR} \\"
    echo '  --quiet'
  } > "${SYSTEMD_NSPAWN_SERVICE_FILE}"

  systemctl daemon-reload |& debugoutput || return 1
  systemctl start "$(basename "${SYSTEMD_NSPAWN_SERVICE_FILE}")" |& debugoutput || return 1
  local max_checks=300
  for ((check=1; check<=max_checks; check++)); do
    systemd_nspawn_container_is_running && break
    (( check == max_checks )) && return 1
    sleep 1
  done
  debug 'started the installed system within a systemd nspawn container:'
  # systemctl status $(basename ${SYSTEMD_NSPAWN_SERVICE_FILE}) |& debugoutput
}

# execute_within_systemd_nspawn_container() <command> <debug>
# executes a command within a systemd nspawn container
# $1 <command> the command to execute
# for convenience, the command can also be passed via stdin!
# $2 <debug>   (yes|no) default: yes
execute_within_systemd_nspawn_container() {
  local command="${1}"
  # merge stdin
  [[ -t 0 ]] || command+="$(cat)"
  local debug="${2:-debug}"
  local quiet="${3:-quiet}"
  [[ "${debug}" == debug ]] && debug=true || debug=false
  [[ "${quiet}" == quiet ]] && quiet=true || quiet=false

  ${debug} && debug "# executing within systemd nspawn container: ${command}"
  if ! systemd_nspawn_container_is_running; then
    start_systemd_nspawn_container || return 1
  fi
  echo "${command}" > "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_IN_FIFO}"
  (
    if ${debug}; then
      if ${quiet}; then
        cat | debugoutput
      else
        tee >(debugoutput)
      fi
    else
      if ! ${quiet}; then
        cat
      fi
    fi
    wait
  ) < "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_OUT_FIFO}"
  wait
  return "$(cat "${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_RETVAL_FIFO}")"
}

execute_nspawn_command() { execute_within_systemd_nspawn_container "${@}" || return 1; }

# stop_systemd_nspawn_container()
# stops systemd nspawn container
stop_systemd_nspawn_container() {
  debug '# stopping systemd nspawn container'
  if ! systemd_nspawn_container_is_running; then
    debug 'systemd nspawn container is not running'
    return 0
  fi
  systemctl stop "$(basename "${SYSTEMD_NSPAWN_SERVICE_FILE}")" |& debugoutput || return 1
  local max_checks=300
  for ((check=1; check<=max_checks; check++)); do
    systemd_nspawn_container_is_running || break
    (( check == max_checks )) && return 1
    sleep 1
  done
  debug 'stopped systemd nspawn container'
  # systemctl status $(basename ${SYSTEMD_NSPAWN_SERVICE_FILE}) |& debugoutput

  debug '# remounting temp. umounted mount points:'
  mount --all --fstab "${SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST}" &> /dev/null || return 1
}

# vim: ai:ts=2:sw=2:et
