#!/usr/bin/env bash

#
# lamp functions
#
# (c) 2008-2018, Hetzner Online GmbH
#

lamp_install() { [[ "${IMAGENAME,,}" =~ lamp$|lamp-beta$ ]]; }

setup_lamp() {
  debug '# setup lamp'
  regenerate_snakeoil_ssl_certificate || return 1
  if ! debian_buster_image; then
    randomize_mysql_root_password || return 1
  fi
  if mysql_user_exists debian-sys-maint; then
    randomize_debian_sys_maint_mysql_password || return 1
  fi
  return
}

# vim: ai:ts=2:sw=2:et
