#!/bin/sh
set -e

# This entrypoint script runs as root to fix volume permissions,
# then drops privileges to run as the dev user

# Fix ownership of volume-mounted directories if they exist
# This is needed because Docker volumes are created with root ownership
for dir in /home/dev/.config /home/dev/.local /home/dev/.cache; do
    if [ -d "$dir" ]; then
        chown -R dev:dev "$dir" 2>/dev/null || true
    fi
done

# Copy SSH keys from read-only Windows mount and fix permissions
# WSL2 bind mounts come through as 777 which SSH rejects
SSH_SRC="/home/dev/.ssh-host"
SSH_DEST="/home/dev/.ssh"
if [ -d "$SSH_SRC" ]; then
    mkdir -p "$SSH_DEST"
    cp -a "$SSH_SRC/." "$SSH_DEST/" 2>/dev/null || true
    chown -R dev:dev "$SSH_DEST"
    chmod 700 "$SSH_DEST"
    find "$SSH_DEST" -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find "$SSH_DEST" -name "*.pub" -exec chmod 644 {} \;
    [ -f "$SSH_DEST/config" ] && chmod 644 "$SSH_DEST/config"
    [ -f "$SSH_DEST/known_hosts" ] && chmod 644 "$SSH_DEST/known_hosts"
fi

# Optional: enable network firewall
if [ "${CLAUDIO_FIREWALL:-false}" = "true" ] && [ -x /usr/local/bin/init-firewall.sh ]; then
    /usr/local/bin/init-firewall.sh 2>/dev/null || true
fi

# If running as root and we have arguments, exec as dev user
if [ "$(id -u)" = "0" ]; then
    # Run init-claudio as dev user, then exec the command
    if [ $# -eq 0 ]; then
        # No command provided, run default (init + sleep infinity)
        exec runuser -u dev -- sh -c 'init-claudio && exec sleep infinity'
    else
        # Command provided, run it as dev user
        exec runuser -u dev -- "$@"
    fi
else
    # Already running as dev user
    if [ $# -eq 0 ]; then
        # No command provided, run default
        init-claudio
        exec sleep infinity
    else
        # Command provided, run it
        exec "$@"
    fi
fi
