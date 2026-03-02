#!/bin/sh
set -e

# Claudio Base Image Entrypoint
# Runs as root to fix volume permissions, then drops privileges to dev user.
# This pattern solves the Docker named volume root-ownership problem where
# volumes mount over directories with root:root, causing permission errors
# when the container runs as a non-root user.

# Fix ownership of volume-mounted directories if they exist
# Docker named volumes are created with root:root ownership, which causes
# "Permission denied" errors when the dev user tries to write to them.
for dir in /home/dev/.config /home/dev/.local /home/dev/.cache /home/dev/.claude /home/dev/.claudio; do
    if [ -d "$dir" ]; then
        chown -R dev:dev "$dir" 2>/dev/null || true
    fi
done

# Copy SSH keys from read-only host mount and fix permissions
# WSL2 bind mounts come through as 777 which SSH rejects as too permissive
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

# Optional: enable network firewall (set CLAUDIO_FIREWALL=true in .env)
if [ "${CLAUDIO_FIREWALL:-false}" = "true" ] && [ -x /usr/local/bin/init-firewall.sh ]; then
    /usr/local/bin/init-firewall.sh 2>/dev/null || true
fi

# Drop privileges and run as dev user
if [ "$(id -u)" = "0" ]; then
    if [ $# -eq 0 ]; then
        # No command provided - run default: init-claudio then sleep
        exec runuser -u dev -- sh -c 'init-claudio && exec sleep infinity'
    else
        # Command provided - run it as dev user
        exec runuser -u dev -- "$@"
    fi
else
    # Already running as non-root (e.g., invoked with --user)
    if [ $# -eq 0 ]; then
        init-claudio
        exec sleep infinity
    else
        exec "$@"
    fi
fi
