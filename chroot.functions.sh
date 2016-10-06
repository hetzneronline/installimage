#!/usr/bin/env bash

#
# chroot functions
#
# (c) 2007-2016, Hetzner Online GmbH
#

# execute_chroot_command() <command> <debug> <quiet>
# executes a chroot command
# $1 <command> the command to execute
# $2 <debug>   (debug|nodebug) default: yes
# $3 <quiet>   (quiet|dump) default: yes
execute_chroot_command() {
  local command="${1}"
  local debug="${2:-debug}"
  local quiet="${3:-quiet}"
  [[ "${debug}" == debug ]] && debug=true || debug=false
  [[ "${quiet}" == quiet ]] && quiet=true || quiet=false

  ${debug} && debug "# executing chroot command: ${command}"

  chroot "${FOLD}/hdd" /usr/bin/env bash -c "${command}" |& (
    if ${debug}; then
      if ${quiet}; then
        cat | debugoutput
      else
        tee >(debugoutput); wait
      fi
    else
      if ! ${quiet}; then
        cat
      fi
    fi
  )
}

# for compatibility
execute_chroot_command_wo_debug() { execute_chroot_command "${1}" nodebug "${2:-dump}"; return "${?}"; }

# vim: ai:ts=2:sw=2:et
