#!/bin/sh
set -e

# mpulse devcontainer entrypoint (self-contained)
# Runs as root: fixes permissions, seeds configs, then drops to dev user.

# --- Volume permission fixes ---
VOLUME_DIRS="
    /home/dev/.config
    /home/dev/.local
    /home/dev/.cache
    /home/dev/.claudio-shared
    /home/dev/.claudio-sessions
    /home/dev/.azure
"
for dir in $VOLUME_DIRS; do
    if [ -d "$dir" ]; then
        chown -R dev:dev "$dir" 2>/dev/null || true
        find "$dir" -type d -exec chmod 700 {} \; 2>/dev/null || true
    fi
done
# Preserve execute permissions on user-installed binaries
if [ -d /home/dev/.local/bin ]; then
    chmod 755 /home/dev/.local/bin 2>/dev/null || true
    find /home/dev/.local/bin -type f -exec chmod 755 {} \; 2>/dev/null || true
fi

# --- SSH key copy from read-only host mount ---
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

# --- Start persistent ssh-agent with fixed socket ---
SSH_SOCK="/home/dev/.ssh/agent.sock"
if [ -d "$SSH_DEST" ]; then
    rm -f "$SSH_SOCK"
    runuser -u dev -- ssh-agent -a "$SSH_SOCK" > /dev/null 2>&1
    SSH_AUTH_SOCK="$SSH_SOCK" DISPLAY="" SSH_ASKPASS="" runuser -u dev -- sh -c \
        'for key in $(find ~/.ssh -name "id_*" ! -name "*.pub"); do ssh-add "$key" < /dev/null 2>/dev/null || true; done'
    export SSH_AUTH_SOCK="$SSH_SOCK"
fi

# --- Snowflake config seeding from read-only host mount ---
SF_SRC="/home/dev/.snowflake-host"
SF_DEST="/home/dev/.snowflake"
if [ -d "$SF_SRC" ] && [ ! -f "$SF_DEST/config.toml" ]; then
    echo "[entrypoint] Seeding .snowflake from host mount..."
    cp -a "$SF_SRC/." "$SF_DEST/" 2>/dev/null || true
fi
mkdir -p "$SF_DEST/logs"
if [ -d "$SF_DEST" ]; then
    chown -R dev:dev "$SF_DEST"
    find "$SF_DEST" -type d -exec chmod 700 {} \;
    find "$SF_DEST" -type f -exec chmod 600 {} \;
fi

# --- Git identity from .env variables ---
if [ -n "$GIT_USER_EMAIL" ]; then
    runuser -u dev -- git config --global user.email "$GIT_USER_EMAIL"
    echo "[entrypoint] Set git user.email: $GIT_USER_EMAIL"
fi
if [ -n "$GIT_USER_NAME" ]; then
    runuser -u dev -- git config --global user.name "$GIT_USER_NAME"
    echo "[entrypoint] Set git user.name: $GIT_USER_NAME"
fi
if [ "${GIT_GPG_SIGN:-false}" = "true" ]; then
    runuser -u dev -- git config --global commit.gpgsign true
    if [ -n "$GIT_SIGNING_KEY" ]; then
        runuser -u dev -- git config --global user.signingkey "$GIT_SIGNING_KEY"
        echo "[entrypoint] Enabled GPG commit signing with key: $GIT_SIGNING_KEY"
    else
        echo "[entrypoint] Enabled GPG commit signing (using default key)"
    fi
fi

# --- Run init-claudio if available ---
if [ "$(id -u)" = "0" ]; then
    if [ $# -eq 0 ]; then
        exec runuser -u dev -- sh -c '
            if command -v init-claudio >/dev/null 2>&1; then
                init-claudio || echo "[entrypoint] WARNING: init-claudio failed (exit $?)"
            fi
            exec sleep infinity'
    else
        exec runuser -u dev -- "$@"
    fi
else
    if [ $# -eq 0 ]; then
        if command -v init-claudio >/dev/null 2>&1; then
            init-claudio || echo "[entrypoint] WARNING: init-claudio failed (exit $?)"
        fi
        exec sleep infinity
    else
        exec "$@"
    fi
fi
