#!/bin/bash
#
# CentOS specific functions 
#
# originally written by Florian Wicke and David Mayr
# (c) 2008-2015, Hetzner Online GmbH



# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ "$1" -a "$2" ]; then
    # good we have a device and a MAC
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    echo -e "### Hetzner Online GmbH - installimage" > $UDEVFILE
    echo -e "# device: $1" >> $UDEVFILE
    echo -e "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$2\", KERNEL==\"eth*\", NAME=\"$1\"" >> $UDEVFILE

    local upper_mac="$(echo "$2" | awk '{ print toupper($0) }')"

    NETWORKFILE="$FOLD/hdd/etc/sysconfig/network"
    echo -e "### Hetzner Online GmbH - installimage" > $NETWORKFILE 2>>$DEBUGFILE
    echo -e "# general networking" >> $NETWORKFILE 2>>$DEBUGFILE
    echo -e "NETWORKING=yes" >> $NETWORKFILE 2>>$DEBUGFILE

    CONFIGFILE="$FOLD/hdd/etc/sysconfig/network-scripts/ifcfg-$1"
    ROUTEFILE="$FOLD/hdd/etc/sysconfig/network-scripts/route-$1"

    echo -e "### Hetzner Online GmbH - installimage" > $CONFIGFILE 2>>$DEBUGFILE
    echo -e "#" >> $CONFIGFILE 2>>$DEBUGFILE
    if ! is_private_ip "$3"; then 
      echo -e "# Note for customers who want to create bridged networking for virtualisation:" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "# Gateway is set in separate file" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "# Do not forget to change interface in file route-$1 and rename this file" >> $CONFIGFILE 2>>$DEBUGFILE
    fi
    echo -e "#" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "# device: $1" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "DEVICE=$1" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "BOOTPROTO=none" >> $CONFIGFILE 2>>$DEBUGFILE
    echo -e "ONBOOT=yes" >> $CONFIGFILE 2>>$DEBUGFILE

    if [ "$3" -a "$4" -a "$5" -a "$6" -a "$7" ]; then
      echo -e "HWADDR=$upper_mac" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "IPADDR=$3" >> $CONFIGFILE 2>>$DEBUGFILE
      if is_private_ip "$3"; then 
        echo -e "NETMASK=$5" >> $CONFIGFILE 2>>$DEBUGFILE
        echo -e "GATEWAY=$6" >> $CONFIGFILE 2>>$DEBUGFILE
      else
        echo -e "NETMASK=255.255.255.255" >> $CONFIGFILE 2>>$DEBUGFILE
        echo -e "SCOPE=\"peer $6\"" >> $CONFIGFILE 2>>$DEBUGFILE

        echo -e "### Hetzner Online GmbH - installimage" > $ROUTEFILE 2>>$DEBUGFILE
        echo -e "# routing for eth0" >> $ROUTEFILE 2>>$DEBUGFILE
        echo -e "ADDRESS0=0.0.0.0" >> $ROUTEFILE 2>>$DEBUGFILE
        echo -e "NETMASK0=0.0.0.0" >> $ROUTEFILE 2>>$DEBUGFILE
        echo -e "GATEWAY0=$6" >> $ROUTEFILE 2>>$DEBUGFILE
      fi
    fi

    if [ "$8" -a "$9" -a "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      echo -e "NETWORKING_IPV6=yes" >> $NETWORKFILE 2>>$DEBUGFILE
      echo -e "IPV6INIT=yes" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "IPV6ADDR=$8/$9" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "IPV6_DEFAULTGW=${10}" >> $CONFIGFILE 2>>$DEBUGFILE
      echo -e "IPV6_DEFAULTDEV=$1" >> $CONFIGFILE 2>>$DEBUGFILE
    fi 

    # set duplex/speed
    if ! isNegotiated && ! isVServer; then
      echo -e "ETHTOOL_OPTS=\"speed 100 duplex full autoneg off\"" >> $CONFIGFILE 2>>$DEBUGFILE
    fi

    # remove all hardware info from image (CentOS 5)
    if [ -f $FOLD/hdd/etc/sysconfig/hwconf ]; then
      echo -e "" > $FOLD/hdd/etc/sysconfig/hwconf
    fi

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

    # pick the latest kernel
    VERSION="$(ls -r -1 $FOLD/hdd/boot/vmlinuz-* | head -n1 |cut -d '-' -f 2-)"

    if [ $IMG_VERSION -lt 60 ] ; then 
      MODULESFILE="$FOLD/hdd/etc/modprobe.conf"
      # previously we added an alias for eth0 based on the niclist (static
      # pci-id->driver mapping) of the old rescue. But the new rescue mdev/udev
      # So we only add aliases for the controller
      echo -e "### Hetzner Online GmbH - installimage" > $MODULESFILE 2>>$DEBUGFILE
      echo -e "# load all modules" >> $MODULESFILE 2>>$DEBUGFILE
      echo -e "" >> $MODULESFILE 2>>$DEBUGFILE

      echo -e "# hdds" >> $MODULESFILE 2>>$DEBUGFILE
      HDDDEV=""
      for hddmodule in $MODULES; do
        if [ "$hddmodule" != "powernow-k8" -a "$hddmodule" != "via82cxxx" -a "$hddmodule" != "atiixp" ]; then
          echo -e "alias scsi_hostadapter$HDDDEV $hddmodule" >> $MODULESFILE 2>>$DEBUGFILE
          [ -z "$HDDDEV" ] && HDDDEV="1" || HDDDEV="$(echo $[$HDDDEV+1])"
        fi
      done
      echo -e "" >> $MODULESFILE 2>>$DEBUGFILE
    elif [ $IMG_VERSION -ge 60 ] ; then 
      # blacklist some kernel modules due to bugs and/or stability issues or annoyance
      local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-hetzner.conf"
      echo -e "### Hetzner Online GmbH - installimage" > $blacklist_conf
      echo -e "### silence any onboard speaker" >> $blacklist_conf
      echo -e "blacklist pcspkr" >> $blacklist_conf
      echo -e "### i915 driver blacklisted due to various bugs" >> $blacklist_conf
      echo -e "### especially in combination with nomodeset" >> $blacklist_conf
      echo -e "blacklist i915" >> $blacklist_conf
    fi

    if [ $IMG_VERSION -ge 70 ] ; then
      DRACUTFILE="$FOLD/hdd/etc/dracut.conf.d/hetzner.conf"
      echo "add_dracutmodules+=\"mdraid lvm\"" >> $DRACUTFILE
      echo "add_drivers+=\"raid1 raid10 raid0 raid456\"" >> $DRACUTFILE
      echo "mdadmconf=\"yes\"" >> $DRACUTFILE
      echo "lvmconf=\"yes\"" >> $DRACUTFILE
      echo "hostonly=\"no\"" >> $DRACUTFILE
      echo "early_microcode=\"no\"" >> $DRACUTFILE
    fi

    if [ $IMG_VERSION -ge 70 ] ; then 
      execute_chroot_command "/sbin/dracut -f --kver $VERSION"; EXITCODE=$?
    else
      if [ $IMG_VERSION -ge 60 ] ; then 
        execute_chroot_command "/sbin/new-kernel-pkg --mkinitrd --dracut --depmod --install $VERSION"; EXITCODE=$?
      else 
        execute_chroot_command "/sbin/new-kernel-pkg --package kernel --mkinitrd --depmod --install $VERSION"; EXITCODE=$?
      fi
    fi
    return $?
  fi
}


setup_cpufreq() {
  if [ "$1" ]; then
    if isVServer; then
      debug "no powersaving on virtual machines"
    	return 0
    fi 
    if [ $IMG_VERSION -ge 70 ] ; then
      #https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System_Administrators_Guide/sec-Persistent_Module_Loading.html
      #local CPUFREQCONF="$FOLD/hdd/etc/modules-load.d/cpufreq.conf"
      debug "no cpufreq configuration necessary"
    else 
      #https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/sec-Persistent_Module_Loading.html
      local CPUFREQCONF="$FOLD/hdd/etc/sysconfig/modules/cpufreq.modules"
      echo -e "" > $CPUFREQCONF 2>>$DEBUGFILE
      echo -e "#!/bin/sh" > $CPUFREQCONF 2>>$DEBUGFILE
      echo -e "### Hetzner Online GmbH - installimage" >> $CPUFREQCONF 2>>$DEBUGFILE
      echo -e "# cpu frequency scaling" >> $CPUFREQCONF 2>>$DEBUGFILE
      echo -e "# this gets started by /etc/rc.sysinit" >> $CPUFREQCONF 2>>$DEBUGFILE
      if [ "$(check_cpu)" = "intel" ]; then
        debug "# Setting: cpufreq modprobe to intel"
        echo -e "modprobe intel_pstate >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE
        echo -e "modprobe acpi-cpufreq >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE
      else
        debug "# Setting: cpufreq modprobe to amd"
        echo -e "modprobe powernow-k8 >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE
      fi
      echo -e "cpupower frequency-set --governor $1 >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE
      chmod a+x $CPUFREQCONF >>$DEBUGFILE

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
  [ "$1" ] || return
  # we should not need to do anything, as grubby (new-kernel-pkg) should have
  # already generated a grub.conf
  if [ $IMG_VERSION -lt 70 ] ; then 
    DMAPFILE="$FOLD/hdd/boot/grub/device.map"
  else
    # even though grub2-mkconfig will generate a device.map on the fly, the
    # anaconda installer still creates this
    DMAPFILE="$FOLD/hdd/boot/grub2/device.map"
  fi
  [ -f $DMAPFILE ] && rm $DMAPFILE

  local i=0
  for i in $(seq 1 $COUNT_DRIVES) ; do
    local j="$[$i-1]"
    local disk="$(eval echo "\$DRIVE"$i)"
    echo "(hd$j) $disk" >> $DMAPFILE
  done
  cat $DMAPFILE >> $DEBUGFILE

  local elevator=''
  if isVServer; then
    elevator='elevator=noop'
  fi

  if [ $IMG_VERSION -lt 70 ] ; then 
    execute_chroot_command "cd /boot; rm -rf boot; ln -s . boot >> /dev/null 2>&1"
    execute_chroot_command "mkdir -p /boot/grub/"
    #execute_chroot_command "grub-install --no-floppy $DRIVE1 2>&1"; EXITCODE=$?

    BFILE="$FOLD/hdd/boot/grub/grub.conf"

    rm -rf "$FOLD/hdd/boot/grub/*" >> /dev/null 2>&1

    echo "#" > $BFILE 2>> $DEBUGFILE
    echo "# Hetzner Online GmbH - installimage" >> $BFILE 2>> $DEBUGFILE
    echo "# GRUB bootloader configuration file" >> $BFILE 2>> $DEBUGFILE
    echo "#" >> $BFILE 2>> $DEBUGFILE
    echo >> $BFILE 2>> $DEBUGFILE

    PARTNUM=`echo "$SYSTEMBOOTDEVICE" | rev | cut -c1`

    if [ "$SWRAID" = "0" ]; then
      PARTNUM="$[$PARTNUM - 1]"
    fi

    echo "timeout 5" >> $BFILE 2>> $DEBUGFILE
    echo "default 0" >> $BFILE 2>> $DEBUGFILE
    echo >> $BFILE 2>> $DEBUGFILE
    echo "title CentOS ($1)" >> $BFILE 2>> $DEBUGFILE
    echo "root (hd0,$PARTNUM)" >> $BFILE 2>> $DEBUGFILE
    # disable pcie active state power management. does not work as it should,
    # and causes problems with Intel 82574L NICs (onboard-NIC Asus P8B WS - EX6/EX8, addon NICs)
    [ "$(lspci -n | grep '8086:10d3')" ] && ASPM='pcie_aspm=off' || ASPM=''

    if [ $IMG_VERSION -ge 60 ]; then 
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE rd_NO_LUKS rd_NO_DM nomodeset $elevator $ASPM" >> $BFILE 2>> $DEBUGFILE
    else
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE nomodeset" >> $BFILE 2>> $DEBUGFILE
    fi
    INITRD=''
    if [ -f "$FOLD/hdd/boot/initrd-$1.img" ]; then
     INITRD="initrd"
    fi
    if [ -f "$FOLD/hdd/boot/initramfs-$1.img" ]; then
     INITRD="initramfs"
    fi
    if [ $INITRD ]; then
      echo "initrd /boot/$INITRD-$1.img" >> $BFILE 2>> $DEBUGFILE
    fi

    echo >> $BFILE 2>> $DEBUGFILE
  
    uuid_bugfix
  # TODO: let grubby add its own stuff (SYSFONT, LANG, KEYTABLE)
#  if [ $IMG_VERSION -lt 60 ] ; then 
#   execute_chroot_command "/sbin/new-kernel-pkg --package kernel --install $VERSION"; EXITCODE=$?
#  else 
#   execute_chroot_command "/sbin/new-kernel-pkg --install $VERSION"; EXITCODE=$?
#  fi
  else
    if isVServer; then
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto elevator=noop\"/"'
    else
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto\"/"'
    fi

    [ -e $FOLD/hdd/boot/grub2/grub.cfg ] && rm "$FOLD/hdd/boot/grub2/grub.cfg"
    execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"; EXITCODE=$?

  fi
  return $EXITCODE
}

write_grub() {
  if [ $IMG_VERSION -ge 70 ] ; then 
     # only install grub2 in mbr of all other drives if we use swraid
    local i=0
    for i in $(seq 1 $COUNT_DRIVES) ; do
      if [ $SWRAID -eq 1 -o $i -eq 1 ] ;  then
        local disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1" EXITCODE=$?
      fi
    done
  else 
    local i=0

    for i in $(seq 1 $COUNT_DRIVES) ; do
      if [ $SWRAID -eq 1 -o $i -eq 1 ] ;  then
        local disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "echo -e \"device (hd0) $disk\nroot (hd0,$PARTNUM)\nsetup (hd0)\nquit\" | grub --batch >> /dev/null 2>&1"
      fi
    done
  fi

  return $?
}

disabled_set_hostname() {
  local SETHOSTNAME="$1"

  hostname $SETHOSTNAME
  execute_chroot_command "hostname $SETHOSTNAME"
 
  if [ -z "$SETHOSTNAME" ]; then
    SETHOSTNAME="$IMAGENAME"
  fi
  if [ "$IMG_VERSION" -ge 70 ] ; then
    HOSTNAMEFILE="$FOLD/hdd/etc/hostname"
    echo "$SETHOSTNAME" > $HOSTNAMEFILE
    debug "# set new hostname '$SETHOSTNAME' in $HOSTNAMEFILE"
    # remove machine-id from install (will be regen upon first boot)
    echo >  $FOLD/hdd/etc/machine-id
  else
    NETWORKFILE="$FOLD/hdd/etc/sysconfig/network"
    echo -e "HOSTNAME=$SETHOSTNAME" >> $NETWORKFILE 2>>$DEBUGFILE
  fi
  
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
    echo $IMAGENAME | grep -q -i cpanel && ( setup_cpanel || return 1 )
  fi
 
  # selinux autorelabel if enabled 
  if [ "$(egrep "SELINUX=enforcing" $FOLD/hdd/etc/sysconfig/selinux)" ] ; then
    touch $FOLD/hdd/.autorelabel
  fi

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
  CPHULKDCONF="$FOLD/hdd/var/cpanel/hulkd/password"
  CPHULKDPASS=$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c16)
  ROOTPASS=$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c8)
  MYSQLCOMMAND="UPDATE mysql.user SET password=PASSWORD(\""$CPHULKDPASS"\") WHERE user='cphulkd'; \
  UPDATE mysql.user SET password=PASSWORD(\""$ROOTPASS"\") WHERE user='root';\nFLUSH PRIVILEGES;"
  echo -e "$MYSQLCOMMAND" > "$FOLD/hdd/tmp/pwchange.sql"
  debug "changing mysql passwords"
  execute_chroot_command "service mysql start --skip-grant-tables --skip-networking >/dev/null 2>&1"; EXITCODE=$?
  execute_chroot_command "mysql < /tmp/pwchange.sql >/dev/null 2>&1"; EXITCODE=$?
  execute_chroot_command "service mysql stop >/dev/null 2>&1"
  cp "$CPHULKDCONF" "$CPHULKDCONF.old"
  sed s/pass.*/"pass=\"$CPHULKDPASS\""/g "$CPHULKDCONF.old" > "$CPHULKDCONF"
  rm "$FOLD/hdd/tmp/pwchange.sql"
  rm "$CPHULKDCONF.old"

  # write password file 
  echo -e "[client]\nuser=root\npass=$ROOTPASS" > $FOLD/hdd/root/.my.cnf

  return $EXITCODE
}

#
# set the content of /var/cpanel/mainip correct
#
change_mainIP() {
  MAINIPFILE="/var/cpanel/mainip"
  debug "changing content of ${MAINIPFILE}"
  execute_chroot_command "echo -n ${IPADDR} > $MAINIPFILE"
}

#
# set the correct hostname, IP and nameserver in /etc/wwwacct.conf
#
modify_wwwacct() {
  WWWACCT="/etc/wwwacct.conf"
  NS="ns1.first-ns.de"
  NS2="robotns2.second-ns.de"
  NS3="robotns3.second-ns.com"

  debug "setting hostname in ${WWWACCT}"
  execute_chroot_command "echo \"HOST ${SETHOSTNAME}\" >> $WWWACCT"
  debug "setting IP in ${WWWACCT}"
  execute_chroot_command "echo \"ADDR ${IPADDR}\" >> $WWWACCT"
  debug "setting NS in ${WWWACCT}"
  execute_chroot_command "echo \"NS ${NS}\" >> $WWWACCT"
  execute_chroot_command "echo \"NS2 ${NS2}\" >> $WWWACCT"
  execute_chroot_command "echo \"NS3 ${NS3}\" >> $WWWACCT"
}
