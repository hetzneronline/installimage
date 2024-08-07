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

report_install_old() {
  filter_install_conf < "$FOLD/install.conf" > "$FOLD/install.conf.filtered"
  local main_mac
  main_mac="$(main_mac)" || return 1
  if has_no_ipv4; then
    local statsserver="$STATSSERVER6"
  else
    local statsserver="$STATSSERVER4"
  fi
  curl --data-urlencode "config@$FOLD/install.conf.filtered" \
    --data-urlencode "mac=$main_mac" \
    -k \
    -m 10 \
    -s \
    -D "$FOLD/install_report.headers" \
    "https://$statsserver/api/v1/installimage/installations" > "$FOLD/install_report.response"
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
    "https://$statsserver/api/v1/installimage/installations/$image_id/logs" > /dev/null
  debug "Sent debug.txt to statsserver: $(head -n 1 "$FOLD/install_report.headers")"
}

report_install_new() {
  local rescue_system_build_sha=''

  if [[ -e /etc/hetzner-build ]] && [[ "\n$(< /etc/hetzner-build)" =~ $'\n'Build\ SHA1:\ ([0-9a-f-]+) ]]; then
    rescue_system_build_sha="${BASH_REMATCH[1]}"
  fi

  local bootif_mac

  [[ " $(< /proc/cmdline)" =~ \ BOOTIF=01-([0-9a-f-]+) ]];

  bootif_mac="${BASH_REMATCH[1]//-/:}"

  local bootif_ip='' bootif_ip6='' dir ip_json

  for dir in /sys/class/net/*; do
    [[ "$(< "$dir/address")" == "$bootif_mac" ]] || continue
    ip_json="$(ip -j a s "${dir##*/}")"
    bootif_ip="$(jq -r '.[0].addr_info | map(select(.family=="inet" and .scope=="global"))[0].local' <<< "$ip_json")"
    bootif_ip6="$(jq -r '.[0].addr_info | map(select(.family=="inet6" and .scope=="global"))[0].local' <<< "$ip_json")"
    break
  done

  if [[ -e /sys/firmware/efi ]]; then local boot_mode='uefi'; else local boot_mode='bios'; fi

  local image_uri="$IMAGE"
  local image_basename="${image_uri##*/}"

  local distro_id='' image_version='' image_arch='' image_flavour=''

  if [[ "${image_basename}" =~ ^([^-]+)-([^-]+)-([^-]+)-([^.]+) ]]; then
    distro_id="${BASH_REMATCH[1]}"
    image_version="${BASH_REMATCH[2]}"
    image_arch="${BASH_REMATCH[3]}"
    image_flavour="${BASH_REMATCH[4]}"
  elif [[ "${image_basename}" =~ ^([^-]+)-([^-]+)-([^-]+)-([^-]+)-([^.]+) ]]; then
    distro_id="${BASH_REMATCH[1]}"
    image_version="${BASH_REMATCH[2]}"
    image_arch="${BASH_REMATCH[4]}"
    image_flavour="${BASH_REMATCH[5]}"
  fi

  local image_realpath="$(readlink -f "$image_uri")"

  local distro_release=''

  if [[ -n "$distro_id" && "${image_realpath##*/}" =~ ^[^-]+-([^-]+)- ]]; then
    distro_release="${BASH_REMATCH[1]}"
  fi

  filter_install_conf < "$FOLD/install.conf" > "$FOLD/install.conf.filtered"
  filter_image_option < "$DEBUGFILE" > "$FOLD/debug.txt.filtered"

  report="$(
    jq -n '{
      "rescue_system_build_sha": $rescue_system_build_sha,
      "installimage_version": $installimage_version,
      "bootif_ip": $bootif_ip,
      "bootif_ip6": $bootif_ip6,
      "bootif_mac": $bootif_mac,
      "hardware_information": {
        "board_vendor": $board_vendor,
        "board_name": $board_name,
        "board_version": $board_version,
        "bios_version": $bios_version,
        "boot_mode": $boot_mode
      },
      "image_information": {
        "uri": $image_uri,
        "version": $image_version,
        "arch": $image_arch,
        "flavour": $image_flavour
      },
      "distribution_information": {
        "name": $distro_id,
        "release": $distro_release
      },
      "installimage_config": $installimage_config,
      "installimage_return_code": $installimage_return_code,
      "debug_log": $debug_log
    }' \
    --arg rescue_system_build_sha "$rescue_system_build_sha" \
    --arg installimage_version "$INSTALLIMAGE_VERSION" \
    --arg bootif_ip "$bootif_ip" \
    --arg bootif_ip6 "$bootif_ip6" \
    --arg bootif_mac "$bootif_mac" \
    --arg board_vendor "$(< /sys/class/dmi/id/board_vendor)" \
    --arg board_name "$(< /sys/class/dmi/id/board_name)" \
    --arg board_version "$(< /sys/class/dmi/id/board_version)" \
    --arg bios_version "$(< /sys/class/dmi/id/bios_version)" \
    --arg boot_mode "$boot_mode" \
    --arg image_uri "$image_uri" \
    --arg image_version "${image_version,,}" \
    --arg image_arch "${image_arch,,}" \
    --arg image_flavour "${image_flavour,,}" \
    --arg distro_id "${distro_id,,}" \
    --arg distro_release "${distro_release,,}" \
    --argjson installimage_return_code "$ERROREXIT" \
    --arg installimage_config "$(< "$FOLD/install.conf.filtered")" \
    --arg debug_log "$(< "$FOLD/debug.txt.filtered")"
  )"

  debug '# report installation'
  {
    local response
    if response="$(curl -s --max-time 30 --retry 3 --retry-all-errors --retry-delay 5 -H 'Accept: application/json' -H 'Content-Type: application/json' "$INSTALLATION_REPORT_URL" --data "$report")"; then
      local uuid
      uuid="$(jq -r '.data.uuid' <<< "$response")"
      debugoutput <<< "installation report uuid: $uuid"
    fi
  } |& debugoutput
}

# vim: ai:ts=2:sw=2:et
