#!/bin/bash

set -e
set -u
set -o pipefail

dnf makecache --refresh
dnf -y install cmake
dnf -y --enablerepo=powertools install ninja-build

# Fix for latest version linux
# dnf install -y dnf-plugin-config-manager
# dnf config-manager --set-enabled crb
# dnf makecache --refresh
# dnf -y install cmake ninja-build