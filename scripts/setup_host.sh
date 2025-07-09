#!/bin/bash
set -e

VAGRANT_VERSION="2.4.1"
ARCH="amd64"
DEB_FILE="vagrant_${VAGRANT_VERSION}-1_${ARCH}.deb"
DOWNLOAD_URL="https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/${DEB_FILE}"

echo "Installing dependencies..."
sudo apt update
sudo apt install -y wget curl gnupg lsb-release

# Remove old version if any
if command -v vagrant >/dev/null; then
    echo "Removing existing Vagrant installation..."
    sudo apt remove -y vagrant
fi

# Download and install the .deb file
echo "Downloading Vagrant ${VAGRANT_VERSION}..."
wget -q "${DOWNLOAD_URL}" -O "/tmp/${DEB_FILE}"

echo "Installing Vagrant..."
sudo dpkg -i "/tmp/${DEB_FILE}"

# Cleanup
rm "/tmp/${DEB_FILE}"

# Verify installation
echo "✅ Vagrant installed successfully:"
vagrant --version

echo "Installing VirtualBox..."
wget -O- -q https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --dearmour -o /usr/share/keyrings/oracle_vbox_2016.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle_vbox_2016.gpg] http://download.virtualbox.org/virtualbox/debian bookworm contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
sudo apt update
sudo apt install virtualbox-7.1

# Verify VirtualBox installation
echo "✅ VirtualBox installed successfully:"
virtualbox --help | head -n 1
