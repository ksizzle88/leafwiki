#!/bin/sh
set -e

# mpulse entrypoint - delegates to the Claudio base image entrypoint
#
# The base image entrypoint (/usr/local/bin/docker-entrypoint.sh) handles:
#   - Volume permission fixes (.config, .local, .cache, .claude, .claudio)
#   - SSH key copy from .ssh-host with permission fixes (WSL2 777 issue)
#   - Optional firewall init (CLAUDIO_FIREWALL=true)
#   - Dropping privileges to dev user
#   - Running init-claudio + sleep infinity as default command
#
# This file is no longer COPY'd into the image (the Dockerfile inherits the
# base entrypoint). It is kept as a reference and extension point. If mpulse
# needs project-specific entrypoint logic in the future, uncomment the COPY
# in the Dockerfile and add custom steps before the exec below.

# Add any mpulse-specific entrypoint logic here (runs as root):
# e.g., fix ownership of mpulse-specific volume mounts

# Delegate to base entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
