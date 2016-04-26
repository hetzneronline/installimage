#!/bin/bash

#
# skip menu - use "autosetup" file
#
# (c) 2008-2016, Hetzner Online GmbH
#

# read global variables and functions
. /tmp/install.vars


# check if the script is temporary disabled due some maintenance or something
debug "# checking if the script is disabled"
if [ -f "$DISABLEDFILE" ]; then
 debug "=> script is DISABLED"
 echo_red "Due to maintenance the installimage-script is temporarily unavailable.\nWe are sorry for the inconvenience."
 exit 1
fi


# display information about autosetup
echo ""
echo -e "\033[01;32mFound AUTOSETUP file '$AUTOSETUPCONFIG'\033[00m"
echo -e "\033[01;33mRunning unattended installimage installation ...\033[00m"
echo ""
grep -v "^#" "$FOLD/install.conf" | grep -v "^$"
echo ""
echo ""


# validate config
VALIDATED="false"
CANCELLED="false"
while [ "$VALIDATED" = "false" ]; do
 debug "# validating config ..."
 validate_vars "$FOLD/install.conf"; EXITCODE=$?
 if [ "$CANCELLED" = "true" ]; then
   echo "Cancelled."
   exit 1
 fi
 if [ $EXITCODE = 0 ]; then
   VALIDATED="true"
 else
   debug "=> FAILED"
   mcedit "$FOLD/install.conf"
 fi
done


# if we are using the config file option "-c" and not using the automatic mode,
# ask for confirmation before continuing ...
if [ "$OPT_CONFIGFILE" ] && [ -z "$OPT_AUTOMODE" ] ; then
  echo -n ""
  echo -e "${RED}ALL DATA ON THE GIVEN DISKS WILL BE DESTROYED!"
  echo ""
  echo -en "${YELLOW}DO YOU REALLY WANT TO CONTINUE?${NOCOL} [y|N] "
  read -r -n1 aw
  case "$aw" in
    y|Y|j|J) echo -e "\n\n" ;;
    *) echo -e "\n\n${GREEN}ABORT${NOCOL}\n" ; exit 0 ;;
  esac
fi


# execute installfile
echo -e "\033[01;31mWARNING:"
echo -e "\033[01;33m  Starting installation in 20 seconds ..."
echo -e "\033[01;33m  Press X to continue immediately ...\033[00m"
echo -e "\033[01;31m  Installation will DELETE ALL DATA ON DISK(s)!"
echo -e "\033[01;33m  Press CTRL-C to abort now!\033[00m"
echo -n "  => "
for ((i=1; i<=20; i++)); do
  echo -n "."
  read -r -t1 -n1 anykey
  if [ "$anykey" = "x" ] || [ "$anykey" = "X" ]; then
    break
  fi
done
echo ""
#
debug "# executing installfile ..."
if [ -f "$INSTALLFILE" ] && [ "$VALIDATED" = "true" ] ; then
  . "$INSTALLFILE"
  declare -i EXITCODE="$?"
else
  debug "=> FAILED"
  echo ""
  echo -e "\033[01;31mERROR: Cant find files\033[00m"
fi


# abort on error
if [ "$EXITCODE" = "1" ]; then
  exit 1
fi

# vim: ai:ts=2:sw=2:et
