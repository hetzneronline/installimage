#!/usr/bin/env bash

#
# imageinfo functions
#
# (c) 2019, Hetzner Online GmbH
#

debian_buster_image() {
  [[ "${IAM,,}" == 'debian' ]] && ((IMG_VERSION >= 100)) && ((IMG_VERSION < 710))
}

# vim: ai:ts=2:sw=2:et
