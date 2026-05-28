#!/bin/sh
printf '\033c\033]0;%s\a' Soccer
base_path="$(dirname "$(realpath "$0")")"
"$base_path/power-soccer-server.x86_64" "$@"
