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

# vim: ai:ts=2:sw=2:et
