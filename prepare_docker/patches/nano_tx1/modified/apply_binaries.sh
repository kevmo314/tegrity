#!/bin/bash

# Copyright (c) 2011-2019, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#
# This script applies the binaries to the rootfs dir pointed to by
# LDK_ROOTFS_DIR variable.
#

set -e

readonly SCRIPT_NAME="$(basename $0)"
readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
readonly THIS_USER="$(whoami)"
# apply .deb script name (in ./nv_tegra/
readonly DEB_SCRIPT_NAME="nv-apply-debs.sh"
# tarballs to extract to the rootfs (path relative to BSP_DIR) if TARGET_OVERLAY
# (otherwise apt is used)
readonly TARBALLS=(
	"config.tbz2"
	"graphics_demos.tbz2"
	# todo: if kernel_supplements is user generated, it should be installed and
	#  the apt package for the kernel and friends not installed. a warning
	#  should be printed that ota updates will not update the kernel.
	"kernel_supplements.tbz2"
	"nv_sample_apps/nvgstapps.tbz2"
	"nv_tools.tbz2"
	"nvidia_drivers.tbz2"
	"weston.tbz2"
)
# if "true", prints extra debug info
DEBUG="false"
# flag used to switch between legacy overlay packages and debians
# default is debians, but can be switched to overlay by setting to "true"
USE_TARGET_OVERLAY_DEFAULT=
BSP_DIR="${THIS_DIR}"

function ShowDebug {
	echo "${SCRIPT_NAME} debug info:"
	echo "BSP_DIR=${BSP_DIR}"
	echo "DEB_SCRIPT_NAME=${DEB_SCRIPT_NAME}"
	echo "DEBUG=${DEBUG}"
	echo "LDK_BOOTLOADER_DIR=${LDK_BOOTLOADER_DIR}"
	echo "LDK_KERN_DIR=${LDK_KERN_DIR}"
	echo "LDK_NV_TEGRA_DIR=${LDK_NV_TEGRA_DIR}"
	echo "LDK_ROOTFS_DIR=${LDK_ROOTFS_DIR}"
	echo "THIS_DIR=${THIS_DIR}"
	echo "THIS_USER=${THIS_USER}"
	echo "USE_TARGET_OVERLAY_DEFAULT=${USE_TARGET_OVERLAY_DEFAULT}"
	set -ex
}

function ShowUsage {
	echo "Use: $1 [--bsp|-b PATH] [--root|-r PATH] [--target-overlay] [--help|-h]"
cat <<EOF
	This script installs tegra binaries
	Options are:
	--bsp|-b PATH
				   bsp location (bsp, readme, installer)
	--root|-r PATH
				   install toolchain to PATH
	--target-overlay|-t
				   untar NVIDIA target overlay (.tbz2) instead of
				   pre-installing them as Debian packages
	--help|-h
				   show this help
EOF
}

function FailIfRoot() {
	if [ "${THIS_USER}" == "root" ]; then
		echo "This script should not be run as root"
		exit 1
	fi
}

# parse the command line first
TGETOPT=$(getopt -n "$SCRIPT_NAME" --longoptions help,bsp:,debug,target-overlay,root: -o b:dhr:b:t: -- "$@")

if [ $? != 0 ]; then
	echo "Terminating... wrong switch"
	ShowUsage "$SCRIPT_NAME"
	exit 1
fi

eval set -- "${TGETOPT}"

while [ $# -gt 0 ]; do
	case "$1" in
	-r|--root) LDK_ROOTFS_DIR="$2"; shift ;;
	-h|--help) ShowUsage "$SCRIPT_NAME"; exit 1 ;;
	-d|--debug) DEBUG="true" ;;
	-t|--target-overlay) TARGET_OVERLAY="true" ;;
	-b|--bsp) BSP_DIR="$2"; shift ;;
	--) shift; break ;;
	-*) echo "Terminating... wrong switch: $@" >&2 ; ShowUsage "$SCRIPT_NAME"; exit 1 ;;
	esac
	shift
done

if [ $# -gt 0 ]; then
	ShowUsage "$SCRIPT_NAME"
	exit 1
fi

# fail if the current user is root
FailIfRoot

LDK_NV_TEGRA_DIR="${BSP_DIR}/nv_tegra"
LDK_KERN_DIR="${BSP_DIR}/kernel"
LDK_BOOTLOADER_DIR="${BSP_DIR}/bootloader"

# use default rootfs dir if none is set
if [ -z "$LDK_ROOTFS_DIR" ]; then
	LDK_ROOTFS_DIR="${BSP_DIR}/rootfs"
fi

# get the absolute path, for LDK_ROOTFS_DIR.
# otherwise, tar behaviour is unknown in last command sets
pushd "$LDK_ROOTFS_DIR" > /dev/null 2>&1
LDK_ROOTFS_DIR="$PWD"
popd > /dev/null 2>&1

echo "Using rootfs directory of: ${LDK_ROOTFS_DIR}"

install -m 0755 -d "${LDK_ROOTFS_DIR}"

if [ ! $(find "$LDK_ROOTFS_DIR/etc/passwd" -group "${THIS_USER}" -user "${THIS_USER}") ]; then
	echo "||||||||||||||||||||||| ERROR |||||||||||||||||||||||"
	echo "-----------------------------------------------------"
	echo "1. The root filesystem, provided with this package,"
	echo "   has to be extracted to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "2. The root filesystem, provided with this package,"
	echo "   has to be extracted as your user to this directory:"
	echo "   ${LDK_ROOTFS_DIR}"
	echo "-----------------------------------------------------"
	echo "Consult the Development Guide for instructions on"
	echo "extracting and flashing your device."
	echo "|||||||||||||||||||||||||||||||||||||||||||||||||||||"
	exit 1
fi

if [ "${DEBUG}" == "true" ]; then
	ShowDebug
	START_TIME=$(date +%s)
fi

function ExtractToRootfs() {
	pushd "${LDK_ROOTFS_DIR}" > /dev/null 2>&1
	tar -I lbzip2 -xpmf "${LDK_NV_TEGRA_DIR}/${1}"
	popd > /dev/null 2>&1
}

if [ "${TARGET_OVERLAY}" != "true" ] &&
		[ "${USE_TARGET_OVERLAY_DEFAULT}" != "true" ]; then
	if [ ! -f "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}" ]; then
		echo "Debian script ${DEB_SCRIPT_NAME} not found"
		exit 1
	fi
	echo "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME}";
	eval "${LDK_NV_TEGRA_DIR}/${DEB_SCRIPT_NAME} -r ${LDK_ROOTFS_DIR}";
else
	# install standalone debian packages by extracting and dumping them
	# into the rootfs directly for .tbz2 install flow
	debs=($(ls "${THIS_DIR}/tools"/*.deb))
	for deb in "${debs[@]}"; do
		dpkg -x "${deb}" "${LDK_ROOTFS_DIR}"
	done

	# add gpio as a system group and search unused gid decreasingly from
	# SYS_GID_MAX to SYS_GID_MIN
	gids=($(cut -d: -f3 ${LDK_ROOTFS_DIR}/etc/group))
	for gid in {999..100}; do
		if [[ ! " ${gids[*]} " =~ " ${gid} " ]]; then
			echo "gpio:x:${gid}:" >> ${LDK_ROOTFS_DIR}/etc/group
			echo "gpio:!::" >> ${LDK_ROOTFS_DIR}/etc/gshadow
			break
		fi
	done

	for tarball in ${TARBALLS[@]}; do
		ExtractToRootfs ${tarball}
	done

	echo "Extracting the kernel headers to ${LDK_ROOTFS_DIR}/usr/src"
	# The kernel headers package can be used on the target device as well as on another host.
	# When used on the target, it should go into /usr/src and owned by root.
	# Note that there are multiple linux-headers-* directories; one for use on an
	# x86-64 Linux host and one for use on the L4T target.
	EXTMOD_DIR=ubuntu18.04_aarch64
	KERNEL_HEADERS_A64_DIR="$(tar tf "${LDK_KERN_DIR}/kernel_headers.tbz2" | grep "${EXTMOD_DIR}" | head -1 | cut -d/ -f1)"
	KERNEL_VERSION="$(echo "${KERNEL_HEADERS_A64_DIR}" | sed -e "s/linux-headers-//" -e "s/-${EXTMOD_DIR}//")"
	KERNEL_SUBDIR="kernel-$(echo "${KERNEL_VERSION}" | cut -d. -f1-2)"
	install -m 0755 -d "${LDK_ROOTFS_DIR}/usr/src"
	pushd "${LDK_ROOTFS_DIR}/usr/src" > /dev/null 2>&1
	# This tar is packaged for the host (all files 666, dirs 777) so that when
	# extracted on the host, the user's umask controls the permissions.
	# However, we're now installing it into the rootfs, and hence need to
	# explicitly set and use the umask to achieve the desired permissions.
	(umask 022 && tar -I lbzip2 --no-same-permissions -xmf "${LDK_KERN_DIR}/kernel_headers.tbz2")
	# Link to the kernel headers from /lib/modules/<version>/build
	KERNEL_MODULES_DIR="${LDK_ROOTFS_DIR}/lib/modules/${KERNEL_VERSION}"
	if [ -d "${KERNEL_MODULES_DIR}" ]; then
		echo "Adding symlink ${KERNEL_MODULES_DIR}/build --> /usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}"
		[ -h "${KERNEL_MODULES_DIR}/build" ] && unlink "${KERNEL_MODULES_DIR}/build" && rm -f "${KERNEL_MODULES_DIR}/build"
		[ ! -h "${KERNEL_MODULES_DIR}/build" ] && ln -s "/usr/src/${KERNEL_HEADERS_A64_DIR}/${KERNEL_SUBDIR}" "${KERNEL_MODULES_DIR}/build"
	fi
	popd > /dev/null

	if [ -e "${LDK_KERN_DIR}/zImage" ]; then
		echo "Installing zImage into /boot in target rootfs"
		install --mode=644 -D "${LDK_KERN_DIR}/zImage" "${LDK_ROOTFS_DIR}/boot/zImage"
	fi

	if [ -e "${LDK_KERN_DIR}/Image" ]; then
		echo "Installing Image into /boot in target rootfs"
		install --mode=644 -D "${LDK_KERN_DIR}/Image" "${LDK_ROOTFS_DIR}/boot/Image"
	fi

	echo "Installing the board *.dtb and *.dtbo files into /boot in target rootfs"
	install -m 0755 -d "${LDK_ROOTFS_DIR}"/boot
	cp -a "${LDK_KERN_DIR}"/dtb/*.dtb* "${LDK_ROOTFS_DIR}/boot"
fi

#ARM_ABI_DIR=

if [ -d "${LDK_ROOTFS_DIR}/usr/lib/arm-linux-gnueabihf/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/arm-linux-gnueabihf"
elif [ -d "${LDK_ROOTFS_DIR}/usr/lib/arm-linux-gnueabi/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/arm-linux-gnueabi"
elif [ -d "${LDK_ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/tegra" ]; then
	ARM_ABI_DIR_ABS="usr/lib/aarch64-linux-gnu"
else
	echo "Error: None of Hardfp/Softfp Tegra libs found"
	exit 4
fi

ARM_ABI_DIR="${LDK_ROOTFS_DIR}/${ARM_ABI_DIR_ABS}"
ARM_ABI_TEGRA_DIR="${ARM_ABI_DIR}/tegra"

install -m 0755 -d "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants" > /dev/null 2>&1
if [ -h "isc-dhcp-server.service" ]; then
	rm -f "isc-dhcp-server.service"
fi
if [ -h "isc-dhcp-server6.service" ]; then
	rm -f "isc-dhcp-server6.service"
fi
popd > /dev/null

# Enable Unity by default for better user experience [2332219]
echo "Rename ubuntu.desktop --> ux-ubuntu.desktop"
if [ -d "${LDK_ROOTFS_DIR}/usr/share/xsessions" ]; then
	pushd "${LDK_ROOTFS_DIR}/usr/share/xsessions" > /dev/null 2>&1
	if [ -f "ubuntu.desktop" ]; then
		mv "ubuntu.desktop" "ux-ubuntu.desktop"
	fi
	popd > /dev/null
fi

if [ -e "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" ]; then
	grep -q -F 'allow-guest=false' \
		"${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" \
		|| echo 'allow-guest=false' \
		>> "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf"
fi

# test if installation comes with systemd-gpt-auto-generator. If so, disable it
# this is a WAR for https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1783994
# systemd spams log with "Failed to dissect: Input/output error" on systems with mmc
if [ -e "${LDK_ROOTFS_DIR}/lib/systemd/system-generators/systemd-gpt-auto-generator" ]; then
	if [ ! -d "${LDK_ROOTFS_DIR}/etc/systemd/system-generators" ]; then
		mkdir "${LDK_ROOTFS_DIR}/etc/systemd/system-generators"
	fi
	# this is the way to disable systemd unit auto generators by
	# symlinking the generator to null in corresponding path in /etc
	ln -sf /dev/null "${LDK_ROOTFS_DIR}/etc/systemd/system-generators/systemd-gpt-auto-generator"
fi

echo "Copying USB device mode filesystem image to ${LDK_ROOTFS_DIR}"
install -m 0755 -d "${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode"
cp "${LDK_NV_TEGRA_DIR}/l4t-usb-device-mode-filesystem.img" "${LDK_ROOTFS_DIR}/opt/nvidia/l4t-usb-device-mode/filesystem.img"

# Disabling NetworkManager-wait-online.service for Bug 200290321
echo "Disabling NetworkManager-wait-online.service"
if [ -h "${LDK_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service" ]; then
	rm "${LDK_ROOTFS_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"
fi

echo "Disable the ondemand service by changing the runlevels to 'K'"
for file in "${LDK_ROOTFS_DIR}"/etc/rc[0-9].d/; do
	if [ -f "${file}"/S*ondemand ]; then
		mv "${file}"/S*ondemand "${file}/K01ondemand"
	fi
done

# Remove the spawning of ondemand service
if [ -h "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service" ]; then
	rm -f "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service"
fi

# If default target does not exist and if rootfs contains gdm, set default to nv-oem-config target
if [ ! -e "${LDK_ROOTFS_DIR}/etc/systemd/system/default.target" ] && \
		[ -d "${LDK_ROOTFS_DIR}/etc/gdm3/" ]; then
	mkdir -p "${LDK_ROOTFS_DIR}/etc/systemd/system/nv-oem-config.target.wants"
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/nv-oem-config.target.wants" > /dev/null 2>&1
	ln -sf /lib/systemd/system/nv-oem-config.service nv-oem-config.service
	ln -sf "/etc/systemd/system/nvfb-early.service" "nvfb-early.service"
	popd > /dev/null 2>&1
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system" > /dev/null 2>&1
	ln -sf /lib/systemd/system/nv-oem-config.target nv-oem-config.target
	ln -sf nv-oem-config.target default.target
	popd > /dev/null 2>&1

	extra_groups="EXTRA_GROUPS=\"audio gdm gpio i2c video weston-launch\""
	sed -i "/\<EXTRA_GROUPS\>=/ s/^.*/${extra_groups}/" \
		"${LDK_ROOTFS_DIR}/etc/adduser.conf"
	sed -i "/\<ADD_EXTRA_GROUPS\>=/ s/^.*/ADD_EXTRA_GROUPS=1/" \
		"${LDK_ROOTFS_DIR}/etc/adduser.conf"
fi

if [ -d "${LDK_ROOTFS_DIR}/etc/gdm3/" ] || \
	[ -e "${LDK_ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf" ]; then
	pushd "${LDK_ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants" > /dev/null 2>&1
	if [ -f "${LDK_ROOTFS_DIR}/etc/systemd/system/nvpmodel.service" ]; then
		ln -sf "../nvpmodel.service" "nvpmodel.service"
	fi
	popd > /dev/null 2>&1
fi

if [ -e "${LDK_ROOTFS_DIR}/etc/gdm3/custom.conf" ]; then
	sed -i "/WaylandEnable=false/ s/^#//" "${LDK_ROOTFS_DIR}/etc/gdm3/custom.conf"
fi

if [ -f "${LDK_BOOTLOADER_DIR}/extlinux.conf" ]; then
	echo "Installing extlinux.conf into /boot/extlinux in target rootfs"
	mkdir -p "${LDK_ROOTFS_DIR}/boot/extlinux/"
	install --mode=644 -D "${LDK_BOOTLOADER_DIR}/extlinux.conf" "${LDK_ROOTFS_DIR}/boot/extlinux/"
fi

if [ "${DEBUG}" == "true" ]; then
	END_TIME=$(date +%s)
	TOTAL_TIME=$((${END_TIME}-${START_TIME}))
	echo "Time for applying binaries - $(date -d@${TOTAL_TIME} -u +%H:%M:%S)"
fi

echo "Success!"