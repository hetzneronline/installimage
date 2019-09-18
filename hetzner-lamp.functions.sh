#!/usr/bin/env bash

#
# hetzner lamp functions
#
# (c) 2017-2018, Hetzner Online GmbH
#

hetzner_lamp_install() { lamp_install && [[ "${IAM,,}" == 'debian' ]]; }

setup_hetzner_lamp() {
  debug '# setup hetzner lamp'
  setup_lamp || return 1
  if debian_buster_image; then
    setup_adminer || return 1
  else
    setup_phpmyadmin || return 1
  fi
  setup_webmin
}

# vim: ai:ts=2:sw=2:et
