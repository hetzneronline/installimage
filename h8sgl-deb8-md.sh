#!/bin/sh

### Hetzner Online GmbH - installimage

PREREQ="mdadm mdrun multipath"

prereqs()
{
        echo "$PREREQ"
}

case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac

mdadm --assemble --scan

