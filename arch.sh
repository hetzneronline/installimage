#!/bin/bash

#
# Archlinux specific functions 
#
# originally written by Markus Schade 
# (c) 2013-2015, Hetzner Online GmbH
#


# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ "$1" -a "$2" ]; then
    # good we have a device and a MAC
    CONFIGFILE="$FOLD/hdd/etc/systemd/network/50-hetzner.network"
    UDEVFILE="$FOLD/hdd/etc/udev/rules.d/80-net-setup-link.rules"

    echo -e "### Hetzner Online GmbH - installimage" > $UDEVFILE
    echo -e "# device: $1" >> $UDEVFILE
    echo -e "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$2\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"$1\"" >> $UDEVFILE

    echo -e "### Hetzner Online GmbH - installimage" > $CONFIGFILE
    echo -e "# device: $1" >> $CONFIGFILE
    echo -e "[Match]" >> $CONFIGFILE
    echo -e "MACAddress=$2" >> $CONFIGFILE
    echo -e "" >> $CONFIGFILE

    echo -e "[Network]" >> $CONFIGFILE
    if [ "$8" -a "$9" -a "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      echo -e "Address=$8/$9" >> $CONFIGFILE
      echo -e "Gateway=${10}" >> $CONFIGFILE	
      echo -e "" >> $CONFIGFILE
    fi

    if [ "$3" -a "$4" -a "$5" -a "$6" -a "$7" ]; then
      debug "setting up ipv4 networking $3/$5 via $6"
      echo -e "Address=$3/$CIDR" >> $CONFIGFILE
      echo -e "Gateway=$6" >> $CONFIGFILE
      echo -e "" >> $CONFIGFILE

      if ! is_private_ip "$3"; then 
        echo -e "[Route]" >> $CONFIGFILE
        echo -e "Destination=$7/$CIDR" >> $CONFIGFILE
        echo -e "Gateway=$6" >> $CONFIGFILE
      fi
    fi

    execute_chroot_command "systemctl enable systemd-networkd.service"

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ "$1" ]; then
    MDADMCONF="/etc/mdadm.conf"
    echo "DEVICES /dev/[hs]d*" > $FOLD/hdd$MDADMCONF
    echo "MAILADDR root" >> $FOLD/hdd$MDADMCONF
    execute_chroot_command "mdadm --examine --scan >> $MDADMCONF"; EXITCODE=$?
    return $EXITCODE
  fi
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ "$1" ]; then
    local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-hetzner.conf"
    echo -e "### Hetzner Online GmbH - installimage" > $blacklist_conf
    echo -e "### silence any onboard speaker" >> $blacklist_conf
    echo -e "blacklist pcspkr" >> $blacklist_conf
    echo -e "blacklist snd_pcsp" >> $blacklist_conf
    echo -e "### i915 driver blacklisted due to various bugs" >> $blacklist_conf
    echo -e "### especially in combination with nomodeset" >> $blacklist_conf
    echo -e "blacklist i915" >> $blacklist_conf
    echo -e "### mei driver blacklisted due to serious bugs" >> $blacklist_conf
    echo -e "blacklist mei" >> $blacklist_conf
    echo -e "blacklist mei-me" >> $blacklist_conf

    execute_chroot_command 'sed -i /etc/mkinitcpio.conf -e "s/^HOOKS=.*/HOOKS=\"base udev autodetect modconf block mdadm lvm2 filesystems keyboard fsck\"/"'
    execute_chroot_command "mkinitcpio -p linux"; EXITCODE=$?

    return $EXITCODE
  fi
}

setup_cpufreq() {
  if [ "$1" ]; then
    if ! isVServer; then
      CPUFREQCONF="$FOLD/hdd/etc/default/cpupower"
      sed -i -e "s/#governor=.*/governor'$1'/" $CPUFREQCONF
      execute_chroot_command "systemctl enable cpupower"
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
  EXITCODE=0
  execute_chroot_command "rm -rf /boot/grub; mkdir -p /boot/grub/ >> /dev/null 2>&1"
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"nomodeset\"/"'
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT=console/"'

  execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg 2>&1"

  execute_chroot_command "grub-install --no-floppy --recheck $DRIVE1 2>&1"; EXITCODE=$?

  # only install grub2 in mbr of all other drives if we use swraid
  if [ "$SWRAID" = "1" ] ;  then
    local i=2
    while [ `eval echo \\$DRIVE${i}` ]; do
      local TARGETDRIVE=`eval echo \\$DRIVE${i}`
      execute_chroot_command "grub-install --no-floppy --recheck $TARGETDRIVE 2>&1"
      let i=i+1
    done
  fi
  uuid_bugfix

  return $EXITCODE
}


#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {

  execute_chroot_command "pacman-key --init"
  execute_chroot_command "pacman-key --populate archlinux"
  execute_chroot_command "systemctl enable sshd"
  execute_chroot_command "systemctl enable haveged"
  execute_chroot_command "systemctl enable cronie"
  execute_chroot_command "systemctl enable systemd-timesyncd"

  return 0
}

# validate image with detached signature
validate_image() {
  # no detached sign found
  return 2
}

# extract image file to hdd
extract_image() {
  LANG=C pacstrap -m -a $FOLD/hdd base btrfs-progs cpupower cronie findutils gptfdisk grub haveged openssh vim wget 2>&1 | debugoutput

  if [ "$EXITCODE" -eq "0" ]; then
    cp -r "$FOLD/fstab" "$FOLD/hdd/etc/fstab" 2>&1 | debugoutput

    #timezone - we are in Germany
    execute_chroot_command "ln -s /usr/share/timezone/Europe/Berlin /etc/localtime"
    echo en_US.UTF-8 UTF-8 > $FOLD/hdd/etc/locale.gen
    echo de_DE.UTF-8 UTF-8 >> $FOLD/hdd/etc/locale.gen
    execute_chroot_command "locale-gen"

    echo > $FOLD/hdd/etc/locale.conf
    echo "LANG=de_DE.UTF-8" >> $FOLD/hdd/etc/locale.conf
    echo "LC_MESSAGES=C" >> $FOLD/hdd/etc/locale.conf

    echo > $FOLD/hdd/etc/vconsole.conf
    echo "KEYMAP=de" >> $FOLD/hdd/etc/vconsole.conf
    echo "FONT=LatArCyrHeb-16" >> $FOLD/hdd/etc/vconsole.conf

    
    return 0 
  else
    return 1
  fi
}
