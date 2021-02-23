#!/usr/bin/env bash

#
# swraid functions
#
# (c) 2016-2018, Hetzner Online GmbH
#

# suspend_swraid_resync
suspend_swraid_resync() {
  echo 0 | tee /proc/sys/dev/raid/speed_limit_max > /proc/sys/dev/raid/speed_limit_min
}

set_raid0_default_layout() {
  modprobe raid0
  (($(< /sys/module/raid0/parameters/default_layout) == 0)) || return
  echo 2 > /sys/module/raid0/parameters/default_layout
}

unset_raid0_default_layout() {
  [[ -e /sys/module/raid0/parameters/default_layout ]] || return
  echo 0 > /sys/module/raid0/parameters/default_layout
}

# resume_swraid_resync
resume_swraid_resync() {
  echo 200000 > /proc/sys/dev/raid/speed_limit_max
  echo 1000 > /proc/sys/dev/raid/speed_limit_min
}

# vim: ai:ts=2:sw=2:et
