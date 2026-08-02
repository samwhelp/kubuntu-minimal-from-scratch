#!/usr/bin/env bash


################################################################################
## Environment
################################################################################

set -Eeuo pipefail

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
## Main Steps Start
################################################################################


################################################################################
## Gen Chroot Script
################################################################################

echo "################################################################################"
echo "## [Step 1/1] Gen Chroot Script"
echo "################################################################################"

cat << __CHROOT_SCRIPT__ | tee chroot-script.sh > /dev/null 2>&1

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

apt install -y \
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
## ## Desktop Environment
##

## Desktop Shell & Requested Core Apps (Konsole, Dolphin, Kate)
apt-get install -y \
	kde-plasma-desktop plasma-workspace \
	kio-extras systemsettings xinit xserver-xorg-core xserver-xorg-video-all \
	plasma-nm kdenetwork \
	konsole dolphin kate kde-spectacle \
--install-recommends


##
## ## Policykit
##

apt-get install -y \
	polkit-kde-agent-1 policykit-desktop-privileges \
--no-install-recommends


##
## ## System Installer
##

## Calamares Installer & Kubuntu Configurations
apt-get install -y \
	calamares calamares-settings-kubuntu kubuntu-settings-desktop \
--no-install-recommends


##
## ## Resolved some issues where errors occurred when installing the system using the calamares installer.
##


##
## ## Remove line: [      - kubuntu-installer-prompt]
##

if [ -e "/etc/calamares/modules/packages.conf" ]; then
	sed -i '/kubuntu-installer-prompt/d' "/etc/calamares/modules/packages.conf"
fi


##
## ## keep /etc/apt/sources.list exist for calamares installer
##

touch /etc/apt/sources.list


##
## Please see file:
##
## * /etc/calamares/settings.conf
## * /etc/calamares/modules/before_bootloader_context.conf
## * /etc/calamares/modules/shellprocess_rmcdrom.conf
##

##
## ## keep /etc/apt/sources.list.d/cdrom.sources exist for calamares installer
##

mkdir -p /etc/apt/sources.list.d

touch /etc/apt/sources.list.d/cdrom.sources

##
## or fix file: [/etc/calamares/modules/before_bootloader_context.conf]
##
## from
##         -    command: rm /tmp/calamares-cdrom-sources/cdrom.sources
## to
##         -    command: rm -f /tmp/calamares-cdrom-sources/cdrom.sources
##

##
## or fix file: [/etc/calamares/modules/shellprocess_rmcdrom.conf]
##
## from
##     - rm \${ROOT}/etc/apt/sources.list.d/cdrom.sources
## to
##     - rm -f \${ROOT}/etc/apt/sources.list.d/cdrom.sources
##




##
## ## Software Helper
##

apt-get install -y \
	update-notifier-common ubuntu-release-upgrader-core apport \
--no-install-recommends


##
## ## Display Manager / SDDM
##

apt-get install -y \
	sddm \
--no-install-recommends

## Configure SDDM autologin for KDE Plasma (adjust Session if needed)
mkdir -p /etc/sddm.conf.d
cat << __EOF__ | tee /etc/sddm.conf.d/50-autologin.conf > /dev/null 2>&1
[Autologin]
User=kubuntu
Session=plasma.desktop
__EOF__


##
## ## Network / Extra
##

apt-get install -y \
	network-manager-applet nm-connection-editor \
	network-manager-openconnect-gnome network-manager-openvpn-gnome network-manager-pptp-gnome \
	bluetooth blueman bluez \
--install-recommends


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
