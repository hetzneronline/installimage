#!/bin/bash

URL=?
n=0

while [ $n -lt 3 ]; do
  wget --timeout=10 --no-check-certificate -O /dev/null $URL &>/dev/null
  test $? -eq 0 && break
  let n++
  sleep 5
done

# need to change this soon, b/c SuSE-release is deprecated
# and CentOS has also os-release
#if [ -f /etc/os-release ]; then
if [ -f /etc/SuSE-release ]; then
  # openSuSE
  sed -i -e "s#^bash /robot.*##" /etc/init.d/after.local
  sed -i -e "s#^bash /robot.*##" /etc/init.d/boot.local
else
  sed -e 's/^\[ -x \/robot\.sh \] && \/robot\.sh$//' -i /etc/rc.local
fi

rm -f /robot.sh
