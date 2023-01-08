#!/bin/bash

#
# To install before using:
#
# MCHOME="/opt/matrix-commander"
# MCARGS="-c $MCHOME/credentials.json --store $MCHOME/store"
# mkdir -p "$MCHOME/venv"
# python3 -m venv "$MCHOME/venv"
# source "$MCHOME/venv/bin/activate"
# pip3 install matrix-commander
# chmod 700 "$MCHOME"
# matrix-commander $MCARGS --login password   # < NB here this is literally 'password' as authentication method, the actual password will be asked by a prompt
# chmod 600 "$MCHOME/credentials.json"
# chmod 700 "$MCHOME"
# matrix-commander $MCARGS --room-join '#yunohost-apps:matrix.org'
#

MCHOME="/opt/matrix-commander/"
MCARGS="-c $MCHOME/credentials.json --store $MCHOME/store"
"$MCHOME/venv/bin/matrix-commander" $MCARGS -m "$@"  --room 'yunohost-apps'
