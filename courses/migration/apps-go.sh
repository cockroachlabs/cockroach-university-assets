#!/bin/bash
set -euxo pipefail
#!/bin/bash

# Define version tag
TAG="migration-v0.0.1"

# Extract the version number (strip "migration-")
VERSION="${TAG#migration-}"

# Detect system architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

# Compose the binary name and URL
BINARY_NAME="migration-mysql-app-linux-${ARCH}-${VERSION}"
URL="https://github.com/cockroachlabs/cockroach-university-apps/releases/download/${TAG}/${BINARY_NAME}"

# Destination path
DEST="/usr/local/bin/migration-mysql-app"

# Download and install
echo "[INFO] Downloading $URL ..."
curl -fsSL "$URL" -o "$DEST"

# Make it executable
chmod +x "$DEST"

echo "[INFO] Installed to $DEST"
