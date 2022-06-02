#!/bin/bash

echo "PreInstall Linux for FUSE_PKG=${FUSE_PKG} LIBFUSE=${LIBFUSE}"
sudo apt-get update -y
sudo apt-get install -qq pkg-config ${FUSE_PKG} libffi-dev gcc make
sudo modprobe fuse
sudo chmod 666 /dev/fuse
sudo chown root:$USER /etc/fuse.conf
echo yes | gem update --system -N --force
gem install bundler