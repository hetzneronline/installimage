#!/usr/bin/env bash

#
# imageinfo functions
#
# (c) 2019, Hetzner Online GmbH
#

debian_buster_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ( ((IMG_VERSION >= 100)) && ((IMG_VERSION <= 109)) ) || ( ((IMG_VERSION >= 1010)) && ((IMG_VERSION < 1100)) )
}

debian_bullseye_image() {
  [[ "${IAM,,}" == 'debian' ]] || return 1
  ((IMG_VERSION >= 1100)) && ((IMG_VERSION <= 1200))
}

# vim: ai:ts=2:sw=2:et
