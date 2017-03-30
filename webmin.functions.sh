#!/usr/bin/env bash

#
# webmin functions
#
# (c) 2017, Hetzner Online GmbH
#

regenerate_webmin_miniserv_ssl_certificate() {
  local webmin_miniserv_ssl_certificate="$FOLD/hdd/etc/webmin/miniserv.pem"
  debug '# regenerate webmin miniserv ssl certificate'
  if [[ -e "$webmin_miniserv_ssl_certificate" ]]; then
    rm "$webmin_miniserv_ssl_certificate" || return 1
  fi
  openssl req -days 1825 -keyout "$webmin_miniserv_ssl_certificate" \
    -newkey rsa:2048 -nodes -out "$webmin_miniserv_ssl_certificate" -sha256 \
    -subj "/CN=*/emailAddress=$USER@$(hostname)/O=Webmin Webserver on $(hostname)" \
    -x509 |& debugoutput
  (("${PIPESTATUS[0]}" == 0)) && [[ -e "$webmin_miniserv_ssl_certificate" ]]
}

setup_webmin() {
  debug '# setup webmin'
  regenerate_webmin_miniserv_ssl_certificate
}

# vim: ai:ts=2:sw=2:et
