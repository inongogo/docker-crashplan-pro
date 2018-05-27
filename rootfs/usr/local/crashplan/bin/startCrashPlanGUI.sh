#!/usr/bin/with-contenv sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

export HOME=/config
export SWT_GTK3=0
export LD_LIBRARY_PATH=$CRASHPLAN_DIR

cd /config
exec ${CRASHPLAN_DIR}/electron/crashplan >> /config/log/ui_output.log 2>> /config/log/ui_error.log

# vim: set ft=sh :
