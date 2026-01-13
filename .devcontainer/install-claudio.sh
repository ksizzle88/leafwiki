#!/bin/bash
# install-claudio.sh - Install Claudio (Claude Code) into any Docker image
#
# Usage in Dockerfile:
#   FROM claudio-base:latest AS claudio
#   FROM your-existing-image:latest
#
#   COPY --from=claudio /usr/local/bin/install-claudio.sh /tmp/
#   RUN /tmp/install-claudio.sh
#
#   # Or with custom paths
#   RUN CLAUDE_HOME=/root/.claude PROJECT_CLAUDE=/app/.claude /tmp/install-claudio.sh

set -e

# Auto-detect current user and set defaults
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    DEFAULT_HOME="/root"
else
    DEFAULT_HOME="/home/$CURRENT_USER"
fi

# Configuration via environment variables
CLAUDE_HOME="${CLAUDE_HOME:-$DEFAULT_HOME/.claude}"
CLAUDE_HISTORY="${CLAUDE_HISTORY:-$DEFAULT_HOME/.history}"

echo "Installing Claudio (Claude Code)..."
echo "  User: $CURRENT_USER"
echo "  Home: $DEFAULT_HOME"
echo "  Claude Home: $CLAUDE_HOME"

# Step 1: Verify Node.js binaries are available
if [ ! -f /usr/bin/node ]; then
    echo "ERROR: Node.js binary not found"
    echo "Ensure you copied it from claudio-base image:"
    echo "  COPY --from=claudio /usr/bin/node /usr/bin/node"
    echo "  COPY --from=claudio /usr/lib/node_modules /usr/lib/node_modules"
    exit 1
fi

if [ ! -d /usr/lib/node_modules ]; then
    echo "ERROR: node_modules directory not found"
    echo "Ensure you copied it from claudio-base image:"
    echo "  COPY --from=claudio /usr/lib/node_modules /usr/lib/node_modules"
    exit 1
fi

# Step 2: Create symlinks for npm, npx, and claude
echo "Creating symlinks for npm, npx, and claude..."
ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/bin/npm
ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/bin/npx
ln -sf ../lib/node_modules/@anthropic-ai/claude-code/cli.js /usr/bin/claude
echo "✓ Symlinks created"

# Step 3: Verify init script exists
if [ ! -f /usr/local/bin/init-claude-settings.sh ]; then
    echo "ERROR: init-claude-settings.sh not found"
    echo "Ensure you copied it:"
    echo "  COPY --from=claudio /usr/local/bin/init-claude-settings.sh /usr/local/bin/"
    exit 1
fi

# Step 4: Verify image defaults exist
if [ ! -d /opt/claudio-defaults/.claude ]; then
    echo "ERROR: Claudio defaults not found"
    echo "Ensure you copied them:"
    echo "  COPY --from=claudio /opt/claudio-defaults/.claude/ /opt/claudio-defaults/.claude/"
    exit 1
fi

# Step 5: Create directories with proper permissions
echo "Creating Claude directories..."
mkdir -p "$CLAUDE_HOME" "$CLAUDE_HISTORY"

# Set ownership if not root
if [ "$CURRENT_USER" != "root" ] && [ -n "$CURRENT_USER" ]; then
    chown -R "$CURRENT_USER:$CURRENT_USER" "$CLAUDE_HOME" "$CLAUDE_HISTORY" 2>/dev/null || true
fi

chmod 755 "$CLAUDE_HOME" "$CLAUDE_HISTORY"
echo "✓ Directories created"

# Step 6: Set environment variables
echo "Configuring environment variables..."
cat >> /etc/environment <<EOF

# Claudio (Claude Code) environment
CLAUDE_CONFIG_DIR=$CLAUDE_HOME
npm_config_update_notifier=false
npm_config_fund=false
EOF
echo "✓ Environment configured"

# Step 7: Verify installation
echo ""
echo "Verifying installation..."
node --version
npm --version
claude --version

echo ""
echo "✓ Claudio installation complete!"
echo ""
echo "Configuration:"
echo "  CLAUDE_CONFIG_DIR=$CLAUDE_HOME"
echo "  npm notifications disabled"
echo ""
echo "Next steps:"
echo "  - Run init-claude-settings.sh in postCreateCommand"
echo "  - Authenticate with 'claude login' or VS Code extension"
echo ""
