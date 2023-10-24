#!/bin/bash

#
# mainmenu - choose which image should be installed
#
# (c) 2007-2022, Hetzner Online GmbH
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


if [ "$OPT_AUTOMODE" ] ; then

  ### automatic mode ------------------------------------------------

  debug "# AUTOMATIC MODE: start"

  # create config
  debug "# AUTOMATIC MODE: create config"
  create_config "$IMAGENAME" ; EXITCODE=$?
  if [ $EXITCODE != 0 ] ; then
    debug "=> FAILED"
    exit 1
  fi


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
      # dont show editor in automode. print to stdout
      echo "Abort: invalid config or parameters. See $DEBUGFILE for details"
      # mcedit "$FOLD/install.conf"
      exit 1
    fi
  done

  # display information about automatic mode
  echo -e "\n\033[01;32mStarting AUTOMATIC MODE\033[00m"
  echo -e "\033[01;33mRunning unattended installimage installation ...\033[00m"
  echo ""
  grep -v "^#" "$FOLD/install.conf" | grep -v "^$"
  echo ""
  echo ""

  # warn about unsupported image
  warn=""
  if other_image "$IMAGE" || [[ "$PROXMOX" == true ]]; then
    warn="$(other_image_warning)"
  elif old_image "$IMAGE"; then
    warn="$(old_image_warning)"
  fi
  if [[ -n "$warn" ]]; then
    debug "WARNING: $(tr "\n" ' ' <<< "$warn")"
    echo -e "\e[1;31mWARNING:"
    echo -e "\e[1;33m$(sed 's/^/  /' <<< "$warn")\e[0m\n"
  fi
  warn=""

  # print warning
  echo -e "\033[01;31mWARNING:"
  echo -e "\033[01;33m  Starting installation in 20 seconds ..."
  echo -e "\033[01;33m  Press X to continue immediately ...\033[00m"
  echo -e "\033[01;31m  Installation will DELETE ALL DATA ON DISK(s)!"
  echo -e "\033[01;33m  Press CTRL-C to abort now!\033[00m"
  echo -n "  => "
  for ((i=1; i<=20; i++)); do
    echo -n "."
    read -r -t1 -n1 anykey
    if [ "$anykey" = "x" ] || [ "$anykey" = "X" ] ; then break ; fi
  done
  echo

  # start install
  debug "# AUTOMATIC MODE: start installation"
  . "$INSTALLFILE" ; EXITCODE=$?
  [ $EXITCODE != 0 ] && debug "=> FAILED"

else

  ### interactive mode ----------------------------------------------

  # start the mainmenu and loop while not chosen "exit" or a config and finished configuration
  ACCEPTED=""
  while [ -z "$ACCEPTED" ]; do

    if [ "$OPT_IMAGE" ] ; then
      # use image from option, do not display image menu
      NOIMAGEMENU=true
    else
      # display the image menu
      IMAGENAME=""
      debug "# starting menu..."
      while [ -z "$IMAGENAME" ] || [ "$IMAGENAME" = "back" ]; do
        OLDIFS="$IFS"
        IFS=$'\n'

        # we want $OSMENULIST to expand here
        # shellcheck disable=SC2086
        dialog --backtitle "$DIATITLE" --title "o/s list" --no-cancel --menu "choose o/s" 0 0 0 ${OSMENULIST[*]} "exit" "" 2>$FOLD/mainmenu.chosen
        IFS="$OLDIFS"
        MAINMENUCHOSEN=$(cat "$FOLD/mainmenu.chosen")
        case "$MAINMENUCHOSEN" in
          "exit")
            debug "=> user exited from menu"
            exit 1
          ;;
          "Custom image")
            IMAGENAME="custom"
          ;;
          *)
            generate_menu "$MAINMENUCHOSEN"
          ;;
        esac
      done
    fi

    debug "# chosen image: [ $IMAGENAME ]"

    debug "# copy & create config..."
    create_config "$IMAGENAME"; EXITCODE=$?
    if [ $EXITCODE != 0 ] ; then
      debug "=> FAILED"
      exit 1
    fi

    text='\n    An editor will now show you the config for the image.\n
    You can edit the parameters for your needs.\n
    To accept all changes and continue the installation\n
    just save and exit the editor with F10.'

    [ "$COUNT_DRIVES" -gt 1 ] && text=$text'\n\n\Z1  Please note!:  by default all disks are used for software raid\n
  change this to (SWRAID 0) if you want to leave your other harddisk(s)\n  untouched!\Zn'

    dialog --backtitle "$DIATITLE" --title " NOTICE " --colors --msgbox "$text" 14 75
    VALIDATED="false"
    CANCELLED="false"
    while [ "$VALIDATED" = "false" ]; do
      debug "# starting mcedit..."
      whoami "$IMAGENAME"
      mcedit "$FOLD/install.conf"; EXITCODE=$?
      [ $EXITCODE != 0 ] && debug "=> FAILED"
      debug "# validating vars..."
      validate_vars "$FOLD/install.conf"; EXITCODE=$?
      if [ "$CANCELLED" = "true" ]; then
        clear
        echo "Cancelled."
        exit 1
      fi
      if [ $EXITCODE = 0 ]; then
        VALIDATED="true"
      else
        if [ "$CANCELLED" = "true" ]; then
          debug "=> CANCELLED"
          VALIDATED="true"
        else
          debug "=> FAILED"
        fi
      fi
    done

    # warn about unsupported image
    warn=""
    if other_image "$IMAGE" || [[ "$PROXMOX" == true ]]; then
      warn="$(other_image_warning)"
    elif old_image "$IMAGE"; then
      warn="$(old_image_warning)"
    fi
    if [[ -n "$warn" ]]; then
      debug "WARNING: $(tr "\n" ' ' <<< "$warn")"
      dialog --backtitle "$DIATITLE" --title "Confirmation" --colors --defaultno --yesno "\n\Z1WARNING!: $(sed 's/$/\\n\\n/' <<< "$warn")Do you want to continue?\Zn\n" 0 0
      if (($? != 0)); then
        echo "Cancelled."
        exit 1
      fi
    fi
    warn=""

    if [ "$LVM" = "1" ]; then
        graph_notice "Please note that ALL existing LVs and VGs will be removed during the installation!"
    fi

    if [ "$CANCELLED" = "false" ]; then
      debug "# asking for confirmation..."
      for ((i=1; i<=COUNT_DRIVES; i++)); do
        ask_format="$(eval echo "\$FORMAT_DRIVE$i")"
        ask_drive="$(eval echo "\$DRIVE$i")"
        if [ "$SWRAID" = "1" ] || [ "$ask_format" = "1" ] || [ "$i" -eq 1 ]; then
          disk_info=''
          disk_serial="$(disk_serial "$ask_drive")" || :
          [[ -z "$disk_serial" ]] || disk_info+=", Serial Number: $disk_serial"
          dialog --backtitle "$DIATITLE" --title "Confirmation" --colors --yesno "\n\Z1WARNING!: DATA ON THE FOLLOWING DRIVE WILL BE DELETED:\n\n ${ask_drive}$disk_info\n\nDo you want to continue?\Zn\n" 0 0
          if [ $? -ne 0 ]; then
            debug "# Confirmation for drive $ask_drive NOT accepted"
            ACCEPTED=""
            if [ "$NOIMAGEMENU" ]; then
              exit
            else
              break
            fi
          else
            debug "# Confirmation for drive $ask_drive accepted"
            ACCEPTED="true"
          fi
        fi
      done
    fi
  done


  debug "# executing installfile..."
  if [ -f "$INSTALLFILE" ] && [ "$ACCEPTED" = "true" ] && [ "$VALIDATED" = "true" ] && [ -n "$IMAGENAME" ] ; then
     . "$INSTALLFILE" ; EXITCODE=$?
  else
    debug "=> FAILED"
    echo -e "\n\033[01;31mERROR: Cant find files\033[00m"
  fi

fi


if [ "$EXITCODE" = "1" ]; then
  exit 1
fi

# vim: ai:ts=2:sw=2:et
