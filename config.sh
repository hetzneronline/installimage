#!/bin/bash

#
# set all necessary vars and functions
#
# (c) 2007-2018, Hetzner Online GmbH
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
export COMPANY_PUBKEYS=(
  "$COMPANY_PUBKEY"
  "$SCRIPTPATH/gpg/public-key-2018.asc"
)
export COMPANY="Hetzner Online GmbH"
export C_SHORT="hetzner"
export LOCKFILE='/run/lock/installimage'
export SYSTEMD_NSPAWN_TMP_DIR="$FOLD/systemd_nspawn"

export MODULES="virtio_pci virtio_blk via82cxxx sata_via sata_sil sata_nv sd_mod ahci atiixp raid0 raid1 raid5 raid6 raid10 3w-xxxx 3w-9xxx aacraid powernow-k8"
export STATSSERVER="88.198.31.148"
export HDDMINSIZE="7000000"

export NAMESERVER=("213.133.98.98" "213.133.99.99" "213.133.100.100")
export DNSRESOLVER_V6=("2a01:4f8:0:1::add:9898" "2a01:4f8:0:1::add:9999" "2a01:4f8:0:1::add:1010")
export NTPSERVERS=("ntp1.hetzner.de" "ntp2.hetzner.com" "ntp3.hetzner.net")
export AUTH_DNS1="ns1.first-ns.de"
export AUTH_DNS2="robotns2.second-ns.de"
export AUTH_DNS3="robotns3.second-ns.com"

export DEFAULTPARTS="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 all"
export DEFAULTPARTS_BIG="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 1024G\nPART /home ext4 all"
export DEFAULTPARTS_LARGE="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 2014G\nPART /home ext4 all"
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

export UEFI="0"
declare -x -i BTRFS=0

# dialog settings
export DIATITLE="$COMPANY"
export OSMENULIST=(
  "Debian"       "(Official)"
  "Ubuntu"       "(Official)"
  "CentOS"       "(Official)"
  "Arch Linux"   "(Official)"
  "Other"        "(!!NO SUPPORT!!)"
  "Old images"   "(!!NO SUPPORT!!)"
  "Custom image" "(Blanco config for user images)"
)

export PROXMOX4_BASE_IMAGE="Debian-811-jessie-64-minimal"
export PROXMOX5_BASE_IMAGE="Debian-913-stretch-64-minimal"
export PROXMOX6_BASE_IMAGE="Debian-107-buster-64-minimal"

export CPANEL_INSTALLER_SRC=http://mirror.hetzner.de/tools/cpanelinc/cpanel

export PLESK_INSTALLER_SRC=http://mirror.hetzner.de/tools/parallels/plesk
export PLESK_MIRROR=http://mirror.hetzner.de/plesk
export PLESK_STD_VERSION=PLESK_18_0_33
export PLESK_DOWNLOAD_RETRY_COUNT=999
export PLESK_COMPONENTS=(
  awstats
  bind
  config-troubleshooter
  dovecot
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
