#!/usr/bin/env bash

#
# report functions
#
# (c) 2021, Hetzner Online GmbH
#

filter_image_option() {
  sed 's%/.*:.*@%//[FILTERED]:[FILTERED]@%g'
}

filter_install_conf() {
  sed 's/^.*CRYPTPASSWORD.*$/CRYPTPASSWORD [FILTERED]/g' \
    | filter_image_option
}

report_install() {
  filter_install_conf < "$FOLD/install.conf" > "$FOLD/install.conf.filtered"
  curl --data-urlencode "config@$FOLD/install.conf.filtered" \
    --data-urlencode "mac=$HWADDR" \
    -k \
    -m 10 \
    -s \
    -D "$FOLD/install_report.headers" \
    "https://$STATSSERVER/api/v1/installimage/installations" > "$FOLD/install_report.response"
  debug "Sent install.conf to statsserver: $(head -n 1 "$FOLD/install_report.headers")"

  local image_id="$(cat "$FOLD/install_report.response")"
  [[ "$image_id" =~ ^[0-9]*$ ]] || return 1
  filter_image_option < "$DEBUGFILE" > "$FOLD/debug.txt.filtered"
  curl -H 'Content-Type: text/plain' \
    -k \
    -m 10 \
    -s \
    -T "$FOLD/debug.txt.filtered" \
    -D "$FOLD/install_report.headers" \
    -X POST \
    "https://$STATSSERVER/api/v1/installimage/installations/$image_id/logs" > /dev/null
  debug "Sent debug.txt to statsserver: $(head -n 1 "$FOLD/install_report.headers")"
}

# vim: ai:ts=2:sw=2:et
