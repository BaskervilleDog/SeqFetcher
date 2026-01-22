#!/usr/bin/env bash

set -e

INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_NAME="seqfetcher"

echo "Installing SeqFetcher..."

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Copy main script
cp seqfetcher.sh "${INSTALL_DIR}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

# Copy library files
LIB_DIR="${INSTALL_DIR}/seqfetcher_lib"
mkdir -p "$LIB_DIR"
cp -r lib/* "$LIB_DIR/"

# Update BASE_DIR in installed script
sed -i "s|BASE_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\"|BASE_DIR=\"${LIB_DIR%/*}\"|g" "${INSTALL_DIR}/${SCRIPT_NAME}"

echo "✓ SeqFetcher installed to: ${INSTALL_DIR}/${SCRIPT_NAME}"
echo ""
echo "Add to PATH if needed:"
echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
echo ""
echo "Usage: $SCRIPT_NAME --help"