#!/bin/bash
# init-firewall.sh - Network security firewall for Claudio devcontainer
# Based on official Claude Code devcontainer pattern
# https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh

set -euo pipefail
IFS=$'\n\t'

echo "Initializing firewall..."

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127.0.0.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Restore Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# 3. Allow DNS and localhost before any restrictions
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 4. Create ipset with CIDR support
ipset create allowed-domains hash:net

# 5. Fetch GitHub IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "WARNING: Failed to fetch GitHub IP ranges, continuing without them"
else
    if echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
        echo "Processing GitHub IPs..."
        while read -r cidr; do
            if [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                ipset add allowed-domains "$cidr" 2>/dev/null || true
            fi
        done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | sort -u)
    fi
fi

# 6. Resolve and add other allowed domains
ALLOWED_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
    "*.gallery.vsassets.io"
    "pypi.org"
    "files.pythonhosted.org"
    # Docker Hub (BuildKit frontend, base image pulls)
    "auth.docker.io"
    "registry-1.docker.io"
    "production.cloudflare.docker.com"
    # Microsoft Container Registry (devcontainer base images)
    "mcr.microsoft.com"
    # GitHub Container Registry (Claudio image)
    "ghcr.io"
    "pkg.github.com"
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
    # Skip wildcard domains for now
    if [[ "$domain" == *"*"* ]]; then
        continue
    fi

    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" 2>/dev/null | awk '$4 == "A" {print $5}' || true)

    if [ -n "$ips" ]; then
        while read -r ip; do
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                ipset add allowed-domains "$ip" 2>/dev/null || true
            fi
        done <<< "$ips"
    else
        echo "WARNING: Failed to resolve $domain"
    fi
done

# 7. Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3 || true)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network detected as: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# 8. Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 9. Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 10. Allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# 11. Reject all other outbound traffic
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"

# 12. Verify firewall
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "WARNING: Firewall verification failed - was able to reach https://example.com"
else
    echo "Firewall verification passed - blocked https://example.com"
fi

if curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "Firewall verification passed - able to reach https://api.github.com"
else
    echo "WARNING: Unable to reach https://api.github.com - some features may not work"
fi

echo "Firewall initialization complete"
