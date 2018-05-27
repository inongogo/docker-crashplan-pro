#!/usr/bin/with-contenv sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

log() {
    echo "[cont-init.d] $(basename $0): $*"
}

get_cp_max_mem() {
    if [ -f "$1" ]; then
        cat "$1" | sed -n 's/.*SRV_JAVA_OPTS=.* -Xmx\([0-9]\+[g|G|m|M|k|K]\?\) .*$/\1/p'
    fi
}

# Generate machine id.
if [ ! -f /config/machine-id ]; then
    log "generating machine-id..."
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /config/machine-id
fi

# Set a home directory in passwd, needed by the engine.
sed-patch "s|app:x:$USER_ID:$GROUP_ID::/dev/null:|app:x:$USER_ID:$GROUP_ID::/config:|" /etc/passwd && \

# Make sure required directories exist.
mkdir -p /config/bin
mkdir -p /config/log
mkdir -p /config/cache
mkdir -p /config/var
mkdir -p /config/repository/metadata

# Determine if it's a first/initial installation or an upgrade.
FIRST_INSTALL=0
UPGRADE=0
if [ ! -d /config/conf ]; then
    log "handling initial run..."
    FIRST_INSTALL=1
elif [ ! -f /config/cp_version ]; then
    log "handling upgrade to CrashPlan version $(cat /defaults/cp_version)..."
    UPGRADE=1
elif [ "$(cat /config/cp_version)" != "$(cat /defaults/cp_version)" ]; then
    log "handling upgrade from CrashPlan version $(cat /config/cp_version) to $(cat /defaults/cp_version)..."
    UPGRADE=1
fi

# Install defaults.
if [ "$FIRST_INSTALL" -eq 1 ] || [ "$UPGRADE" -eq 1 ]; then
    # Copy default config files.
    cp -r /defaults/conf /config/

    # Copy run.conf.
    # NOTE: Remember the maximum allocated memory setting before overwritting.
    if [ "${CRASHPLAN_SRV_MAX_MEM:-UNSET}" = "UNSET" ] && [ -f /config/bin/run.conf ]; then
        CUR_MEM_VAL="$(get_cp_max_mem /config/bin/run.conf)"
        if [ "${CUR_MEM_VAL:-UNSET}" != "UNSET" ]; then
            CRASHPLAN_SRV_MAX_MEM="$CUR_MEM_VAL";
        fi
    fi
    cp /defaults/run.conf /config/bin/run.conf

    # Set the current CrashPlan version.
    cp /defaults/cp_version /config/

    # Clear the cache.
    rm -rf /config/cache/*
fi

# Update CrashPlan Engine max memory if needed.
if [ "${CRASHPLAN_SRV_MAX_MEM:-UNSET}" != "UNSET" ]; then
  if ! echo "$CRASHPLAN_SRV_MAX_MEM" | grep -q "^[0-9]\+[g|G|m|M|k|K]\?$"
  then
    log "ERROR: invalid value for CRASHPLAN_SRV_MAX_MEM variable: '$CRASHPLAN_SRV_MAX_MEM'."
    exit 1
  fi

  CUR_MEM_VAL="$(get_cp_max_mem /config/bin/run.conf)"
  if [ "${CUR_MEM_VAL:-UNSET}" != "UNSET" ] && [ "$CRASHPLAN_SRV_MAX_MEM" != "$CUR_MEM_VAL" ]
  then
    log "updating CrashPlan Engine maximum memory from $CUR_MEM_VAL to $CRASHPLAN_SRV_MAX_MEM."
    sed -i "s/^\(SRV_JAVA_OPTS=.* -Xmx\)[0-9]\+[g|G|m|M|k|K]\? /\1$CRASHPLAN_SRV_MAX_MEM /" /config/bin/run.conf
  fi
fi

# On some systems (e.g QNAP NAS), instead of the loopback IP address
# (127.0.0.1), the IP address of the host is used by the CrashPlan UI to connect
# to the engine.  This connection cannot succeed when using the Docker `bridge`
# network mode.
# Make sure to fix this situation by forcing the loopback IP address in
# concerned configuration files.
if [ -f /config/conf/my.service.xml ]; then
    sed -i 's|<serviceHost>.*</serviceHost>|<serviceHost>127.0.0.1</serviceHost>|' /config/conf/my.service.xml
fi
if [ -f /config/var/.ui_info ]; then
    sed -i 's|,[0-9.]\+$|,127.0.0.1|' /config/var/.ui_info
fi

# Clear some log files.
rm -f /config/log/engine_output.log \
      /config/log/engine_error.log \
      /config/log/ui_output.log \
      /config/log/ui_error.log

# Make sure monitored log files exist.
for LOGFILE in /config/log/service.log.0 /config/log/app.log
do
    [ -f "$LOGFILE" ] || touch "$LOGFILE"
done

# Take ownership of the config directory content.
chown -R $USER_ID:$GROUP_ID /config/*

# vim: set ft=sh :
