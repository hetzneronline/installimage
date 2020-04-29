#!/bin/bash

#
# Ubuntu specific functions
#
# (c) 2007-2018, Hetzner Online GmbH
#

# setup_network_config "$ETH" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    elif [ -f "$FOLD/hdd/etc/udev/rules.d/80-net-setup-link.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/80-net-setup-link.rules"
    else
      UDEVFILE="/dev/null"
    fi
    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$2" "$1"
    } > "$UDEVFILE"

    [ -d "$FOLD/hdd/etc/systemd/network" ] && rm -f "$FOLD"/hdd/etc/systemd/network/*

    if [ "$IMG_VERSION" -ne 1510 ]; then
      CONFIGFILE="$FOLD/hdd/etc/network/interfaces"

      {
        echo "### $COMPANY - installimage"
        echo "# Loopback device:"
        echo "auto lo"
        echo "iface lo inet loopback"
        echo "iface lo inet6 loopback"
        echo ""
      } > "$CONFIGFILE"
      if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
        echo "# device: $1" >> "$CONFIGFILE"
        if is_private_ip "$6" && isVServer; then
          {
            echo "auto  $1"
            echo "iface $1 inet dhcp"
          } >> "$CONFIGFILE"
        else
          {
            echo "auto  $1"
            echo "iface $1 inet static"
            echo "  address   $3"
            echo "  netmask   $5"
            echo "  gateway   $6"
            if ! is_private_ip "$3" || ! isVServer; then
              echo "  # default route to access subnet"
              echo "  up route add -net $7 netmask $5 gw $6 $1"
            fi
          } >> "$CONFIGFILE"
        fi
      fi

      if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
        debug "setting up ipv6 networking $8/$9 via ${10}"
        {
          echo ""
          echo "iface $1 inet6 static"
          echo "  address $8"
          echo "  netmask $9"
          echo "  gateway ${10}"
        } >> "$CONFIGFILE"
      fi

      #
      # set duplex speed
      #
      if ! isNegotiated && ! isVServer; then
        {
          echo "  # force full-duplex for ports without auto-neg"
          echo "  post-up mii-tool -F 100baseTx-FD $1"
        } >> "$CONFIGFILE"
      fi

      return 0
    else
      CONFIGFILE="$FOLD/hdd/etc/systemd/network/50-$C_SHORT.network"

      {
        echo "### $COMPANY - installimage"
        echo "# device: $1"
        echo "[Match]"
        echo "MACAddress=$2"
        echo ""
      } > "$CONFIGFILE"

      echo "[Network]" >> "$CONFIGFILE"
      if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
        debug "setting up ipv6 networking $8/$9 via ${10}"
        {
          echo "Address=$8/$9"
          echo "Gateway=${10}"
          echo ""
        } >> "$CONFIGFILE"
      fi

      if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
        debug "setting up ipv4 networking $3/$5 via $6"
        if is_private_ip "$6" && isVServer; then
          {
            echo "DHCP=ipv4"
          } >> "$CONFIGFILE"
        else
          {
            echo "Address=$3/$CIDR"
            echo "Gateway=$6"
            echo ""
          } >> "$CONFIGFILE"
          if ! is_private_ip "$3" || ! isVServer; then
            {
              echo "[Route]"
              echo "Destination=$7/$CIDR"
              echo "Gateway=$6"
            } >> "$CONFIGFILE"
          fi
        fi
      fi

      execute_chroot_command "systemctl enable systemd-networkd.service"

      return 0
    fi
  fi
}

# generate_config_mdadm "NIL"
generate_config_mdadm() {
  local mdadmconf="/etc/mdadm/mdadm.conf"
  execute_chroot_command "/usr/share/mdadm/mkconf > $mdadmconf"; declare -i EXITCODE=$?

  #
  # Enable mdadm
  #
  local mdadmdefconf="$FOLD/hdd/etc/default/mdadm"
  sed -i "s/AUTOCHECK=false/AUTOCHECK=true # modified by installimage/" \
    "$mdadmdefconf"
  sed -i "s/AUTOSTART=false/AUTOSTART=true # modified by installimage/" \
    "$mdadmdefconf"
  sed -i "s/START_DAEMON=false/START_DAEMON=true # modified by installimage/" \
    "$mdadmdefconf"
  sed -i -e "s/^INITRDSTART=.*/INITRDSTART='all' # modified by installimage/" \
    "$mdadmdefconf"
  if [ -f "$FOLD/hdd/etc/initramfs-tools/conf.d/mdadm" ]; then
    sed -i "s/BOOT_DEGRADED=false/BOOT_DEGRADED=true # modified by installimage/" \
      "$FOLD/hdd/etc/initramfs-tools/conf.d/mdadm"
  fi

  return "$EXITCODE"
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ "$1" ]; then
    local outfile; outfile=$(find "$FOLD/hdd/boot" -name "initrd.img-*" -not -regex ".*\(gz\|bak\)" -printf "%f\n" | sort -nr | head -n1)
    local kvers; kvers=$(echo "$outfile" |cut -d "-" -f2-)
    debug "# Kernel Version found: $kvers"

    if [ "$IMG_VERSION" -ge 1204 ]; then
      # blacklist various driver due to bugs and stability issues
      # required for Ubuntu 12.10 because of a kernel bug
      local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-$C_SHORT.conf"
      {
        echo "### $COMPANY - installimage"
        echo "### silence any onboard speaker"
        echo "blacklist pcspkr"
        echo "blacklist snd_pcsp"
        echo "### i915 driver blacklisted due to various bugs"
        echo "### especially in combination with nomodeset"
        echo "blacklist i915"
        echo "blacklist i915_bdw"
        echo "### mei driver blacklisted due to serious bugs"
        echo "blacklist mei"
        echo "blacklist mei-me"
        echo "blacklist sm750fb"
      } > "$blacklist_conf"
    fi

    # just make sure that we do not accidentally try to install a bootloader
    # when we haven't configured grub yet
    sed -i "s/do_bootloader = yes/do_bootloader = no/" "$FOLD/hdd/etc/kernel-img.conf"

    # well, we might just as well update all initramfs and stop findling around
    # to find out which kernel version is the latest
    execute_chroot_command "update-initramfs -u -k $kvers"; EXITCODE=$?

    # re-enable updates to grub
    sed -i "s/do_bootloader = no/do_bootloader = yes/" "$FOLD/hdd/etc/kernel-img.conf"

    return $EXITCODE
  fi
}

setup_cpufreq() {
  if [ -n "$1" ]; then
    local loadcpufreqconf="$FOLD/hdd/etc/default/loadcpufreq"
    local cpufreqconf="$FOLD/hdd/etc/default/cpufrequtils"
    {
      echo "### $COMPANY - installimage"
      echo "# cpu frequency scaling"
    } > "$cpufreqconf"
    if isVServer; then
      echo 'ENABLE="false"' > "$loadcpufreqconf"
      echo 'ENABLE="false"' >> "$cpufreqconf"
    else
      {
        echo 'ENABLE="true"'
        echo "GOVERNOR=\"$1\""
        echo 'MAX_SPEED="0"'
        echo 'MIN_SPEED="0"'
      } >> "$cpufreqconf"
    fi

    return 0
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  declare -i EXITCODE=0

  local grubdefconf="$FOLD/hdd/etc/default/grub"
  local grubconfdir="$FOLD/hdd/etc/default/grub.d"

  # this shold not be necessary anymore
#  ubuntu_grub_fix
#  execute_chroot_command "cd /boot; [ -e boot ] && rm -rf boot; ln -s . boot >> /dev/null 2>&1"

  # set linux_default in grub
  local grub_linux_default="nomodeset consoleblank=0"
  if isVServer; then
    grub_linux_default="${grub_linux_default} elevator=noop"
  else
    if [ "$IMG_VERSION" -eq 1404 ]; then
      grub_linux_default="${grub_linux_default} intel_pstate=enable"
    fi
  fi

  # H8SGL need workaround for iommu
  if [ "$MBTYPE" = 'H8SGL' ] && [ "$IMG_VERSION" -ge 1404 ] ; then
    grub_linux_default="${grub_linux_default} iommu=noaperture"
  fi

  if [ "$IMG_VERSION" -ge 1604 ] && [ "$IMG_VERSION" -lt 1710 ]; then
    grub_linux_default="${grub_linux_default} net.ifnames=0"
  fi

  if has_threadripper_cpu; then
    grub_linux_default+=' pci=nommconf'
  fi

  if is_dell_r6415; then
    grub_linux_default=${grub_linux_default/nomodeset }
  fi

  if [ -d "$grubconfdir" ]; then
    # this needs to end in .cfg, otherwise grub-mkconfig will not read it"
    grubdefconf="$grubconfdir/hetzner.cfg"
    {
      echo "GRUB_HIDDEN_TIMEOUT_QUIET=false"
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_linux_default}\""
    } >> "$grubdefconf"

  else
    sed -i "$grubdefconf" -e "s/^GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=5/" -e "s/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=false/"
    sed -i "$grubdefconf" -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_linux_default}\"/"
  fi

  {
    echo ""
    echo "# only use text mode - other modes may scramble screen"
    echo 'GRUB_GFXPAYLOAD_LINUX="text"'
  } >> "$grubdefconf"

  if [ "$UEFI" -eq 1 ]; then
    # ubuntu always installs to removable path as well (which is what we want)
    # unless grub2/no_efi_extra_removable is set to true
    execute_chroot_command "echo 'set grub2/update_nvram false' | debconf-communicate"
  fi

  # create /run/lock if it didn't exist because it is needed by grub-mkconfig
  mkdir -p "$FOLD/hdd/run/lock"

  execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg 2>&1"
  if [ "$UEFI" -eq 1 ]; then
    local efi_target="x86_64-efi"
    local efi_dir="/boot/efi"
    local efi_grub_options="--no-floppy --no-nvram --removable"
    # if/after installing grub-efi-amd64-signed, this will always install the "static" grubx64.efi
    execute_chroot_command "grub-install --target=${efi_target} --efi-directory=${efi_dir} ${efi_grub_options} 2>&1"
    declare -i EXITCODE=$?
    local shimdir="$FOLD/hdd/usr/lib/shim"
    if [ -d "$shimdir" ]; then
      cp "$shimdir/*" "$FOLD/hdd/boot/efi/EFI/ubuntu/"
    fi
  else
    # only install grub2 in mbr of all other drives if we use swraid
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE$i")"
        execute_chroot_command "grub-install --no-floppy --recheck $disk 2>&1"
      fi
    done
  fi

  if ((IMG_VERSION >= 1604)); then
    debconf_set_grub_install_devices #|| return 1
  fi

  uuid_bugfix

  PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)
  if [ "$SWRAID" = "0" ]; then
    PARTNUM="$((PARTNUM - 1))"
  fi


  return "$EXITCODE"
}

disable_ttyvtdisallocate() {
  # TTYVTDisallocate=yes may seriously mess up the login screen
  mkdir -p "$FOLD/hdd/etc/systemd/system/getty@tty1.service.d"
  {
    echo "### $COMPANY installimage"
    echo
    echo '[Service]'
    echo 'TTYVTDisallocate=no'
  } > "$FOLD/hdd/etc/systemd/system/getty@tty1.service.d/override.conf"
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  randomize_mdadm_checkarray_cronjob_time
  if nextcloud_install; then
    setup_nextcloud || return 1
  fi
  ((IMG_VERSION >= 1804)) && disable_ttyvtdisallocate

  disable_resume
  return 0
}

randomize_mdadm_checkarray_cronjob_time() {
  local mdcron; mdcron="$FOLD/hdd/etc/cron.d/mdadm"
  if [ -f "$mdcron" ] && grep -q checkarray "$mdcron"; then
    hour=$(((RANDOM % 4) + 1))
    minute=$(((RANDOM % 59) + 1))
    day=$(((RANDOM % 28) + 1))
    debug "# Randomizing cronjob run time for mdadm checkarray: day $day @ $hour:$minute"

    sed -i -e "s/^[* 0-9]*root/$minute $hour $day * * root/" -e "s/ &&.*]//" \
      "$mdcron"
  else
    debug "# No /etc/cron.d/mdadm found to randomize cronjob run time"
  fi
}

ubuntu_grub_fix() {
  local mapper="$FOLD/hdd/dev/mapper"
  local tempfile="$FOLD/hdd/tmp/mapper.tmp"

  ls -l "$mapper" > "$tempfile"
  grep -v "total" "$tempfile" | grep -v "crw" | while read -r line; do
    local dmdevice volgroup
    volgroup=$(echo "$line" | cut -d " " -f9)
    dmdevice=$(echo "$line" | cut -d "/" -f2)

    rm "$mapper/$volgroup"
    cp -R "$FOLD/hdd/dev/$dmdevice" "$mapper/$volgroup"
  done
  rm "$tempfile"
}

# vim: ai:ts=2:sw=2:et
