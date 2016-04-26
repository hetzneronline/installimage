#!/bin/bash

#
# set all necessary vars and functions
#
# (c) 2007-2016, Hetzner Online GmbH
#


DEBUGFILE=/root/debug.txt


# set up standard env
export SCRIPTPATH; SCRIPTPATH=$(dirname "$0")
export DISABLEDFILE="$SCRIPTPATH/disabled"
export SETUPFILE="$SCRIPTPATH/setup.sh"
export AUTOSETUPFILE="$SCRIPTPATH/autosetup.sh"
export AUTOSETUPCONFIG="/autosetup"
export INSTALLFILE="$SCRIPTPATH/install.sh"
export FUNCTIONSFILE="$SCRIPTPATH/functions.sh"
export GETOPTIONSFILE="$SCRIPTPATH/get_options.sh"
export STANDARDCONFIG="$SCRIPTPATH/standard.conf"
export CONFIGSPATH="$SCRIPTPATH/configs"
export POSTINSTALLPATH="$SCRIPTPATH/post-install"
export IMAGESPATH="$SCRIPTPATH/../images/"
export OLDIMAGESPATH="$SCRIPTPATH/../images.old/"
export IMAGESPATHTYPE="local"
export IMAGESEXT="tar.gz"
export IMAGEFILETYPE="tgz"
export COMPANY_PUBKEY="$SCRIPTPATH/gpg/public-key.asc"
export COMPANY="Hetzner Online GmbH"
export C_SHORT="hetzner"
export LOCKFILE='/run/lock/installimage'

export MODULES="virtio_pci virtio_blk via82cxxx sata_via sata_sil sata_nv sd_mod ahci atiixp raid0 raid1 raid5 raid6 raid10 3w-xxxx 3w-9xxx aacraid powernow-k8"
export STATSSERVER="213.133.99.103"
export HDDMINSIZE="7000000"

export NAMESERVER=("213.133.98.98" "213.133.99.99" "213.133.100.100")
export DNSRESOLVER_V6=("2a01:4f8:0:a111::add:9898" "2a01:4f8:0:a102::add:9999" "2a01:4f8:0:a0a1::add:1010")
export NTPSERVERS=("ntp1.hetzner.de" "ntp2.hetzner.com" "ntp3.hetzner.net")
export AUTH_DNS1="ns1.first-ns.de"
export AUTH_DNS2="robotns2.second-ns.de"
export AUTH_DNS3="robotns3.second-ns.com"

export DEFAULTPARTS="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 all"
export DEFAULTPARTS_BIG="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 1024G\nPART /home ext4 all"
export DEFAULTPARTS_LARGE="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 2014G\nPART /home ext4 all"
export DEFAULTPARTS_VSERVER="PART / ext3 all"
export DEFAULTPARTS_CLOUDSERVER="PART / ext4 all"
export DEFAULTSWRAID="1"
export DEFAULTTWODRIVESWRAIDLEVEL="1"
export DEFAULTTHREEDRIVESWRAIDLEVEL="5"
export DEFAULTFOURDRIVESWRAIDLEVEL="6"
export DEFAULTLVM="0"
export DEFAULTLOADER="grub"
export DEFAULTGOVERNOR="ondemand"

export V6ONLY="0"

# dialog settings
export DIATITLE="$COMPANY"
export OSMENULIST=(
"Debian"          "(official)"
"Ubuntu"          "(official)"
"CentOS"          "(official)"
"openSUSE"        "(official)"
"Archlinux"       "(!!NO SUPPORT!!)"
"Virtualization"  "(!!NO SUPPORT!!)"
"old images"      "(!!NO SUPPORT!!)"
"custom image"    "(blanco config for user images)"
)

export PROXMOX3_BASE_IMAGE="Debian-79-wheezy-64-minimal"
export PROXMOX4_BASE_IMAGE="Debian-84-jessie-64-minimal"

# all files that are added to this array will be removed by our cleanup
# function
export TEMP_FILES=(${LOCKFILE})

# the following mount points must be umounted before a systemd nspawn container
# can be started
export SYSTEMD_NSPAWN_BLACKLISTED_MOUNT_POINTS=(
  /dev
  /proc
  /sys
)
export SYSTEMD_NSPAWN_ROOT_DIR=${FOLD}/hdd
export SYSTEMD_NSPAWN_HELPER_SERVICE_FILE=/etc/systemd/system/multi-user.target.wants/installimage-systemd-nspawn-helper.service
export SYSTEMD_NSPAWN_SERVICE_FILE=/lib/systemd/system/installimage-systemd-nspawn.service
export SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST=${FOLD}/installimage-umounted-mount-points

TEMP_FILES+=(
  ${SYSTEMD_NSPAWN_ROOT_DIR}/${SYSTEMD_NSPAWN_HELPER_SERVICE_FILE}
  ${SYSTEMD_NSPAWN_SERVICE_FILE}
  ${SYSTEMD_NSPAWN_UMOUNTED_MOUNT_POINT_LIST}
)

export CPANEL_INSTALLER_SRC=http://mirror.hetzner.de/tools/cpanelinc/cpanel

export PLESK_INSTALLER_SRC=http://mirror.hetzner.de/tools/parallels/plesk
export PLESK_STD_VERSION=PLESK_12_5_30
export PLESK_DOWNLOAD_RETRY_COUNT=999
export PLESK_COMPONENTS=(
  awstats
  bind
  config-troubleshooter
  dovecot
  drweb
  heavy-metal-skin
  horde
  l10n
  mailman
  mod-bw
  mod_fcgid
  mod_python
  mysqlgroup
  nginx
  panel
  php5.6
  phpgroup
  pmm
  postfix
  proftpd
  psa-firewall
  roundcube
  spamassassin
  Troubleshooter
  webalizer
  web-hosting
  webservers
)

export RED="\033[1;31m"
export GREEN="\033[1;32m"
export YELLOW="\033[1;33m"
export BLUE="\033[0;34m"
export MANGENTA="\033[0;35m"
export CYAN="\033[1;36m"
export GREY="\033[0;37m"
export WHITE="\033[1;39m"
export NOCOL="\033[00m"

# write log entries in debugfile - single line as second argument
debug() {
  local line="${@}"
  #(
  #  flock 200
    printf '[%(%H:%M:%S)T] %s\n' -1 "${line}" >> ${DEBUGFILE}
  #) 200> ${LOCKFILE}
}

# write log entries in debugfile - multiple lines at once
debugoutput() {
  while read -r line; do
    #(
    #  flock 200
      printf '[%(%H:%M:%S)T] :   %s\n' -1 "${line}" >> ${DEBUGFILE}
    #) 200> ${LOCKFILE}
  done
}

. "$FUNCTIONSFILE"

for f in $SCRIPTPATH/*.functions.sh; do
  . $f
done

# vim: ai:ts=2:sw=2:et
