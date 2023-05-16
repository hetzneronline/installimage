#!/usr/bin/env bash

# (c) 2023, Hetzner Online GmbH

# list network interfaces
network_interfaces() {
  for file in /sys/class/net/*; do
    echo "${file##*/}"
  done
}

# check whether network interface is virtual
# $1 <network_interface>
network_interface_is_virtual() {
  local network_interface="$1"
  [[ -d "/sys/devices/virtual/net/$network_interface" ]]
}

# list physical network interfaces
physical_network_interfaces() {
  while read network_interface; do
    network_interface_is_virtual "$network_interface" && continue
    echo "$network_interface"
  done < <(network_interfaces)
}

# get network interface driver
network_interface_driver() {
  local network_interface="$1"
  basename "$(readlink -f "/sys/class/net/$network_interface/device/driver")"
}

# predict network interface name
# $1 <network_interface>
predict_network_interface_name() {
  local network_interface="$1"
  # https://github.com/systemd/systemd/pull/1119
  local network_interface_driver="$(network_interface_driver "$network_interface")"
  local d="$(echo; udevadm test-builtin net_id "/sys/class/net/$network_interface" 2>/dev/null)"
  [[ "$d" =~ $'\n'ID_NET_NAME_ONBOARD=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_SLOT=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  # we need to convert ID_NET_NAME_PATH to ID_NET_NAME_SLOT for e1000 and 8139cp network interfaces
  [[ "$network_interface_driver" =~ ^(e1000|8139cp)$ ]] && [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([a-z]{2})p0([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  [[ "$d" =~ $'\n'ID_NET_NAME_MAC=([^$'\n']+) ]] && echo "${BASH_REMATCH[1]}" && return
  return 1
}

while read network_interface; do
  echo "$network_interface -> $(predict_network_interface_name "$network_interface")"
done < <(physical_network_interfaces)

# vim: ai:ts=2:sw=2:et
