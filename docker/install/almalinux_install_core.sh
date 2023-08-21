#!/bin/bash

set -e
set -u
set -o pipefail

# install libraries for building c++ core on almalinux
dnf install -y wget xz python3 python3-pip ncurses-devel cargo gcc-toolset-12 # ncurses-devel for libtinfo
ln -s /usr/bin/python3 /usr/bin/python

# install multibuild utils
git clone https://github.com/multi-build/multibuild.git && cd multibuild &&
	git checkout 509e63a6d8ab4705a500264d396b0e675798b6fc

# git clone https://github.com/matthew-brett/multibuild.git && cd multibuild &&
	# git checkout 9e2349833e994cb829b77cc08f1aacc6ab6d2458
