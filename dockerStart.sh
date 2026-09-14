#!/bin/bash

# Restarts an existing container created by dockerRun.sh.
#
# Unlike `docker run`, `docker start` reuses the container's original bind
# mounts as-is. /tmp is cleared on reboot (systemd-tmpfiles / tmpfs), so
# /tmp/.docker.xauth can go missing; if something (Docker/runc included)
# then recreates it as a directory instead of a file, `docker start` fails
# with a "mounting ... not a directory" error because the container still
# expects a regular file there. A systemd-tmpfiles rule
# (/etc/tmpfiles.d/docker-xauth.conf) now recreates it as a file on every
# boot, but this guard also fixes it on demand in case that ever slips.

if [ -z "$1" ]; then
  echo "Use: ./dockerStart.sh <container_name>"
  exit 1
fi

CONTAINER_NAME=$1

XAUTH=/tmp/.docker.xauth

if [ -d "$XAUTH" ]; then
  echo "$XAUTH is a directory (stale), replacing with a file..."
  sudo rmdir "$XAUTH"
fi

if [ ! -f "$XAUTH" ]; then
  touch "$XAUTH"
  chmod a+r "$XAUTH"
fi

if [ -n "$DISPLAY" ]; then
  xhost +local:root >/dev/null 2>&1
  xauth nlist "$DISPLAY" | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge -
fi

sudo docker start -ai "$CONTAINER_NAME"
