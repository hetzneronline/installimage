#!/usr/bin/env bash

#
# imageinfo functions
#
# (c) 2019-2024, Hetzner Online GmbH
#

debian_buster_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ( ((IMG_VERSION >= 100)) && ((IMG_VERSION <= 109)) ) || ( ((IMG_VERSION >= 1010)) && ((IMG_VERSION < 1100)) )
}

debian_bullseye_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ((IMG_VERSION >= 1100)) && ((IMG_VERSION <= 1200))
}

debian_bookworm_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ((IMG_VERSION >= 1200)) && ((IMG_VERSION <= 1300))
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

rhel_based_image() {
  [[ "$IAM" == 'centos' ]] ||
  [[ "$IAM" == 'rockylinux' ]] ||
  [[ "$IAM" == 'almalinux' ]] ||
  [[ "$IAM" == 'rhel' ]]
}

rhel_9_based_image() {
  [[ "$IAM" == 'centos' ]] && ((IMG_VERSION >= 90)) && ((IMG_VERSION != 610)) && return
  rhel_based_image && ((IMG_VERSION >= 90)) && return
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

hwe_image() {
  [[ "$IMAGE_FILE" =~ -hwe\. ]]
}

image_requires_xfs_version_check() {
  [[ "$IAM" == 'ubuntu' ]] && ((IMG_VERSION <= 2004)) && return 0
  [[ "$IAM" == 'debian' ]] && ((IMG_VERSION < 1100)) && return 0
  return 1
}

image_i40e_driver_version() {
  [[ "$(modinfo -F vermagic "$FOLD/hdd/lib/modules/"*'/kernel/drivers/net/ethernet/intel/i40e/i40e.ko' 2> /dev/null)" =~ ^([0-9]+\.[0-9]+)[^0-9] ]] || return
  echo "${BASH_REMATCH[1]}"
}

image_i40e_driver_version_ge() {
  local other="$1"
  [[ "$(echo -e "$(image_i40e_driver_version)\n$other" | sort -V | head -n 1)" == "$other" ]]
}

image_i40e_driver_exposes_port_name() {
  image_i40e_driver_version_ge '6.7'
}

# vim: ai:ts=2:sw=2:et
