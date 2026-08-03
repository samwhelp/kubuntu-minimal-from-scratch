#!/usr/bin/env bash


################################################################################
## HARDENED KUBUNTU 26.04 LTS (RESOLUTE) MINIMAL ISO ENGINE FROM SCRATCH
## Fully Corrected Dynamic String Expansion for Cloud Build Actions Platforms
## Hybrid BIOS + UEFI Boot Support
################################################################################


################################################################################
## Environment
################################################################################

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive


################################################################################
## Permission
################################################################################

user_root_required () {
	if [ $(id -u) -ne 0 ]; then
		echo "This script should be run as 'root'"
		exit 1
	fi
}

user_root_required


################################################################################
## Option
################################################################################

##
## Pipeline Target Configurations
##

CODENAME="resolute"
MIRROR="http://archive.ubuntu.com/ubuntu"

BUILD_DIR="/opt/tmp/kubuntu-hardened-build"
ROOTFS="${BUILD_DIR}/chroot"
IMAGE_DIR="${BUILD_DIR}/iso_structure"
ISO_OUT="${GITHUB_WORKSPACE:-/opt/tmp}/kubuntu-26.04-minimal-hardened.iso"
ISO_VOLID="KUBUNTU_RESOLVE"

#DEBOOTSTRAP_SCRIPT="/usr/share/debootstrap/scripts/noble"
DEBOOTSTRAP_SCRIPT=""

TARGET_HOSTNAME="kubuntu-live"

TARGET_INIT_LOCALES="C.UTF-8 en_US.UTF-8"
TARGET_DEFAULT_LOCALE="en_US.UTF-8"

################################################################################
## Module
################################################################################

##
## https://github.com/mvallim/live-custom-ubuntu-from-scratch/blob/master/scripts/build.sh#L46
##

raw_mount () {
	mount --bind /dev "${ROOTFS}/dev"
	mount --bind /run "${ROOTFS}/run"
	chroot "${ROOTFS}" mount none -t proc /proc
	chroot "${ROOTFS}" mount none -t sysfs /sys
	chroot "${ROOTFS}" mount none -t devpts /dev/pts
}

raw_unmount () {
	chroot "${ROOTFS}" umount -l /proc || true
	chroot "${ROOTFS}" umount -l /sys || true
	chroot "${ROOTFS}" umount -l /dev/pts || true
	umount -l "${ROOTFS}/dev" || true
	umount -l "${ROOTFS}/run" || true
}

try_unmount_prototype () {
	umount "${ROOTFS}/proc" || umount -lf "${ROOTFS}/proc" || true
	umount "${ROOTFS}/sys" || umount -lf "${ROOTFS}/sys" || true
	umount "${ROOTFS}/dev/pts" || umount -lf "${ROOTFS}/dev/pts" || true
	umount "${ROOTFS}/dev" || umount -lf "${ROOTFS}/dev" || true
	umount "${ROOTFS}/run" || umount -lf "${ROOTFS}/run" || true

	umount "${IMAGE_DIR}/boot/efi" || umount -lf "${IMAGE_DIR}/boot/efi" || true
}

try_unmount () {
	local mnt=""
	for mnt in proc sys dev/pts dev run; do
		umount "${ROOTFS}/${mnt}" || umount -lf "${ROOTFS}/${mnt}" || true
	done

	for mnt in boot/efi; do
		umount "${IMAGE_DIR}/${mnt}" || umount -lf "${IMAGE_DIR}/${mnt}" || true
	done
}

let_unmount () {
	local mnt=""
	for mnt in proc sys dev/pts dev run; do
		if mountpoint -q "${ROOTFS}/${mnt}"; then
			umount "${ROOTFS}/${mnt}" || umount -lf "${ROOTFS}/${mnt}" || true
		fi
	done
}

sys_mount () {
	raw_mount
}

sys_unmount () {
	try_unmount
	raw_unmount
}

mod_mount () {
	sys_unmount
	sys_mount
}

mod_unmount () {
	sys_unmount
}

################################################################################
## Signal
################################################################################

# 2. Advanced Signal Trap Cleanup Handler (Aligned with exact mounts)
cleanup () {
	echo "################################################################################"
	echo "## [ Event  ] 🚨 Signal caught or process ended. Commencing filesystem safety cleanup..."
	echo "################################################################################"
	##set +e
	mod_unmount
	echo "################################################################################"
	echo "## [ Result ] 🧹 Cleanup sequence finished."
	echo "################################################################################"
}
trap cleanup EXIT INT TERM

################################################################################
## Prepare host packages for building iso file.
################################################################################

echo "################################################################################"
echo "## [Step 1/8] Environment Setup & Packaging Dependencies"
echo "################################################################################"

apt-get update
apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin binutils gdisk rsync zstd


################################################################################
## Build Steps Start
################################################################################

mod_unmount

rm -rf "${BUILD_DIR}"

mkdir -p "${ROOTFS}"


################################################################################
## Create Base System
################################################################################

echo "################################################################################"
echo "## [Step 2/8] Instantiating Clean Resolute Raccoon Operating System Tree"
echo "################################################################################"

debootstrap --variant=minbase --components=main,universe,restricted,multiverse \
	--include=ca-certificates,openssl,console-setup-linux,console-setup,locales,tzdata,whiptail,wget,dbus \
	"${CODENAME}" "${ROOTFS}" "${MIRROR}" "${DEBOOTSTRAP_SCRIPT}"

################################################################################
## Target System / Mount
################################################################################

echo "################################################################################"
echo "## [Step 3/8] Bridging Virtual Host Kernel Filesystem Tables"
echo "################################################################################"

##cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"

##
## ## Virtual Mount Binding Execution
##

echo "I: Mount before chroot"
mod_mount


################################################################################
## Target System / Run Chroot Script
################################################################################

echo "################################################################################"
echo "## [Step 4/8] Run Chroot Script Start"
echo "################################################################################"

cat << __CHROOT_SCRIPT__ | chroot "${ROOTFS}" /bin/bash

### target os fulfill build steps ###

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

MIRROR="${MIRROR}"
CODENAME="${CODENAME}"
TARGET_HOSTNAME="${TARGET_HOSTNAME}"
TARGET_INIT_LOCALES="${TARGET_INIT_LOCALES}"
TARGET_DEFAULT_LOCALE="${TARGET_DEFAULT_LOCALE}"


##
## ## Locale / Init Locales
##

echo "Init Locales"
echo locale-gen --lang \${TARGET_INIT_LOCALES}
locale-gen --lang \${TARGET_INIT_LOCALES}


##
## ## Host Name / Config
##

echo "\${TARGET_HOSTNAME}" > "/etc/hostname"


##
## ## Machine Id / Config
##

dbus-uuidgen > /etc/machine-id
ln -fs /etc/machine-id /var/lib/dbus/machine-id


##
## ## Apt Sources
##

echo "Migrating repository mappings to DEB822 layout structure..."
if [ -f /etc/apt/sources.list ]; then
	mv /etc/apt/sources.list /etc/apt/sources.list.bak
fi

mkdir -p /etc/apt/sources.list.d

# SOURCES is unquoted to allow variable expansion inside the chroot context
cat << __EOF__ > /etc/apt/sources.list.d/ubuntu.sources
Types: deb
URIs: \${MIRROR}
Suites: \${CODENAME}
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: \${MIRROR}
Suites: \${CODENAME}-updates
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: \${MIRROR}
Suites: \${CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: \${MIRROR}
Suites: \${CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
__EOF__


##
## ## Upgrade First
##

## 0. Upgrade packages which installed by debootstrap
apt-get update
apt-get dist-upgrade -y


##
## ## Systemd
##

apt-get install -y \
	systemd-sysv \
--install-recommends


##
## ## Kernel
##

##
## ## Base System Kernel, Compression & Microcode Hardware Layer
##

apt-get install -y \
	linux-generic linux-firmware \
	initramfs-tools zstd \
	thermald \
--no-install-recommends


##
## ## Boot Loader
##

apt-get install -y \
	os-prober \
	grub-common \
	grub-gfxpayload-lists \
	grub-pc \
	grub-pc-bin \
	grub2-common \
	grub-efi-amd64-signed \
	shim-signed \
	efibootmgr \
--install-recommends


##
## ## Casper
##

##
## ## Live Boot Orchestration Engines (Casper Infrastructure)
##
## * https://github.com/VCHui/ubuntu-16.04-desktop-custom-iso/blob/master/remaster-initrds/custom/etc/casper.conf
## * https://github.com/AiursoftWeb/AnduinOS-2/blob/master/mods/46-casper-patch/install.sh
## * https://github.com/Anduin2017/AnduinOS/blob/1.4/src/mods/08-casper-and-kernel-install-mod/install.sh
## * https://github.com/Anduin2017/AnduinOS/blob/1.4/src/mods/44-casper-patch/install.sh
##

apt-get install -y \
	casper \
	discover \
	laptop-detect \
	os-prober \
	keyutils \
--no-install-recommends

cat << __EOF__ | tee /etc/casper.conf > /dev/null 2>&1
# This file should go in /etc/casper.conf
# Supported variables are:
# USERNAME, USERFULLNAME, HOST, BUILD_SYSTEM, FLAVOUR

export USERNAME="live"
export USERFULLNAME="Kubuntu Live session user"
export HOST="kubuntu"
export BUILD_SYSTEM="Ubuntu"

# USERNAME and HOSTNAME as specified above won't be honoured and will be set to
# flavour string acquired at boot time, unless you set FLAVOUR to any
# non-empty string.

export FLAVOUR="Kubuntu"
__EOF__


##
## ## Network / Base
##

apt-get install -y \
	network-manager net-tools resolvconf \
	iputils-ping iproute2 iw \
--install-recommends

mkdir -p "/etc/NetworkManager"

cat << __EOF__ > "/etc/NetworkManager/NetworkManager.conf"
[main]
rc-manager=resolvconf
plugins=ifupdown,keyfile
dns=dnsmasq

[ifupdown]
managed=false
__EOF__

mkdir -p "/etc/netplan"

cat << __EOF__ > "/etc/netplan/01-network-manager-all.yaml"
network:
  version: 2
  renderer: NetworkManager
__EOF__


##
## ## Sound
##

apt-get install -y \
	alsa-utils \
	pulseaudio pamixer \
	pipewire \
--install-recommends


##
## ## Shell
##

apt-get install -y \
	bash \
	bash-completion \
--install-recommends


##
## ## Text Editor
##

apt-get install -y \
	nano \
	vim \
--install-recommends


##
## ## Locale / Default Locale
##

echo "Set default locale to \${TARGET_DEFAULT_LOCALE}"
echo "LANG=\${TARGET_DEFAULT_LOCALE}" > /etc/locale.conf


##
## ## initramfs
##

## Generate initramfs for all installed kernels
echo "Generating initramfs..."
update-initramfs -c -k all


##
## ## Machine Id / Clear
##

truncate -s 0 /etc/machine-id || true
truncate -s 0 /var/lib/dbus/machine-id || true


##
## ## Cleanup
##

## Final: Space-Saving Optimizations
find /usr/share/doc -depth -type f ! -name copyright -delete || true
find /usr/share/man -type f -delete || true
rm -rf /usr/share/groff/* /usr/share/info/* /var/cache/man/*

apt-get autoremove --purge -y
apt-get clean
rm -rf /tmp/* /var/lib/apt/lists/*
__CHROOT_SCRIPT__

echo "################################################################################"
echo "## [Step 4/8] Run Chroot Script End"
echo "################################################################################"


################################################################################
## Archive Steps Start
################################################################################

mkdir -p "${IMAGE_DIR}/casper"
mkdir -p "${IMAGE_DIR}/boot/grub"
mkdir -p "${IMAGE_DIR}/.disk"


################################################################################
## Copy Kernel
################################################################################

##
## ## Extract Kernel Assets For Media Boot Loader
##

echo "################################################################################"
echo "## [Step 5/8] Pulling Boot Kernel and Initial Boot Ramdisk Images"
echo "################################################################################"

KERNEL_VERSION=$(ls "${ROOTFS}/boot"/vmlinuz-* 2>/dev/null | head -n 1 | sed 's/.*vmlinuz-//')

if [ -z "${KERNEL_VERSION}" ]; then
	echo "ERROR: No kernel found in ${ROOTFS}/boot"
	exit 1
fi

cp "${ROOTFS}/boot/vmlinuz-${KERNEL_VERSION}" "${IMAGE_DIR}/casper/vmlinuz"
cp "${ROOTFS}/boot/initrd.img-${KERNEL_VERSION}" "${IMAGE_DIR}/casper/initrd"


################################################################################
## Archive / filesystem.squashfs
################################################################################

##
## ## Compress Live Workspace File Container
##

echo "################################################################################"
echo "## [Step 6/8] Recompressing Sandbox System into Squashfs Container"
echo "################################################################################"

mod_unmount

##mksquashfs "${ROOTFS}" "${IMAGE_DIR}/casper/filesystem.squashfs" -comp xz -b 1M -noappend

mksquashfs "${ROOTFS}" "${IMAGE_DIR}/casper/filesystem.squashfs" \
	-noappend -no-duplicates -no-recovery \
	-wildcards -b 1M \
	-comp zstd -Xcompression-level 19 \
	-e "var/cache/apt/archives/*" \
	-e "tmp/*" \
	-e "tmp/.*" \
	-e "swapfile"


printf "%s" "$(du -sx --block-size=1 "${ROOTFS}" | cut -f1)" | tee "${IMAGE_DIR}/casper/filesystem.size" > /dev/null

##
## ## Create filesystem.manifest
##

chroot "${ROOTFS}" dpkg-query -W --showformat='${Package} ${Version}\n' \
	> "${IMAGE_DIR}/casper/filesystem.manifest"

##
## ## Create desktop manifest copy and prune installer/live-only packages (optional)
##

cp "${IMAGE_DIR}/casper/filesystem.manifest" "${IMAGE_DIR}/casper/filesystem.manifest-desktop"
# remove packages that shouldn't be in desktop manifest (adjust patterns as needed)
sed -i -E '/(casper|ubiquity|live|calamares|cloud-init)/Id' "${IMAGE_DIR}/casper/filesystem.manifest-desktop" || true


################################################################################
## Disk Info
################################################################################

##
## ## Create file: [iso_structure/.disk/info]
##

echo "Kubuntu 26.04 | amd64 | ($(date +%Y%m%d)) Release" | tee "${IMAGE_DIR}/.disk/info"


################################################################################
## ISO grub config
################################################################################

##
## ## Dual-Boot Layout Configuration Matrix
##

echo "################################################################################"
echo "## [Step 7/8] Deploying Unified Hybrid Bootloader Rules"
echo "################################################################################"


##
## ## for search --set=root --file /kubuntu
##

touch "${IMAGE_DIR}/kubuntu"

cat << __EOF__ > "${IMAGE_DIR}/boot/grub/grub.cfg"

search --set=root --file /kubuntu

set default="0"
set timeout=5

insmod all_video
insmod gfxterm

menuentry "Kubuntu 26.04 Resolute (Boot)" {
	set gfxpayload=keep
	linux /casper/vmlinuz boot=casper nopersistent ---
	initrd /casper/initrd
}

__EOF__


################################################################################
## Archive / target.iso
################################################################################

##
## ## Master Production ISO Output Image via xorriso
##

echo "################################################################################"
echo "## [Step 8/8] Mastering Bootable Hybrid Image via Xorriso"
echo "################################################################################"

pushd "${IMAGE_DIR}" > /dev/null 2>&1

echo
echo "##"
echo "## [Work Dir] $(pwd)"
echo "##"
echo

##
## ## Create BIOS boot image
##

mkdir -p "${IMAGE_DIR}/boot/grub/i386-pc"

echo "Copy GRUB i386-pc modules into ISO layout ..."
cp -f /usr/lib/grub/i386-pc/*.mod "${IMAGE_DIR}/boot/grub/i386-pc/"
cp -f /usr/lib/grub/i386-pc/*.lst "${IMAGE_DIR}/boot/grub/i386-pc/"

##
## Create core.img / Way 1
##

#grub-mkimage -o "${IMAGE_DIR}/boot/grub/i386-pc/core.img" -O i386-pc -p /boot/grub biosdisk ext2 fat iso9660 search


##
## ## Create core.img / Way 2
##

grub-mkstandalone \
	--format="i386-pc" \
	--output="${IMAGE_DIR}/boot/grub/i386-pc/core.img" \
	--install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls font gfxterm all_video" \
	--modules="linux16 linux normal iso9660 biosdisk search font gfxterm all_video" \
	--locales="" \
	--fonts="" \
	"boot/grub/grub.cfg=boot/grub/grub.cfg"


##
## ## Notice:
##
## run
##
## ...
## grub-mkstandalone -O i386-pc \
##	--output="${IMAGE_DIR}/boot/grub/i386-pc/grub-standalone.img" \
##	--install-modules="biosdisk part_msdos part_gpt normal linux iso9660 search" \
##	"boot/grub/grub.cfg=${IMAGE_DIR}/boot/grub/grub.cfg"
## ...
##
## show
##
## ...
## grub-mkstandalone: error: core image is too big (0x1c03c1 > 0x78000).
## ...
##


##
## ## Create bios.img
##

echo "Creating BIOS boot image on iso_structure/boot/grub/i386-pc/bios.img ..."
cat /usr/lib/grub/i386-pc/cdboot.img "${IMAGE_DIR}/boot/grub/i386-pc/core.img" > "${IMAGE_DIR}/boot/grub/i386-pc/bios.img"


##
## ## Create EFI boot image
##

echo "Copy GRUB x86_64-efi modules into ISO layout ..."
mkdir -p "${IMAGE_DIR}/boot/grub/x86_64-efi"
cp -f /usr/lib/grub/x86_64-efi/*.mod "${IMAGE_DIR}/boot/grub/x86_64-efi/"
cp -f /usr/lib/grub/x86_64-efi/*.lst "${IMAGE_DIR}/boot/grub/x86_64-efi/"


# --- produce a standalone EFI binary (grub EFI executable) and create a FAT efi.img ---
# create an EFI binary (this embeds the config that we already wrote to ${IMAGE_DIR}/boot/grub/grub.cfg)

rm -f "/tmp/BOOTX64.EFI"

grub-mkstandalone \
	--format="x86_64-efi" \
	--output="/tmp/BOOTX64.EFI" \
	--install-modules="efi_gop normal linux iso9660 search" \
	"boot/grub/grub.cfg=boot/grub/grub.cfg"

# make a small FAT image to use as the EFI system partition
rm -f "${IMAGE_DIR}/boot/efi.img"
dd if=/dev/zero of="${IMAGE_DIR}/boot/efi.img" bs=1M count=64 status=none || true
mkfs.vfat -n EFI "${IMAGE_DIR}/boot/efi.img"

# mount, populate, then unmount
#TMPDIR="$(mktemp -d)"
TMPDIR="${IMAGE_DIR}/boot/efi"
umount "${TMPDIR}" || umount -lf "${TMPDIR}" || true
rm -rf "${TMPDIR}"
mkdir -p "${TMPDIR}"
mount -o loop "${IMAGE_DIR}/boot/efi.img" "${TMPDIR}"
mkdir -p "${TMPDIR}/EFI/BOOT" "${TMPDIR}/boot/grub"
cp -f /tmp/BOOTX64.EFI "${TMPDIR}/EFI/BOOT/BOOTX64.EFI"
# copy the grub folder (modules + config) so grub can find modules if needed
cp -rfT "${IMAGE_DIR}/boot/grub" "${TMPDIR}/boot/grub"
sync
umount "${TMPDIR}" || umount -lf "${TMPDIR}" || true
rm -rf "${TMPDIR}"
rm -f /tmp/BOOTX64.EFI


##
## ## Generate md5sum list for casper-md5check (exclude md5sum.txt itself)
##

find . -type f -print0 \
	| xargs -0 md5sum \
	| sed 's|^\./||' \
	| grep -v -E '(^md5sum.txt$|/boot/grub/i386-pc/eltorito.img$)' \
	> md5sum.txt


##
## ## Create hybrid ISO with both BIOS and UEFI support
##

echo "Creating hybrid ISO with both BIOS and UEFI support ..."

xorriso -as mkisofs \
	-iso-level 3 \
	-o "${ISO_OUT}" \
	-full-iso9660-filenames \
	-volid "KUBUNTU_RESOLVE" \
	-appid "Kubuntu 26.04 Resolute Hardened" \
	-partition_offset 16 \
	-A "Kubuntu Resolute 26.04 LTS" \
	-b boot/grub/i386-pc/bios.img \
		-c boot/boot.catalog \
		-no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
	--efi-boot boot/efi.img \
		-efi-boot-part --efi-boot-image \
	"."


popd > /dev/null 2>&1


################################################################################
## Result
################################################################################

echo "################################################################################"
echo "## ✅ SUCCESS! Your custom hardened minimal Kubuntu ISO is available at:"
echo "## 📦 ${ISO_OUT}"
echo "################################################################################"

if [ -f "${ISO_OUT}" ]; then
	ISO_SIZE=$(du -h "${ISO_OUT}" | cut -f1)
	echo "################################################################################"
	echo "## 📏 Size: ${ISO_SIZE}"
	echo "## 🚀 Ready to boot from USB or VM!"
	echo "################################################################################"
	ls -lh "${ISO_OUT}"
	echo "################################################################################"
else
	echo "################################################################################"
	echo "## [ Result ] ❌ ISO creation failed!"
	echo "################################################################################"
	exit 1
fi
