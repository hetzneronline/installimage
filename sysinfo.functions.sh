#!/usr/bin/env bash

#
# sysinfo functions
#
# (c) 2018, Hetzner Online GmbH
#

cpu_model_names() {
  while read line; do
    [[ "$line" =~ ^model\ name$'\t'+:\ (.*)$ ]] || continue
    echo "${BASH_REMATCH[1]}"
  done < /proc/cpuinfo | sort -u
}

has_epyc_cpu() {
  while read cpu_model_name; do
    [[ "$cpu_model_name" =~ EPYC ]] && return 0
  done < <(cpu_model_names)
  return 1
}

has_threadripper_cpu() {
  while read cpu_model_name; do
    [[ "$cpu_model_name" =~ Threadripper ]] && return 0
  done < <(cpu_model_names)
  return 1
}

is_dell_r6415() {
  if [ "$(dmidecode -t system|grep -m 1 -o "PowerEdge R6415")" = "PowerEdge R6415" ] ; then
    return 0
  else
    return 1
  fi
}

drive_disk_by_id_path() {
  local drive; drive="$1"
  for l in /dev/disk/by-id/*; do
    [[ "${l##*/}" =~ ^(ata|nvme|scsi)- ]] && [[ "$(readlink -f "$drive")" == "$(readlink -f "$l")" ]] && echo "$l" && return 0
  done
}

board_vendor() { cat /sys/class/dmi/id/board_vendor; }

board_name() { cat /sys/class/dmi/id/board_name; }

has_fujitsu_board() {
  [[ "$(board_vendor)" == FUJITSU ]]
}

has_b360hd3p_board() {
  [[ "$(board_name)" == 'B360HD3P-CF' ]] ||
    [[ "$(board_name)" == 'B360HD3PLM-CF' ]]
}


# vim: ai:ts=2:sw=2:et
