#!/usr/bin/env bash

#
# network config functions
#
# (c) 2017-2024, Hetzner Online GmbH
#

# setup /etc/sysconfig/network
setup_etc_sysconfig_network() {
  debug '# setup /etc/sysconfig/network'

  {
    echo "### $COMPANY installimage"
    echo
    echo "NETWORKING=yes"
  } > "$FOLD/hdd/etc/sysconfig/network"
}

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

# get ip addr without suffix
# $1 <ip_addr>
ip_addr_without_suffix() {
  local ip_addr="$1"
  echo "${ip_addr%%/*}"
}

# get ip addr suffix
# $1 <ip_addr>
ip_addr_suffix() {
  local ip_addr="$1"
  if [[ "$ip_addr" =~ / ]]; then
    echo "${ip_addr##*/}"
  # assume /32 unless $ip_addr contains /
  else
    echo 32
  fi
}

# conv ipv4 addr to int
# $1 <ipv4_addr>
ipv4_addr_to_int() {
  local ipv4_addr="$1"
  local ipv4_addr_without_suffix="$(ip_addr_without_suffix "$ipv4_addr")"
  { IFS=. read a b c d; } <<< "$ipv4_addr_without_suffix"
  echo "$(((((((a << 8) | b) << 8) | c) << 8) | d))"
}

# conv int to ipv4 addr
# $1 <int>
int_to_ipv4_addr() {
  local int="$1"
  echo "$(((int >> 24) & 0xff)).$(((int >> 16) & 0xff)).$(((int >> 8) & 0xff)).$((int & 0xff))/32"
}

# calc ipv4 addr network
# $1 <ipv4_addr>
ipv4_addr_network() {
  local ipv4_addr="$1"
  local ipv4_addr_suffix="$(ip_addr_suffix "$ipv4_addr")"
  local int="$(ipv4_addr_to_int "$ipv4_addr")"
  local network_without_suffix="$(ip_addr_without_suffix "$(int_to_ipv4_addr "$((int & (0xffffffff << (32 - ipv4_addr_suffix))))")")"
  echo "$network_without_suffix/$ipv4_addr_suffix"
}

# check whether network contains ipv4 addr
# $1 <network>
# $2 <ipv4_addr>
network_contains_ipv4_addr() {
  local network="$1"
  local ipv4_addr="$2"
  ipv4_addr="$(ip_addr_without_suffix "$ipv4_addr")/$(ip_addr_suffix "$network")"
  [[ "$(ipv4_addr_network "$ipv4_addr")" == "$network" ]]
}

# check whether ipv4 addr is a shared addr (rfc6598)
# $1 <ipv4_addr>
ipv4_addr_is_shared_addr() {
  local ipv4_addr="$1"
  network_contains_ipv4_addr 100.64.0.0/10 "$ipv4_addr"
}

# check if ipv4 addr is reserved for future use
ipv4_addr_is_reserved_for_future_use() {
  local ipv4_addr="$1"
  network_contains_ipv4_addr 240.0.0.0/4 "$ipv4_addr"
}

# get network interface ipv4 addrs
# $1 <network_interface>
network_interface_ipv4_addrs() {
  local network_interface="$1"
  while read line; do
    [[ "$line" =~ ^\ *inet\ ([^\ ]+) ]] || continue
    local ipv4_addr="${BASH_REMATCH[1]}"
    # ignore shared addrs
    ipv4_addr_is_shared_addr "$ipv4_addr" && continue
    # ignore addrs reserved for future use
    ipv4_addr_is_reserved_for_future_use "$ipv4_addr" && continue
    echo "$ipv4_addr"
  done < <(ip -4 a s "$network_interface")
}

# check whether ipv6 addr is a link local unicast addr
# $1 <ipv6_addr>
ipv6_addr_is_link_local_unicast_addr() {
  local ipv6_addr="$1"
  [[ "$ipv6_addr" =~ ^fe80: ]]
}

# get network interface ipv6 addrs
# $1 <network_interface>
network_interface_ipv6_addrs() {
  # "hide" v6 if IPV4_ONLY set
  ((IPV4_ONLY == 1)) && return

  local network_interface="$1"
  while read line; do
    [[ "$line" =~ ^\ *inet6\ ([^\ ]+) ]] || continue
    local ipv6_addr="${BASH_REMATCH[1]}"
    # ignore link local unicast addrs
    ipv6_addr_is_link_local_unicast_addr "$ipv6_addr" && continue
    echo "$ipv6_addr"
  done < <(ip -6 a s "$network_interface")
}

# check whether to use predictable network interface names
use_predictable_network_interface_names() {
  [[ "$IAM" == 'centos' ]] && return
  [[ "$IAM" == 'debian' ]] && return
  [[ "$IAM" == 'ubuntu' ]] && return
  [[ "$IAM" == 'archlinux' ]] && return
  [[ "$IAM" == 'rockylinux' ]] && return
  [[ "$IAM" == 'almalinux' ]] && return
  [[ "$IAM" == 'rhel' ]] && return
  return 1
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
  if ! use_predictable_network_interface_names; then
    echo "$network_interface"
    return
  fi
  # https://github.com/systemd/systemd/pull/1119
  local network_interface_driver="$(network_interface_driver "$network_interface")"
  if [[ "$network_interface_driver" == 'virtio_net' ]]; then
    if (($(installed_os_systemd_version) < 226)); then
      echo "$network_interface"
      return
    else
      local d="$(systemd_nspawn_wo_debug "udevadm test-builtin net_id \"/sys/class/net/$network_interface\" 2>/dev/null" 2>/dev/null | tr -cd '[:print:]\n')"
    fi
  else
    local d="$(echo; systemd_nspawn_wo_debug "udevadm test-builtin net_id \"/sys/class/net/$network_interface\" 2>/dev/null")"
  fi

  local predicted_name=''

  [[ "$d" =~ $'\n'ID_NET_NAME_ONBOARD=([^$'\n']+) ]] \
    && predicted_name="${BASH_REMATCH[1]}"

  [[ -z "$predicted_name" ]] \
    && [[ "$d" =~ $'\n'ID_NET_NAME_SLOT=([^$'\n']+) ]] \
    && predicted_name="${BASH_REMATCH[1]}"

  # we need to convert ID_NET_NAME_PATH to ID_NET_NAME_SLOT for e1000 and 8139cp network interfaces
  [[ -z "$predicted_name" ]] \
    && [[ "$network_interface_driver" =~ ^(e1000|8139cp)$ ]] \
    && [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([a-z]{2})p0([^$'\n']+) ]] \
    && predicted_name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"

  [[ -z "$predicted_name" ]] \
    && [[ "$d" =~ $'\n'ID_NET_NAME_PATH=([^$'\n']+) ]] \
    && predicted_name="${BASH_REMATCH[1]}"

  [[ -z "$predicted_name" ]] \
    && [[ "$d" =~ $'\n'ID_NET_NAME_MAC=([^$'\n']+) ]] \
    && predicted_name="${BASH_REMATCH[1]}"

  [[ -n "$predicted_name" ]] || return 1

  if [[ "$network_interface_driver" == 'i40e' ]] && ! image_i40e_driver_exposes_port_name && [[ -e "/sys/class/net/$network_interface/phys_port_name" ]]; then
    local phys_port_name; phys_port_name="$(< "/sys/class/net/$network_interface/phys_port_name")"
    local stripped_name="${predicted_name%n$phys_port_name}"
    if [[ "$predicted_name" != "$stripped_name" ]]; then
      debug "# image i40e driver does not expose port name. removed phys port suffix n$phys_port_name from predicted netif name $predicted_name"
    fi
    predicted_name="$stripped_name"
  fi

  echo "$predicted_name"

  return 1
}

# check whether ipv4 addr is private
# $1 <ipv4_addr>
ipv4_addr_is_private() {
  local ipv4_addr="$1"
  network_contains_ipv4_addr 10.0.0.0/8 "$ipv4_addr" ||
  network_contains_ipv4_addr 172.16.0.0/12 "$ipv4_addr" ||
  network_contains_ipv4_addr 192.168.0.0/16 "$ipv4_addr"
}

# calc ipv4 addr netmask
# $1 <ipv4_addr>
ipv4_addr_netmask() {
  local ipv4_addr="$1"
  local ipv4_addr_suffix="$(ip_addr_suffix "$ipv4_addr")"
  ip_addr_without_suffix "$(int_to_ipv4_addr "$((0xffffffff << (32 - ipv4_addr_suffix)))")"
}

# get network interface ipv4 gateway
# $1 <network_interface>
network_interface_ipv4_gateway() {
  local network_interface="$1"
  [[ "$(ip -4 r l 0/0 dev "$network_interface")" =~ ^default\ via\ ([^\ $'\n']+) ]] && echo "${BASH_REMATCH[1]}"
}

# get network interface ipv6 gateway
# $1 <network_interface>
network_interface_ipv6_gateway() {
  local network_interface="$1"
  [[ "$(ip -6 r l ::/0 dev "$network_interface")" =~ ^default\ via\ ([^\ $'\n']+) ]] && echo "${BASH_REMATCH[1]}"
}

# gen ifcfg script centos
# $1 <network_interface>
gen_ifcfg_script_centos() {
  local network_interface="$1"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))

  echo "### $COMPANY installimage"
  echo
  echo "DEVICE=$predicted_network_interface_name"
  echo 'ONBOOT=yes'
  echo -n 'BOOTPROTO='
  # dhcp
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  if ipv4_addr_is_private "$gateway" && is_virtual_machine; then
    echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
    echo 'dhcp'
  # static config
  else
    echo 'none'
  fi

  # static config
  if ((${#ipv4_addrs[@]} > 0)); then
    if ! ipv4_addr_is_private "$gateway" || ! is_virtual_machine; then
      local address="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
      # ! pointtopoint
      if ipv4_addr_is_private "$gateway" || is_virtual_machine; then
        local netmask="$(ip_addr_suffix "${ipv4_addrs[0]}")"
      # pointtopoint
      else
        local netmask='32'
      fi

      echo "configuring ipv4 addr ${ipv4_addrs[0]} for $predicted_network_interface_name" >&2
      echo "IPADDR=$address"
      echo "PREFIX=$netmask"
      if [[ -n "$gateway" ]]; then
        # pointtopoint
        # only for centos < 8
        if ! ipv4_addr_is_private "$gateway" && ! is_virtual_machine && ( ((IMG_VERSION < 80)) || ((IMG_VERSION == 610)) || is_cpanel_install ); then
          local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"

          echo "configuring host route $network via $gateway" >&2
          echo "SCOPE=\"peer $gateway\""
        # ! pointtopoint
        else
          echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
          echo "GATEWAY=$gateway"
        fi
      fi
    fi
  fi

  echo 'DEFROUTE=yes'

  # almalinux,centos,rockylinux >= 9 let NetworkManager handle DNS
  if rhel_9_based_image && uses_network_manager; then
    local i=0
    local max_i=2
    while read nsaddr; do
      ((i+=1))
      echo "DNS$i=$nsaddr"
      ((i >= max_i)) && break
    done < <(randomized_nsaddrs)
  fi

  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv6_addrs[@]} == 0)) && return

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo
  echo 'IPV6INIT=yes'
  echo "IPV6ADDR=${ipv6_addrs[0]}"
  echo 'IPV6_AUTOCONF=no'

  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"
  [[ -z "$gatewayv6" ]] && return

  echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
  echo "IPV6_DEFAULTGW=$gatewayv6"

  echo 'IPV6_DEFROUTE=yes'

  # Without NetworkManager IPV6_DEFAULTDEV is required
  uses_network_manager || echo "IPV6_DEFAULTDEV=$predicted_network_interface_name"
}

# gen route script
# $1 <gateway>
gen_route_script() {
  local gateway="$1"

  echo "### $COMPANY installimage"
  echo
  echo 'ADDRESS0=0.0.0.0'
  echo 'NETMASK0=0.0.0.0'
  echo "GATEWAY0=$gateway"
}

# setup /etc/sysconfig/network-scripts for centos
setup_etc_sysconfig_network_scripts_centos() {
  debug '# setup /etc/sysconfig/network-scripts'

  # clean up /etc/sysconfig/network-scripts
  find "$FOLD/hdd/etc/sysconfig/network-scripts" -type f \( -name 'ifcfg-*' -or -name 'route-*' \) -and -not -name 'ifcfg-lo' -delete

  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    local ip_addrs=("${ipv4_addrs[@]}" $(network_interface_ipv6_addrs "$network_interface"))
    ((${#ip_addrs[@]} == 0)) && continue

    local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
    local ifcfg_script="/etc/sysconfig/network-scripts/ifcfg-$predicted_network_interface_name"

    debug "# setting up $ifcfg_script"
    gen_ifcfg_script_centos "$network_interface" > "$FOLD/hdd/$ifcfg_script" 2> >(debugoutput)

    local gateway="$(network_interface_ipv4_gateway "$network_interface")"
    # ! pointtopoint
    if [[ -z "$gateway" ]] || ipv4_addr_is_private "$gateway" || is_virtual_machine; then
      continue
    fi

    # dont create route script for centos 8
    ((IMG_VERSION >= 80)) && ((IMG_VERSION != 610)) && ! is_cpanel_install && return

    local route_script="/etc/sysconfig/network-scripts/route-$predicted_network_interface_name"
    debug "# setting up $route_script"
    gen_route_script "$gateway" > "$FOLD/hdd/$route_script" 2> >(debugoutput)
  done < <(physical_network_interfaces)
}

# gen ifcfg script suse
# $1 <network_interface>
gen_ifcfg_script_suse() {
  local network_interface="$1"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"

  echo "### $COMPANY installimage"
  echo
  echo 'STARTMODE="auto"'
  # dhcp
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  if ipv4_addr_is_private "$gateway" && is_virtual_machine; then
    echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
    echo 'BOOTPROTO="dhcp4"'
    echo 'DHCLIENT_SET_HOSTNAME="no"'
  # static config
  else
    if ((${#ipv4_addrs[@]} > 0)); then
      local ipaddr="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
      # ! pointtopoint
      if ipv4_addr_is_private "$gateway" || is_virtual_machine; then
        local netmask="$(ip_addr_suffix "${ipv4_addrs[0]}")"
      # pointtopoint
      else
        local netmask='32'
      fi
      echo "configuring ipv4 addr $ipaddr/$netmask for $predicted_network_interface_name" >&2
      echo "IPADDR=\"$ipaddr/$netmask\""

      # pointtopoint
      if [[ -n "$gateway" ]] && ! ipv4_addr_is_private "$gateway" && ! is_virtual_machine; then
        local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"

        echo "configuring host route $network via $gateway" >&2
        echo "REMOTE_IPADDR=\"$gateway\""
      fi
    fi
  fi

  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv6_addrs[@]} == 0)) && return

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo
  echo -n 'IPADDR'
  ((${#ipv4_addrs[@]} > 0)) && echo -n '_0'
  echo "=\"${ipv6_addrs[0]}\""
}

# gen ifroute script
# $1 <network_interface>
gen_ifroute_script() {
  local network_interface="$1"
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"

  echo "### $COMPANY installimage"
  echo
  # static config
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  if [[ -n "$gateway" ]] && ! ipv4_addr_is_private "$gateway" || ! is_virtual_machine; then
    echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
    echo "default $gateway - $predicted_network_interface_name"
  fi
  [[ -z "$gatewayv6" ]] && return
  echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
  echo "default $gatewayv6 - $predicted_network_interface_name"
}

# gen routes script
# $1 <network_interface>
gen_routes_script() {
  local network_interface="$1"
  gen_ifroute_script "$network_interface"
}

# setup /etc/sysconfig/network scripts for suse
setup_etc_sysconfig_network_scripts_suse() {
  debug '# setup /etc/sysconfig/network scripts'

  # clean up /etc/sysconfig/network
  find "$FOLD/hdd/etc/sysconfig/network" -type f \( -name 'ifcfg-*' -or -name 'ifroute-*' -or -name 'routes' \) -and -not -name 'ifcfg-lo' -delete

  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    local ip_addrs=("${ipv4_addrs[@]}" $(network_interface_ipv6_addrs "$network_interface"))
    ((${#ip_addrs[@]} == 0)) && continue

    local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
    local ifcfg_script="/etc/sysconfig/network/ifcfg-$predicted_network_interface_name"

    debug "# setting up $ifcfg_script"
    gen_ifcfg_script_suse "$network_interface" > "$FOLD/hdd/$ifcfg_script" 2> >(debugoutput)

    # local route_script="/etc/sysconfig/network/ifroute-$predicted_network_interface_name"
    local routes_script="/etc/sysconfig/network/routes"

    # debug "# setting up $route_script"
    # gen_ifroute_script "$network_interface" > "$FOLD/hdd/$route_script" 2> >(debugoutput)
    debug "# setting up $routes_script"
    gen_routes_script "$network_interface" > "$FOLD/hdd/$routes_script" 2> >(debugoutput)
  done < <(physical_network_interfaces)
}

# gen /etc/network/interfaces entry
# $1 <network_interface>
gen_etc_network_interfaces_entry() {
  local network_interface="$1"
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv4_addrs[@]} == 0)) && ((${#ipv6_addrs[@]} == 0)) && return

  echo
  echo "auto $predicted_network_interface_name"
  if ((${#ipv4_addrs[@]} > 0)); then
    echo -n "iface $predicted_network_interface_name inet "
    # dhcp
    local gateway="$(network_interface_ipv4_gateway "$network_interface")"
    if ipv4_addr_is_private "$gateway" && is_virtual_machine; then
      echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
      echo 'dhcp'
    # static config
    else
      local address="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
      local netmask="$(ipv4_addr_netmask "${ipv4_addrs[0]}")"

      echo "configuring ipv4 addr ${ipv4_addrs[0]} for $predicted_network_interface_name" >&2
      echo 'static'
      echo "  address $address"
      echo "  netmask $netmask"
      if [[ -n "$gateway" ]]; then
        echo "configuring ipv4 gateway $gateway for $predicted_network_interface_name" >&2
        echo "  gateway $gateway"
      fi
      # pointtopoint
      if ! ipv4_addr_is_private "$gateway" && ! is_virtual_machine; then
        local network="$(ipv4_addr_network "${ipv4_addrs[0]}")"
        echo "configuring host route $network via $gateway" >&2
        echo "  # route $network via $gateway"
        # echo "  up ip route add $network via $gateway dev $predicted_network_interface_name"

        local network_without_suffix="$(ip_addr_without_suffix "$network")"
        echo "  up route add -net $network_without_suffix netmask $netmask gw $gateway dev $predicted_network_interface_name"
      fi
    fi
  fi

  ((${#ipv6_addrs[@]} == 0)) && return

  ((${#ipv4_addrs[@]} > 0)) && echo

  local addressv6="$(ip_addr_without_suffix "${ipv6_addrs[0]}")"
  local netmaskv6="$(ip_addr_suffix "${ipv6_addrs[0]}")"
  local gatewayv6="$(network_interface_ipv6_gateway "$network_interface")"

  echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
  echo "iface $predicted_network_interface_name inet6 static"
  echo "  address $addressv6"
  echo "  netmask $netmaskv6"
  if [[ -n "$gatewayv6" ]]; then
    echo "configuring ipv6 gateway $gatewayv6 for $predicted_network_interface_name" >&2
    echo "  gateway $gatewayv6"
  fi
}

# setup /etc/network/interfaces
setup_etc_network_interfaces() {
  debug '# setting up /etc/network/interfaces'

  {
    echo "### $COMPANY installimage"
    echo
    if [[ -e "$FOLD/hdd/etc/network/interfaces.d" ]]; then
      echo 'source /etc/network/interfaces.d/*'
      echo
    fi
    echo 'auto lo'
    echo 'iface lo inet loopback'
    echo 'iface lo inet6 loopback'
    while read network_interface; do
      gen_etc_network_interfaces_entry "$network_interface"
    done < <(physical_network_interfaces)
  } > "$FOLD/hdd/etc/network/interfaces" 2> >(debugoutput)
}

# # check whether installed os supports predictable network interface names
# installed_os_supports_predictable_network_interface_names() {
#   installed_os_uses_systemd && (($(installed_os_systemd_version) >= 197))
# }

# # disable predictable network interface names
# disable_predictable_network_interface_names() {
#   debug '# disabling predictable network interface names'
# 
#   ln -s /dev/null "$FOLD/hdd/etc/systemd/network/99-default.link"
# }

# get network interface mac
network_interface_mac() {
  local network_interface="$1"
  cat "/sys/class/net/$network_interface/address"
}

# gen persistent net rule
gen_persistent_net_rule() {
  local network_interface="$1"
  local mac="$(network_interface_mac "$network_interface")"
  printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$mac" "$network_interface"
}

# gen persistent net rules
gen_persistent_net_rules() {
  echo "### $COMPANY installimage"
  echo
  while read network_interface; do
    gen_persistent_net_rule "$network_interface"
  done < <(physical_network_interfaces)
}

# setup persistent net rules
setup_persistent_net_rules() {
  local persistent_net_rules_file='/etc/udev/rules.d/70-persistent-net.rules'
  debug "# setting up $persistent_net_rules_file"
  gen_persistent_net_rules > "$FOLD/hdd/$persistent_net_rules_file"
}

netplan_version() {
  execute_chroot_command_wo_debug $'dpkg-query \'--showformat=${Version}\' --show \'netplan.io\'' | cut -d '-' -f 1
}

netplan_version_ge() {
  local other="$1"
  [[ "$(echo -e "$(netplan_version)\n$other" | sort -V | head -n 1)" == "$other" ]]
}

# gen /etc/netplan/01-netcfg.yaml entry
# $1 <network_interface>
gen_etc_netplan_01_netcfg_yaml_entry() {
  local network_interface="$1"
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  ((${#ipv4_addrs[@]} == 0)) && ((${#ipv6_addrs[@]} == 0)) && return
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  echo "    $predicted_network_interface_name:"
  local addresses=()
  if ((${#ipv4_addrs[@]} > 0)); then
    # dhcp
    local gateway4="$(network_interface_ipv4_gateway "$network_interface")"
    if ipv4_addr_is_private "$gateway4" && is_virtual_machine; then
      echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
      local dhcp4=true
      local gateway4=false
    # static config
    else
      local ipaddr="$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
      # ! pointtopoint
      if ipv4_addr_is_private "$gateway4" || is_virtual_machine; then
        local netmask="$(ip_addr_suffix "${ipv4_addrs[0]}")"
      # pointtopoint
      else
        if [[ -n "$gateway4" ]]; then
          local netmask='32'
        else
          local netmask="$(ip_addr_suffix "${ipv4_addrs[0]}")"
        fi
      fi
      echo "configuring ipv4 addr $ipaddr/$netmask for $predicted_network_interface_name" >&2
      local dhcp4=false
      addresses+=("$ipaddr/$netmask")
      if [[ -n "$gateway4" ]]; then
        echo "configuring ipv4 gateway $gateway4 for $predicted_network_interface_name" >&2
      else
        gateway4=false
      fi
    fi
  fi
  if ((${#ipv6_addrs[@]} > 0)); then
    echo "configuring ipv6 addr ${ipv6_addrs[0]} for $predicted_network_interface_name" >&2
    addresses+=("${ipv6_addrs[0]}")
  fi
  case "${#addresses[@]}" in
    0);;
    # 1)
    #   echo "      addresses: [ ${addresses[0]} ]"
    # ;;
    *)
      echo '      addresses:'
      for address in "${addresses[@]}"; do
        echo "        - $address"
      done
    ;;
  esac
  [[ "$dhcp4" == true ]] && echo '      dhcp4: true'
  # ! pointtopoint
  if netplan_version > /dev/null && [[ -n "$(netplan_version)" ]]; then
    local force_pre_103_style=0
    [[ "$IAM" == ubuntu ]] && ((IMG_VERSION < 2110)) && force_pre_103_style=1
    (( force_pre_103_style == 1 )) && debug 'netplan config: forcing the use of gateway4 and gateway6'
    if netplan_version_ge '0.103' && (( force_pre_103_style == 0 )); then
      debug 'netplan config: using default routes instead of gateway4 and gateway6'
      local gateway6="$(network_interface_ipv6_gateway "$network_interface")"
      { { [[ -n "$gateway4" ]] && [[ "$gateway4" != false ]]; } || [[ -n "$gateway6" ]]; } && echo '      routes:'
      if [[ -n "$gateway4" ]] && [[ "$gateway4" != false ]]; then
        if ipv4_addr_is_private "$gateway4" || is_virtual_machine; then
          echo '        - to: default'
          echo "          via: $gateway4"
        else
          echo '        - on-link: true'
          echo '          to: 0.0.0.0/0'
          echo "          via: $gateway4"
        fi
      fi
      if [[ -n "$gateway6" ]]; then
        echo "configuring ipv6 gateway $gateway6 for $predicted_network_interface_name" >&2
        echo '        - to: default'
        echo "          via: $gateway6"
      fi
    else
      debug 'netplan config: using gateway4 and gateway6 instead of default route'
      if [[ -n "$gateway4" ]] && [[ "$gateway4" != false ]]; then
        if ipv4_addr_is_private "$gateway4" || is_virtual_machine; then
          echo "      gateway4: $gateway4"
        else
          echo '      routes:'
          echo '        - on-link: true'
          echo '          to: 0.0.0.0/0'
          echo "          via: $gateway4"
        fi
      fi
      local gateway6="$(network_interface_ipv6_gateway "$network_interface")"
      if [[ -n "$gateway6" ]]; then
        echo "configuring ipv6 gateway $gateway6 for $predicted_network_interface_name" >&2
        echo "      gateway6: $gateway6"
      fi
    fi
  else
    debug 'fatal: can not query netplan version'
    return 1
  fi
  if [[ "$gateway4" != false ]]; then
    echo '      nameservers:'
    echo '        addresses:'
    while read nsaddr; do
      echo "          - $nsaddr"
    done < <(randomized_nsaddrs)
  fi
}

# setup /etc/netplan/01-netcfg.yaml
setup_etc_netplan_01_netcfg_yaml() {
  debug '# setting up /etc/netplan/01-netcfg.yaml'
  local netplan_configuration_file="$FOLD/hdd/etc/netplan/01-netcfg.yaml"
  {
    echo "### $COMPANY installimage"
    echo 'network:'
    echo '  version: 2'
    echo '  renderer: networkd'
    echo '  ethernets:'
    while read network_interface; do
      gen_etc_netplan_01_netcfg_yaml_entry "$network_interface" || return 1
    done < <(physical_network_interfaces)
  } > "$netplan_configuration_file" 2> >(debugoutput)
  chmod 600 "$netplan_configuration_file"
}

# gen network file
# $1 <network_interface>
gen_network_file() {
  local network_interface="$1"
  echo "### $COMPANY installimage"
  echo '[Match]'
  local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
  echo "Name=$predicted_network_interface_name"
  echo
  echo '[Network]'
  local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
  local gateway="$(network_interface_ipv4_gateway "$network_interface")"
  if ((${#ipv4_addrs[@]} > 0)); then
    # dhcp
    if ipv4_addr_is_private "$gateway" && is_virtual_machine; then
      echo "configuring dhcpv4 for $predicted_network_interface_name" >&2
      echo 'DHCP=ipv4'
    # static config
    else
      # ! pointtopoint
      if ipv4_addr_is_private "$gateway" || is_virtual_machine; then
        echo "Address=${ipv4_addrs[0]}"
      fi
    fi
  fi
  local ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
  if ((${#ipv6_addrs[@]} > 0)); then
    echo "Address=${ipv6_addrs[0]}"
  fi
  local gateway4="$(network_interface_ipv4_gateway "$network_interface")"
  if ((${#ipv4_addrs[@]} > 0)) && [[ -n "$gateway4" ]]; then
    echo "Gateway=$gateway4"
  fi
  gateway6="$(network_interface_ipv6_gateway "$network_interface")"
  if ((${#ipv6_addrs[@]} > 0)) && [[ -n "$gateway6" ]]; then
    echo "Gateway=$gateway6"
  fi
  if ((${#ipv4_addrs[@]} > 0)) && ! ipv4_addr_is_private "$gateway4" && ! is_virtual_machine; then
    echo
    echo '[Address]'
    echo "Address=$(ip_addr_without_suffix "${ipv4_addrs[0]}")"
    local peer="$(network_interface_ipv4_gateway "$network_interface")/32"
    echo "Peer=$peer"
  fi
}

# setup /etc/systemd/network files
setup_etc_systemd_network_files() {
  debug '# setup /etc/systemd/network files'
  while read network_interface; do
    local ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    local ip_addrs=("${ipv4_addrs[@]}" $(network_interface_ipv6_addrs "$network_interface"))
    ((${#ip_addrs[@]} == 0)) && continue
    local predicted_network_interface_name="$(predict_network_interface_name "$network_interface")"
    local network_file="/etc/systemd/network/10-$predicted_network_interface_name.network"
    debug "# setting up $network_file"
    gen_network_file "$network_interface" > "$FOLD/hdd/$network_file" 2> >(debugoutput)
  done < <(physical_network_interfaces)
}

# setup network config
setup_network_config() {
  debug '# setup network config'

  case "$IAM" in
    centos|rockylinux|almalinux|rhel)
      setup_etc_sysconfig_network
      setup_etc_sysconfig_network_scripts_centos
    ;;
    suse) setup_etc_sysconfig_network_scripts_suse;;
    debian) setup_etc_network_interfaces;;
    ubuntu)
     if ((IMG_VERSION >= 1710)); then
       setup_etc_netplan_01_netcfg_yaml || return 1
       local stderr_file="$FOLD/netplan_generate.stderr"
       if ! execute_chroot_command_wo_debug 'netplan generate' 2> "$stderr_file"; then
         debug 'fatal: netplan generate failed:'
         cat "$stderr_file" | debugoutput
         return 1
       fi
       # delete chroot related lines from $stderr_file
       sed -i '/Running in chroot/d' "$stderr_file"
       if [[ -s "$stderr_file" ]]; then
         debug 'fatal: netplan generate stderr not empty:'
         cat "$stderr_file" | debugoutput
         return 1
       fi
     else
       setup_etc_network_interfaces
     fi
    ;;
    archlinux)
      setup_etc_systemd_network_files
      systemd_nspawn 'systemctl enable systemd-networkd' || return 1
    ;;
    *) return 1;;
  esac

  if ! use_predictable_network_interface_names; then
    # predictable network interface names are disabled using the net.ifnames=0 kernel parameter
    # disable_predictable_network_interface_names
    setup_persistent_net_rules
  fi
}

# get BOOTIF mac from kernel cmdline
bootif_mac() {
  xargs -a /proc/cmdline -n 1 | grep ^BOOTIF= | cut -d '-' -f 2- | tr '-' ':'
}

# get bootif via kernel commandline BOOTIF mac
bootif() {
  local bootif_mac
  bootif_mac="$(bootif_mac)"
  while read network_interface; do
    [[ "$(network_interface_mac "$network_interface")" == "$bootif_mac" ]] || continue

    echo "$network_interface"
    break
  done < <(physical_network_interfaces)
}

# get v4 main network interface
v4_main_network_interface() {
  # prefer bootif
  local bootif
  bootif="$(bootif)"
  if [[ -n "$bootif" ]]; then
    echo "$bootif"
    return
  fi

  # legacy behaviour. use first netif with an IPv4
  local ipv4_addrs
  while read network_interface; do
    ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    ((${#ipv4_addrs[@]} == 0)) && continue

    debug "v4 main netif lookup: using v4 main netif $network_interface found via legacy lookup loop"
    echo "$network_interface"
    break
  done < <(physical_network_interfaces)
}

# get v6 main network interface
v6_main_network_interface() {
  # prefer bootif
  local bootif
  bootif="$(bootif)"
  if [[ -n "$bootif" ]]; then
    echo "$bootif"
    return
  fi

  # legacy behaviour. use first netif with an IPv6
  local ipv6_addrs
  while read network_interface; do
    ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
    ((${#ipv6_addrs[@]} == 0)) && continue

    debug "v6 main netif lookup: using v6 main netif $network_interface found via legacy lookup loop"
    echo "$network_interface"
    break
  done < <(physical_network_interfaces)
}

# get main mac from either v4 main netif or v6 main netif
main_mac() {
  local v4_main_network_interface
  v4_main_network_interface="$(v4_main_network_interface)"
  local mac="$(network_interface_mac "$v4_main_network_interface")"
  if [[ -n "$mac" ]]; then
    echo "$mac"
    return
  fi

  local v6_main_network_interface
  v6_main_network_interface="$(v6_main_network_interface)"
  local mac="$(network_interface_mac "$v6_main_network_interface")"
  if [[ -n "$mac" ]]; then
    echo "$mac"
    return
  fi

  debug "fatal: dont know main MAC"
  return 1
}

# first ipv4 of main v4 netif
v4_main_ip() {
  local v4_main_network_interface
  v4_main_network_interface="$(v4_main_network_interface)"
  local ipv4_addrs
  ipv4_addrs=($(network_interface_ipv4_addrs "$v4_main_network_interface"))
  echo "${ipv4_addrs[0]}"
}

# first ipv6 of main v6 netif
v6_main_ip() {
  local v6_main_network_interface
  v6_main_network_interface="$(v6_main_network_interface)"
  local ipv6_addrs
  ipv6_addrs=($(network_interface_ipv6_addrs "$v6_main_network_interface"))
  echo "${ipv6_addrs[0]}"
}

has_no_public_ip() {
  local ipv6_addrs
  while read network_interface; do
    ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
    ((${#ipv6_addrs[@]} > 1)) && return 1

    while read ip; do
      ipv4_addr_is_private "$ip" || return 1
    done < <(network_interface_ipv4_addrs "$network_interface")
  done < <(physical_network_interfaces)

  return 0
}

has_no_ipv6() {
  local ipv6_addrs
  while read network_interface; do
    ipv6_addrs=($(network_interface_ipv6_addrs "$network_interface"))
    ((${#ipv6_addrs[@]} > 0)) && return 1
  done < <(physical_network_interfaces)

  return 0
}

has_no_ipv4() {
  local ipv4_addrs
  while read network_interface; do
    ipv4_addrs=($(network_interface_ipv4_addrs "$network_interface"))
    ((${#ipv4_addrs[@]} > 0)) && return 1
  done < <(physical_network_interfaces)

  return 0
}

has_dualstack() {
  !has_no_ipv6 && !has_no_ipv4
}

v6_first() {
  # force v4 first
  ((IPV4_ONLY == 1)) && return 1

  # dont use v6 first for dualstack yet
  has_no_ipv4 # || has_dualstack
}

v4_first() {
  # force v4 first
  ((IPV4_ONLY == 1)) && return 0

  has_no_public_ip || has_no_ipv6
}

ip_addr_last_octet() {
  local ip_addr="$1"
  [[ "$ip_addr" =~ [.:]([^.:]*)$ ]] && echo "${BASH_REMATCH[1]}"
}

randomized_nsaddrs() {
  local v6_nsaddrs=($(shuf -e "${DNSRESOLVER_V6[@]}"))
  local v4_nsaddrs=($(shuf -e "${DNSRESOLVER[@]}"))

  if v6_first; then
    first_pool=("${v6_nsaddrs[@]}")
    second_pool=("${v4_nsaddrs[@]}")
  else
    first_pool=("${v4_nsaddrs[@]}")
    second_pool=("${v6_nsaddrs[@]}")
  fi

  local spread_by_last_octet=()
  local nsaddr
  local i=${#second_pool[@]}
  for addr in "${first_pool[@]}"; do
    ((i == 0)) && break

    for ((j=0; j<${#second_pool[@]}; j++)); do
      nsaddr="${second_pool[$j]}"
      [[ "$(ip_addr_last_octet "$addr")" == "$(ip_addr_last_octet "$nsaddr")" ]] && continue

      spread_by_last_octet+=("$nsaddr")
      i=$((i - 1))
    done
  done
  second_pool=("${spread_by_last_octet[@]}")

  local nsaddrs=()
  local maxns=4
  local i=-1
  nsaddr=
  until (( ${#nsaddrs[@]} == $maxns || (${#first_pool[@]} == 0 && ${#second_pool[@]} == 0) )); do
    i=$((i + 1))

    nsaddr="${first_pool[$i]}"
    if [[ -n "$nsaddr" ]]; then
      nsaddrs+=("$nsaddr")
      first_pool=("${first_pool[@]:$i}")
    fi

    nsaddr="${second_pool[$i]}"
    if [[ -z "$nsaddr" ]] || (( ${#nsaddrs[@]} == $maxns )); then continue; fi
    nsaddrs+=("$nsaddr")
    second_pool=("${second_pool[@]:$i}")
  done

  for nsaddr in "${nsaddrs[@]}"; do echo "$nsaddr"; done
}

# vim: ai:ts=2:sw=2:et
