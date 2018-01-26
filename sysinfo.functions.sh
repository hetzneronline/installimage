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

# vim: ai:ts=2:sw=2:et
