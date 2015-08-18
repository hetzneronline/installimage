#!/bin/bash

#
# CoreOS specific functions 
#
# originally written by Markus Schade
# (c) 2014-2015, Hetzner Online GmbH
#

IMAGE_PUBKEY=$SCRIPTPATH"/gpg/coreos-pubkey.asc"

# create partitons on the given drive
# create_partitions "DRIVE"
create_partitions() {
  touch $FOLD/fstab
  return 0
}

make_swraid() {
  return 0
}


mount_partitions() {
  return 0
}

make_lvm() {
  return 0
}

format_partitions() {
  return 0
}


# validate image with detached signature
#validate_image() {
#  # no detached sign found
#  return 2
#}

# extract image file to hdd
extract_image() {
  local COMPRESSION=""
  if [ "$1" -a "$2" ]; then
    case "$2" in
      bin)
        COMPRESSION=""
       ;;
      bgz)
        COMPRESSION="gzip"
       ;;
      bbz)
        COMPRESSION="bzip2"
       ;;
      bxz)
        COMPRESSION="xz"
       ;;
      *)return 1;;
    esac

    # extract image with given compression
    $COMPRESSION -d --stdout $EXTRACTFROM > ${DRIVE1}; EXITCODE=$?

    if [ "$EXITCODE" -eq "0" ]; then
      echo "sucess " | debugoutput
      # inform the OS of partition table changes
      blockdev --rereadpt "${DRIVE1}"
      return 0
    else
#      wipefs --all "${DRIVE1}"
      return 1
    fi
  fi
}

setup_network_config() {
  return 0
}


# generate_mdadmconf "NIL"
generate_config_mdadm() {
  return 0
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  return 0
}


set_udev_rules() {
  return 0
}

# copy_mtab "NIL"
copy_mtab() {
  return 0
}

generate_new_sshkeys() {
  return 0
}

generate_ntp_config() {
  if [ -f "$CLOUDINIT" ]; then
    echo -e "write_files:" >>$CLOUDINIT
    echo -e "  - path: /etc/ntp.conf\n    content: |" >>$CLOUDINIT
    echo -e "      # hetzner ntp servers \n      server ntp1.hetzner.de iburst\n      server ntp2.hetzner.com iburst\n      server ntp3.hetzner.net iburst" >>$CLOUDINIT | debugoutput
    echo -e "      # - Allow only time queries, at a limited rate.\n      # - Allow all local queries (IPv4, IPv6)\n      restrict default nomodify nopeer noquery limited kod\n      restrict 127.0.0.1\n      restrict [::1]" >>$CLOUDINIT
    return 0
  else
    return 1
  fi
}

set_hostname() {
  if [ -f "$CLOUDINIT" ]; then
    echo -e "hostname: $1\n" >>$CLOUDINIT
    return 0
  else
    return 1
  fi
}

setup_cpufreq() {
  return 0
}

generate_resolvconf() {
    echo -e "write_files:" >> $CLOUDINIT
    echo -e "  - path: /etc/resolv.conf\n    permissions: 0644\n    owner: root\n    content: |" >> $CLOUDINIT

    # IPV4
    if [ "$V6ONLY" -eq 1 ]; then
      debug "# skipping IPv4 DNS resolvers"
    else
      for index in $(shuf --input-range=0-$(( ${#NAMESERVER[*]} - 1 )) | tr '\n' ' ') ; do
        echo "      nameserver ${NAMESERVER[$index]}" >> $CLOUDINIT
      done
    fi

    # IPv6
    if [ -n "$DOIPV6" ]; then
      for index in $(shuf --input-range=0-$(( ${#DNSRESOLVER_V6[*]} - 1 )) | tr '\n' ' ') ; do
        echo "      nameserver ${DNSRESOLVER_V6[$index]}" >> $CLOUDINIT
      done
    fi
  return 0
}

generate_hosts() {
  return 0
}

generate_sysctlconf() {
  return 0
}

set_rootpassword() {
  if [ "$1" -a "$2" ]; then
    if [ "$2" != '*' ]; then
      echo -e "users:" >> $CLOUDINIT
      echo -e "  - name: core" >> $CLOUDINIT
      echo -e "    passwd: $2" >> $CLOUDINIT
      echo -e "  - name: root" >> $CLOUDINIT
      echo -e "    passwd: $2" >> $CLOUDINIT
    fi
    return 0
  else
    return 1
  fi
}

# set sshd PermitRootLogin
set_ssh_rootlogin() {
  if [ "$1" ]; then
     local permit="$1"
     case $permit in
       yes|no|without-password|forced-commands-only)
        cat << EOF >> $CLOUDINIT
write_files:
  - path: /etc/ssh/sshd_config
    permissions: 0600
    owner: root:root
    content: |
      # Use most defaults for sshd configuration.
      UsePrivilegeSeparation sandbox
      Subsystem sftp internal-sftp

      PermitRootLogin $permit
      PasswordAuthentication yes
EOF
       ;;
       *)
         debug "invalid option for PermitRootLogin"
         return 1
       ;;
     esac
  else
     return 1
  fi
}

# copy_ssh_keys $OPT_SSHKEYS_URL 
copy_ssh_keys() {
   if [ "$1" ]; then
     local key_url="$1"
     echo -e "ssh_authorized_keys:" >> $CLOUDINIT
     case $key_url in
       https:*|http:*|ftp:*)
         wget $key_url -O "$FOLD/authorized_keys"
     	 while read line; do
	   echo -e "  - $line" >> $CLOUDINIT
         done < "$FOLD/authorized_keys"
       ;;
       *)
     	 while read line; do
	   echo -e "  - $line" >> $CLOUDINIT
         done < $key_url 
       ;;
     esac
   else
     return 1
   fi
}


# generate_config_grub <version>
generate_config_grub() {
  return 0
}

write_grub() {
  return 0
}

add_coreos_oem_scripts() {
  if [ "$1" ]; then
    local mntpath=$1
  
    # add netname simplify script (use eth names)
    local scriptpath="$mntpath/bin"
    local scriptfile="$scriptpath/netname.sh"
    if [ ! -d "$scriptpath" ]; then
      mkdir -p $scriptpath
    fi
    cat << EOF >> $scriptfile
#! /bin/bash

IFINDEX=\$1
echo "ID_NET_NAME_SIMPLE=eth\$((\${IFINDEX} - 2))"
EOF
    chmod a+x $scriptfile
    scriptfile="$scriptpath/rename-interfaces.sh"
    cat << EOF >> $scriptfile
#! /bin/bash

INTERFACES=\$(ip link show | gawk -F ':' '/^[0-9]+/ { print \$2 }' | tr -d ' ' | sed 's/lo//')
for iface in \${INTERFACES}; do
	ip link set \${iface} down
	udevadm test /sys/class/net/\${iface}
done
EOF
    chmod a+x $scriptfile
  fi
}

add_coreos_oem_cloudconfig() {
  if [ "$1" ]; then
    local mntpath=$1
    local cloudconfig="$mntpath/cloud-config.yml"
    echo -e "#cloud-config" > $cloudconfig
    if ! isVServer; then
      cat << EOF >> $cloudconfig
write_files:
  - path: /run/udev/rules.d/79-netname.rules
    permissions: 444
    content: |
      SUBSYSTEM!="net", GOTO="netname_end"
      ACTION!="add", GOTO="netname_end"
      ENV{ID_BUS}!="pci", GOTO="netname_end"

      IMPORT{program}="/usr/share/oem/bin/netname.sh \$env{IFINDEX}"

      NAME=="", ENV{ID_NET_NAME_SIMPLE}!="", NAME="\$env{ID_NET_NAME_SIMPLE}"

      LABEL="netname_end"

coreos:
    units:
      - name: rename-network-interfaces.service
        command: start
        runtime: yes
        content: |
          [Unit]
          Before=user-config.target

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/usr/bin/systemctl stop systemd-networkd
          ExecStart=/usr/share/oem/bin/rename-interfaces.sh
          ExecStart=/usr/bin/systemctl start systemd-networkd
    oem:
      id: baremetal
      name: Hetzner Cloud on Root
      home-url: http://www.hetzner.com
      bug-report-url: https://github.com/coreos/bugs/issues
EOF
    else
      cat << EOF >> $cloudconfig
    oem:
      id: vserver
      name: Hetzner vServer
      home-url: http://www.hetzner.com
      bug-report-url: https://github.com/coreos/bugs/issues
EOF
    fi
  fi
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
    local ROOT_DEV=$(blkid -t "LABEL=ROOT" -o device "${DRIVE1}"*)
    local OEM_DEV=$(blkid -t "LABEL=OEM" -o device "${DRIVE1}"*)
    local is_ext4=$(blkid -o value $ROOT_DEV | grep ext4)
    if [ -n "$is_ext4" ]; then
      mount "${ROOT_DEV}" "$FOLD/hdd" 2>&1 | debugoutput ; EXITCODE=$?
    else
      mount -t btrfs -o subvol=root "${ROOT_DEV}" "$FOLD/hdd" 2>&1 | debugoutput ; EXITCODE=$?
    fi
    [ "$EXITCODE" -ne "0" ] && return 1

   # mount OEM partition as well
    mount "${OEM_DEV}" "$FOLD/hdd/usr" 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    if ! isVServer; then
      add_coreos_oem_scripts "$FOLD/hdd/usr"
    fi
    add_coreos_oem_cloudconfig "$FOLD/hdd/usr"

    mkdir -p "$FOLD/hdd/var/lib/coreos-install"
    cat $CLOUDINIT | debugoutput
    cp "${CLOUDINIT}" "$FOLD/hdd/var/lib/coreos-install/user_data"
    
  return 0
}

