#!/bin/bash

set +x
echo "PreInstall Linux for FUSE_PKG=${FUSE_PKG}"
sudo apt-get update -y
sudo apt-get install pkg-config ${FUSE_PKG} libffi-dev gcc make
sudo modprobe -v fuse
sudo chmod 666 /dev/fuse && ls -l /dev/fuse
sudo chown root:$USER /etc/fuse.conf && ls -l /etc/fuse.conf

declare -A LIBS =( [fuse2]="libfuse.so.2" [fuse3]="libfuse3.so.3")

echo "LIBFUSE=${LIBS[${FUSE_PKG}]}" || tee -a ${GITHUB_ENV}