#!/bin/ash

echo "PreInstall Alpine Linux for FUSE_PKG=${FUSE_PKG}"

#sudo chmod 666 /dev/fuse && ls -l /dev/fuse
#sudo chown root:$USER /etc/fuse.conf && ls -l /etc/fuse.conf

# Build lock file for this platform
if [ ! -f Gemfile.lock ]; then
  bundle lock
fi