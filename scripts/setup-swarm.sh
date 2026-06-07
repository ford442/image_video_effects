#!/bin/bash
set -e

echo "🔧 Setting up WGSL Audit Swarm..."

# Install GitHub CLI if missing (Codespaces usually has it, but check)
if ! command -v gh &> /dev/null; then
    echo "📦 Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null || true
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null 2>/dev/null || true
    sudo apt update -qq && sudo apt install gh -y -qq 2>/dev/null || {
        echo "⚠️  Could not install gh via apt, trying direct download..."
        curl -sL https://github.com/cli/cli/releases/download/v2.40.1/gh_2.40.1_linux_amd64.tar.gz | tar -xz -C /tmp
        sudo mv /tmp/gh_2.40.1_linux_amd64/bin/gh /usr/local/bin/ 2>/dev/null || mv /tmp/gh_2.40.1_linux_amd64/bin/gh ~/.local/bin/ 2>/dev/null || true
    }
fi

# Install jq if missing
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    sudo apt-get update -qq && sudo apt-get install -y -qq jq 2>/dev/null || {
        echo "⚠️  jq installation failed, but we'll use a fallback"
    }
fi

# Create directory structure
mkdir -p agents reports fixes temp
chmod +x scripts/wgsl-audit-swarm.sh 2>/dev/null || true

# Check for ai-cli.sh availability
if [ -f "../../ai-cli.sh" ]; then
    echo "✅ Found ai-cli.sh at ../../ai-cli.sh"
elif [ -f "../ai-cli.sh" ]; then
    echo "✅ Found ai-cli.sh at ../ai-cli.sh"
elif [ -f "./ai-cli.sh" ]; then
    echo "✅ Found ai-cli.sh at ./ai-cli.sh"
else
    echo "⚠️  ai-cli.sh not found in expected locations"
    echo "   The swarm will use fallback curl-based validation"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run: bash scripts/wgsl-audit-swarm.sh [batch_size]"
echo "  2. Or with limited scope: bash scripts/wgsl-audit-swarm.sh 5 --sample"
echo ""
echo "Options:"
echo "  batch_size  - Number of parallel agents (default: 4, max: 10)"
echo "  --sample    - Only audit 10 random shaders for testing"
echo "  --category  - Audit only shaders in a category (e.g., --category=glitch)"
echo ""
