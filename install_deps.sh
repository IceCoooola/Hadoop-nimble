#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Return the exit status of the last command in the pipeline that failed

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Update package list and upgrade existing packages
echo "Updating system..."
apt-get update && apt-get upgrade -y

# Install OpenJDK 1.8
echo "Installing JDK 1.8..."
apt-get install -y openjdk-8-jdk

# Install Maven 3.8.6 (or the latest version available via apt)
echo "Installing Maven..."
apt-get install -y maven

# Install Protocol Buffers 3.7.1
echo "Installing Protocol Buffers 3.7.1..."
PROTOBUF_VERSION="3.7.1"
mkdir -p /opt/protobuf
curl -L -o /opt/protobuf/protobuf.tar.gz https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-all-${PROTOBUF_VERSION}.tar.gz
tar -xzf /opt/protobuf/protobuf.tar.gz -C /opt/protobuf
cd /opt/protobuf/protobuf-${PROTOBUF_VERSION}
./configure --prefix=/usr/local
make -j$(nproc)
make install
ldconfig
cd ~
rm -rf /opt/protobuf
protoc --version  # Verify installation

# Install CMake 3.1 or newer
echo "Installing CMake..."
apt-get install -y cmake

# Install Zlib development libraries
echo "Installing Zlib development libraries..."
apt-get install -y zlib1g-dev

# Install Cyrus SASL development libraries
echo "Installing Cyrus SASL development libraries..."
apt-get install -y libsasl2-dev

# Install GCC 4.8.1 or later
echo "Installing GCC..."
apt-get install -y gcc g++

# Install Clang
echo "Installing Clang..."
apt-get install -y clang

# Install OpenSSL development libraries
echo "Installing OpenSSL development libraries..."
apt-get install -y libssl-dev

# Install FUSE (Filesystem in Userspace)
echo "Installing FUSE..."
apt-get install -y fuse libfuse-dev

# Install Doxygen
echo "Installing Doxygen..."
apt-get install -y doxygen

# Install Python
echo "Installing Python..."
apt-get install -y python3 python3-pip

# Install bats
echo "Installing bats..."
apt-get install -y bats

# Install Node.js, Bower, and Ember-cli for YARN UI v2 building
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
npm install -g bower ember-cli

echo "Restarting necessary services..."
systemctl restart networkd-dispatcher.service || true
systemctl restart unattended-upgrades.service || true

# Verify installations
echo "Verifying installations..."
java -version
mvn -version
protoc --version
cmake --version
gcc --version
g++ --version
clang --version
openssl version
fuse --version
python3 --version
bats --version
node -v
npm -v
bower -v
ember -v

echo "All dependencies installed successfully!"
