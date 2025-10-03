#!/usr/bin/env bash
set -euo pipefail
alias cls=clear
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

apt update
apt install alire=1.2.1-2build1 -y
apt install build-essential=12.12ubuntu1 -y
apt install libc6-dev=2.41-6ubuntu1.2 -y
