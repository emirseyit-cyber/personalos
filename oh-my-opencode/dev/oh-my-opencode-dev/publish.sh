#!/bin/bash
# oh-my-opencode NPM Publish Script
# 
# Kullanım:
# 1. NPM token oluştur: https://www.npmjs.com/settings/-/access-tokens
# 2. Token'ı kaydet: echo "//registry.npmjs.org/:_authToken=SENIN_TOKENIN" > ~/.npmrc
# 3. Bu scripti calistir: bash publish.sh

set -e

echo "=== oh-my-opencode v3.8.0 Publish ==="

# Check if logged in
echo "Checking npm login..."
if npm whoami &> /dev/null; then
    echo "Logged in as: $(npm whoami)"
else
    echo "ERROR: Not logged in to npm!"
    echo "Run: npm adduser"
    exit 1
fi

# Build
echo "Building..."
bun run build

# Publish
echo "Publishing to npm..."
npm publish --access public

echo "=== DONE ==="
echo "Package published: https://www.npmjs.com/package/oh-my-opencode"
