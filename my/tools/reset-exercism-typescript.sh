#!/bin/bash

set -euo pipefail

# TypeScript Exercism Directory Reset Script
# Remove exercism-typescript and exercism-typescript-* directories and re-checkout from remote

echo "=== TypeScript Exercism Directory Reset Started ==="

# Move to project root
cd "$(dirname "$0")/../.."
PROJECT_ROOT=$(pwd)
echo "Project root: $PROJECT_ROOT"

# Clear git submodule cache (execute before directory deletion)
echo "Clearing git submodule cache..."
if [ -d "exercism-typescript" ]; then
    echo "  - deinit exercism-typescript submodule"
    git submodule deinit -f exercism-typescript 2>/dev/null || true
fi

# Remove existing exercism-typescript* directories
echo "Removing existing exercism-typescript* directories..."
if [ -d "exercism-typescript" ]; then
    echo "  - removing exercism-typescript"
    rm -r exercism-typescript
fi

# Initialize and update submodules
echo "Initializing and updating submodules..."
git submodule update --init --recursive

# Verify that exercism-typescript directory exists
if [ ! -d "exercism-typescript" ]; then
    echo "Error: exercism-typescript directory was not created"
    exit 1
fi

# Move to exercism-typescript directory and configure yarn
echo "Configuring yarn in exercism-typescript..."
cd "$PROJECT_ROOT/exercism-typescript"
echo "  - enabling corepack"
if ! COREPACK_OUTPUT=$(corepack enable 2>&1); then
    if echo "$COREPACK_OUTPUT" | grep -q "EEXIST"; then
        echo "  - corepack already enabled"
    else
        echo "$COREPACK_OUTPUT" >&2
        exit 1
    fi
else
    printf "%s\n" "$COREPACK_OUTPUT"
fi
echo "  - installing yarn dependencies"
corepack yarn install

# Return to project root
cd "$PROJECT_ROOT"

echo "=== TypeScript Exercism Directory Reset Completed ==="
echo "exercism-typescript directory has been successfully reset"
