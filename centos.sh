#!/bin/bash

#
# CentOS specific functions
#
# (c) 2008-2016, Hetzner Online GmbH
#


# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    # good we have a device and a MAC
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", KERNEL=="eth*", NAME="%s"\n' "$2" "$1"
    } > "$UDEVFILE"

    local upper_mac; upper_mac="$(echo "$2" | awk '{ print toupper($0) }')"

    NETWORKFILE="$FOLD/hdd/etc/sysconfig/network"
    {
      echo "### $COMPANY - installimage"
      echo "# general networking"
      echo "NETWORKING=yes"
    } > "$NETWORKFILE"

    rm -f "$FOLD/hdd/etc/sysconfig/network-scripts/ifcfg-en*"

    CONFIGFILE="$FOLD/hdd/etc/sysconfig/network-scripts/ifcfg-$1"
    ROUTEFILE="$FOLD/hdd/etc/sysconfig/network-scripts/route-$1"

    {
      echo "### $COMPANY - installimage"
      echo "#"
    } > "$CONFIGFILE"

    if ! is_private_ip "$3"; then
      {
        echo "# Note for customers who want to create bridged networking for virtualisation:"
        echo "# Gateway is set in separate file"
        echo "# Do not forget to change interface in file route-$1 and rename this file"
      } >> "$CONFIGFILE"
    fi
    {
      echo "#"
      echo "# device: $1"
      echo "DEVICE=$1"
      echo "BOOTPROTO=none"
      echo "ONBOOT=yes"
    } >> "$CONFIGFILE"

    if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
      {
        echo "HWADDR=$upper_mac"
        echo "IPADDR=$3"
      } >> "$CONFIGFILE"
      if is_private_ip "$3"; then
        {
          echo "NETMASK=$5"
          echo "GATEWAY=$6"
        } >> "$CONFIGFILE"
      else
        {
          echo "NETMASK=255.255.255.255"
          echo "SCOPE=\"peer $6\""
        } >> "$CONFIGFILE"

        {
          echo "### $COMPANY - installimage"
          echo "# routing for eth0"
          echo "ADDRESS0=0.0.0.0"
          echo "NETMASK0=0.0.0.0"
          echo "GATEWAY0=$6"
        } > "$ROUTEFILE"
      fi
    fi

    if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      echo "NETWORKING_IPV6=yes" >> "$NETWORKFILE"
      {
        echo "IPV6INIT=yes"
        echo "IPV6ADDR=$8/$9"
        echo "IPV6_DEFAULTGW=${10}"
        echo "IPV6_DEFAULTDEV=$1"
      } >> "$CONFIGFILE"
    fi

    # set duplex/speed
    if ! isNegotiated && ! isVServer; then
      echo 'ETHTOOL_OPTS="speed 100 duplex full autoneg off"' >> "$CONFIGFILE"
    fi

    # remove all hardware info from image (CentOS 5)
    if [ -f "$FOLD/hdd/etc/sysconfig/hwconf" ]; then
      echo "" > "$FOLD/hdd/etc/sysconfig/hwconf"
    fi

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    local mdadmconf="/etc/mdadm.conf"
    {
      echo "DEVICE partitions"
      echo "MAILADDR root"
    } > "$FOLD/hdd$mdadmconf"
    execute_chroot_command "mdadm --examine --scan >> $mdadmconf"; declare -i EXITCODE=$?
    return $EXITCODE
  fi
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then

    # pick the latest kernel
    VERSION="$(find "$FOLD/hdd/boot/" -name "vmlinuz-*" | cut -d '-' -f 2- | sort -V | tail -1)"

    if [ "$IMG_VERSION" -lt 60 ] ; then
      local modulesfile="$FOLD/hdd/etc/modprobe.conf"
      # previously we added an alias for eth0 based on the niclist (static
      # pci-id->driver mapping) of the old rescue. But the new rescue mdev/udev
      # So we only add aliases for the controller
      {
        echo "### $COMPANY - installimage"
        echo "# load all modules"
        echo ""
        echo "# hdds"
      } > "$modulesfile"

      HDDDEV=""
      for hddmodule in $MODULES; do
        if [ "$hddmodule" != "powernow-k8" ] && [ "$hddmodule" != "via82cxxx" ] && [ "$hddmodule" != "atiixp" ]; then
          echo "alias scsi_hostadapter$HDDDEV $hddmodule" >> "$modulesfile"
          HDDDEV="$((HDDDEV + 1))"
        fi
      done
      echo "" >> "$modulesfile"
    elif [ "$IMG_VERSION" -ge 60 ] ; then
      # blacklist some kernel modules due to bugs and/or stability issues or annoyance
      local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-$C_SHORT.conf"
      {
        echo "### $COMPANY - installimage"
        echo "### silence any onboard speaker"
        echo "blacklist pcspkr"
        echo "### i915 driver blacklisted due to various bugs"
        echo "### especially in combination with nomodeset"
        echo "blacklist i915"
      } > "$blacklist_conf"
    fi

    if [ "$IMG_VERSION" -ge 70 ] ; then
      local dracutfile="$FOLD/hdd/etc/dracut.conf.d/99-$C_SHORT.conf"
      {
        echo "### $COMPANY - installimage"
        echo 'add_dracutmodules+="lvm mdraid"'
        echo 'add_drivers+="raid0 raid1 raid10 raid456"'
        #echo 'early_microcode="no"'
        echo 'hostonly="no"'
        echo 'hostonly_cmdline="no"'
        echo 'lvmconf="yes"'
        echo 'mdadmconf="yes"'
        echo 'persistent_policy="by-uuid"'
      } > "$dracutfile"
    fi

    if [ "$IMG_VERSION" -ge 70 ] ; then
      execute_chroot_command "/sbin/dracut -f --kver $VERSION"
      declare -i EXITCODE=$?
    else
      if [ "$IMG_VERSION" -ge 60 ] ; then
        execute_chroot_command "/sbin/new-kernel-pkg --mkinitrd --dracut --depmod --install $VERSION"
        declare -i EXITCODE=$?
      else
        execute_chroot_command "/sbin/new-kernel-pkg --package kernel --mkinitrd --depmod --install $VERSION"
        declare -i EXITCODE=$?
      fi
    fi
    return "$EXITCODE"
  fi
}


setup_cpufreq() {
  if [ -n "$1" ]; then
    if isVServer; then
      debug "no powersaving on virtual machines"
      return 0
    fi
    if [ "$IMG_VERSION" -ge 70 ] ; then
      #https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System_Administrators_Guide/sec-Persistent_Module_Loading.html
      #local CPUFREQCONF="$FOLD/hdd/etc/modules-load.d/cpufreq.conf"
      debug "no cpufreq configuration necessary"
    else
      #https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/sec-Persistent_Module_Loading.html
      local cpufreqconf="$FOLD/hdd/etc/sysconfig/modules/cpufreq.modules"
      {
        echo "#!/bin/sh"
        echo "### $COMPANY - installimage"
        echo "# cpu frequency scaling"
        echo "# this gets started by /etc/rc.sysinit"
      } > "$cpufreqconf"

      if [ "$(check_cpu)" = "intel" ]; then
        debug "# Setting: cpufreq modprobe to intel"
        {
          echo "modprobe intel_pstate >> /dev/null 2>&1"
          echo "modprobe acpi-cpufreq >> /dev/null 2>&1"
        } >> "$cpufreqconf"
      else
        debug "# Setting: cpufreq modprobe to amd"
        echo "modprobe powernow-k8 >> /dev/null 2>&1" >> "$cpufreqconf"
      fi
      echo "cpupower frequency-set --governor $1 >> /dev/null 2>&1" >> "$cpufreqconf"
      chmod a+x "$cpufreqconf" 2>> "$DEBUGFILE"

    return 0
    fi
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  [ -n "$1" ] || return
  # we should not have to do anything, as grubby (new-kernel-pkg) should have
  # already generated a grub.conf
  if [ "$IMG_VERSION" -lt 70 ] ; then
    DMAPFILE="$FOLD/hdd/boot/grub/device.map"
  else
    # even though grub2-mkconfig will generate a device.map on the fly, the
    # anaconda installer still creates this
    DMAPFILE="$FOLD/hdd/boot/grub2/device.map"
  fi
  [ -f "$DMAPFILE" ] && rm "$DMAPFILE"

  local -i i=0
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local j; j="$((i - 1))"
    local disk; disk="$(eval echo "\$DRIVE$i")"
    echo "(hd$j) $disk" >> "$DMAPFILE"
  done
  cat "$DMAPFILE" >> "$DEBUGFILE"

  local elevator=''
  if isVServer; then
    elevator='elevator=noop'
  fi

  if [ "$IMG_VERSION" -lt 70 ] ; then
    execute_chroot_command "cd /boot; rm -rf boot; ln -s . boot >> /dev/null 2>&1"
    execute_chroot_command "mkdir -p /boot/grub/"
    #execute_chroot_command "grub-install --no-floppy $DRIVE1 2>&1"; EXITCODE=$?

    BFILE="$FOLD/hdd/boot/grub/grub.conf"
    PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)

    if [ "$SWRAID" = "0" ]; then
      PARTNUM="$((PARTNUM - 1))"
    fi

    rm -rf "$FOLD/hdd/boot/grub/*" >> /dev/null 2>&1

    {
      echo "#"
      echo "# $COMPANY - installimage"
      echo "# GRUB bootloader configuration file"
      echo "#"
      echo ''
      echo "timeout 5"
      echo "default 0"
      echo >> "$BFILE"
      echo "title CentOS ($1)"
      echo "root (hd0,$PARTNUM)"
    } > "$BFILE" 2>> "$DEBUGFILE"

    # disable pcie active state power management. does not work as it should,
    # and causes problems with Intel 82574L NICs (onboard-NIC Asus P8B WS - EX6/EX8, addon NICs)
    lspci -n | grep -q '8086:10d3' && aspm='pcie_aspm=off' || aspm=''

    if [ "$IMG_VERSION" -ge 60 ]; then
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE rd_NO_LUKS rd_NO_DM nomodeset $elevator $aspm" >> "$BFILE"
    else
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE nomodeset" >> "$BFILE"
    fi
    INITRD=''
    if [ -f "$FOLD/hdd/boot/initrd-$1.img" ]; then
     INITRD="initrd"
    fi
    if [ -f "$FOLD/hdd/boot/initramfs-$1.img" ]; then
     INITRD="initramfs"
    fi
    if [ -n "$INITRD" ]; then
      echo "initrd /boot/$INITRD-$1.img" >> "$BFILE"
    fi
    echo "" >> "$BFILE"

    uuid_bugfix
  # TODO: add grubby stuff (SYSFONT, LANG, KEYTABLE)
  else
    if isVServer; then
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto elevator=noop\"/"'
    else
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto\"/"'
    fi

    rm -f "$FOLD/hdd/boot/grub2/grub.cfg"
    execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"; declare -i EXITCODE="$?"

  fi
  return "$EXITCODE"
}

write_grub() {
  if [ "$IMG_VERSION" -ge 70 ] ; then
    # only install grub2 in mbr of all other drives if we use swraid
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1"
        declare -i EXITCODE=$?
      fi
    done
  else
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "echo -e \"device (hd0) $disk\nroot (hd0,$PARTNUM)\nsetup (hd0)\nquit\" | grub --batch >> /dev/null 2>&1"
        declare -i EXITCODE=$?
      fi
    done
  fi

  return "$EXITCODE"
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {

  execute_chroot_command "chkconfig iptables off"

  #
  # setup env in cpanel image
  #
  debug "# Testing and setup of cpanel image"
  if [ -f "$FOLD/hdd/etc/wwwacct.conf" ] && [ -f "$FOLD/hdd/etc/cpupdate.conf" ] ; then
    grep -q -i cpanel <<< "$IMAGE_FILE" && {
      setup_cpanel || return 1
    }
  fi

  # selinux autorelabel if enabled
  egrep -q "SELINUX=enforcing" "$FOLD/hdd/etc/sysconfig/selinux" &&
    touch "$FOLD/hdd/.autorelabel"

  return 0
}

setup_cpanel() {
  randomize_cpanel_mysql_passwords
  change_mainIP
  modify_wwwacct
}

#
# randomize mysql passwords in cpanel image
#
randomize_cpanel_mysql_passwords() {
  local cphulkdconf; cphulkdconf="$FOLD/hdd/var/cpanel/hulkd/password"
  local cphulkdpass; cphulkdpass=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c16)
  local rootpass; rootpass=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c8)
  local mysqlcommand;
  mysqlcommand="UPDATE mysql.user SET password=PASSWORD('$cphulkdpass') WHERE user='cphulkd'; \
    UPDATE mysql.user SET password=PASSWORD('$rootpass') WHERE user='root'; \
    FLUSH PRIVILEGES;"
  echo -e "$mysqlcommand" > "$FOLD/hdd/tmp/pwchange.sql"
  debug "changing mysql passwords"
  if [ "$IMG_VERSION" -lt 70 ] ; then
    execute_chroot_command "service mysql start --skip-grant-tables --skip-networking >/dev/null 2>&1"; EXITCODE=$?
    execute_chroot_command "mysql < /tmp/pwchange.sql >/dev/null 2>&1"; EXITCODE=$?
    execute_chroot_command "service mysql stop >/dev/null 2>&1"
  else
    local override_dir="$FOLD/hdd/etc/systemd/system/mysql.service.d"
    local mysql_override="$override_dir/override.conf"
    mkdir -p "$override_dir"
    {
      echo "[Service]"
      echo "ExecStart="
      echo "ExecStart=/usr/bin/mysqld_safe --skip-grant-tables --skip-networking"
    } > "$mysql_override"
    local helper_script=${FOLD}/hdd/helper.sh
    {
      echo '#!/usr/bin/env bash'
      echo 'trap "rm ${0}" EXIT'
      echo 'systemctl start mysql.service'
      echo 'echo ERROR > /tmp/buff'
      # mysql becomes unresponsive from time to time
      echo 'while cat /tmp/buff | grep -q ERROR; do'
      echo '  mysql < /tmp/pwchange.sql &> /tmp/buff'
      echo 'done'
      echo 'rm /tmp/buff'
      echo 'systemctl stop mysql.service'
    } > "${helper_script}"
    chmod a+x "${helper_script}"
    execute_nspawn_command "/helper.sh"; EXITCODE=$?
    rm -rf "$override_dir"
  fi

  cp "$cphulkdconf" "$cphulkdconf.old"
  sed s/pass.*/"pass=\"$cphulkdpass\""/g "$cphulkdconf.old" > "$cphulkdconf"
  rm "$FOLD/hdd/tmp/pwchange.sql"
  rm "$cphulkdconf.old"

  # write password file
  {
    echo "[client]"
    echo "user=root"
    echo "password=$rootpass"
  } > "$FOLD/hdd/root/.my.cnf"

  return "$EXITCODE"
}

#
# set the content of /var/cpanel/mainip correct
#
change_mainIP() {
  local mainipfile="/var/cpanel/mainip"
  debug "changing content of ${mainipfile}"
  echo -n "${IPADDR}" > "$FOLD/hdd/$mainipfile"
}

#
# set the correct hostname, IP and nameserver in /etc/wwwacct.conf
#
modify_wwwacct() {
  local wwwacct="/etc/wwwacct.conf"
  local wfile="$FOLD/hdd/$wwwacct"

  debug "setting hostname in ${wwwacct}"
  echo "HOST ${NEWHOSTNAME}" >> "$wfile"

  debug "setting IP in ${wwwacct}"
  echo "ADDR ${IPADDR}" >> "$wfile"

  debug "setting NS in ${wwwacct}"
  {
    echo "NS ${AUTH_DNS1}"
    echo "NS2 ${AUTH_DNS2}"
    echo "NS3 ${AUTH_DNS3}"
  } >> "$wfile"

}

# vim: ai:ts=2:sw=2:et
