#!/usr/bin/env bash

#
# imageinfo functions
#
# (c) 2019-2022, Hetzner Online GmbH
#

debian_buster_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ( ((IMG_VERSION >= 100)) && ((IMG_VERSION <= 109)) ) || ( ((IMG_VERSION >= 1010)) && ((IMG_VERSION < 1100)) )
}

debian_bullseye_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ((IMG_VERSION >= 1100)) && ((IMG_VERSION <= 1200))
}

other_image() {
  local image="$1"
  while read other_image; do
    [[ "${image##*/}" == "$other_image" ]] && return 0
  done < <(other_images)
  return 1
}

old_image() {
  local image="$1"
  image="$(readlink -f "$image")"
  [[ -e "$image" ]] || return 1
  [[ "${image%/*}" == "$(readlink -f "$OLDIMAGESPATH")" ]]
}

rhel_9_based_image() {
  [[ "$IAM" == 'centos' ]] && ((IMG_VERSION >= 90)) && ((IMG_VERSION != 610)) && return
  [[ "$IAM" == 'rockylinux' ]] && ((IMG_VERSION >= 90)) && return
  [[ "$IAM" == 'rhel' ]] && ((IMG_VERSION >= 90)) && return
  [[ "$IAM" == 'almalinux' ]] && ((IMG_VERSION >= 90)) && return
  return 1
}

uses_network_manager() {
  [[ "$IAM" == 'centos' ]] && ((IMG_VERSION >= 80)) && ((IMG_VERSION != 610)) && ! is_cpanel_install && return
  [[ "$IAM" == 'rockylinux' ]] && return
  [[ "$IAM" == 'rhel' ]] && return
  [[ "$IAM" == 'almalinux' ]] && ! is_cpanel_install && return
  return 1
}

debian_based_image() {
  [[ "$IAM" == 'debian' ]] || [[ "$IAM" == 'ubuntu' ]]
}

# vim: ai:ts=2:sw=2:et
