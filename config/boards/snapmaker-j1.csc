# --- Snapmaker J1 (Qualcomm) ---
BOARD_NAME="Snapmaker J1"
BOARDFAMILY="msm8909"          
LINUXFAMILY="msm8909"          

RELEASE="trixie"
BRANCH="snapmakerj1"

# U-Boot bauen wir nicht (lk2nd übernimmt die Rolle des First/Second Stage)
UBOOT_CONFIGURE="no"
BOOTCONFIG="none"

# Kernel is set in config/sources/families/msm8909.conf
# KERNEL_CONFIGURE="no"
# KERNELSOURCE='https://github.com/msm8916-mainline/linux.git'
# KERNELBRANCH='tag:v6.12.1-msm8916'        # alternativ: branch:<name> oder tag:<vX.Y.Z>
# KERNEL_MAJOR_MINOR='6.12'
KERNEL_TARGET="snapmakerj1"
# KERNEL_GIT="shallow"

# Space-separated list of patch dirs. Each is looked up under BOTH patch/kernel/<dir>
# (core) and userpatches/kernel/<dir> (user):
#   archive/msm8909-6.12 -> core patchset: copies dt/snapmakerj1.dts and auto-patches the
#                           qcom DT Makefile, so snapmakerj1.dtb is built & installed.
#   msm8909-edl          -> userpatches/kernel/msm8909-edl/*.patch (reboot-to-edl).
KERNELPATCHDIR='archive/msm8909-6.12 msm8909-edl'


# Root-FS und Kernel-Image-Format wie gewohnt
CLI_BETA="yes"                 # optional: CLI-Image-Variante erlauben
IMAGE_PARTITION_TABLE="gpt"    # sinnvoll auf eMMC
ARCH="armhf"

# Rockchip RK3328 in Artillery3D X4 Pro/Plus 3D-printer
# Makerbase MKS based board
# Quad core eMMC USB3 WIFI
# NDOR="Armbian"
BOARD_MAINTAINER="eazrael"
BUILD_MINIMAL="no"
#KERNEL_TARGET="current,edge"
SOURCE_COMPILE="yes"
# It's a printer
HAS_VIDEO_OUTPUT="yes"
BUILD_DESKTOP="no"
FULL_DESKTOP="no"
BOOT_LOGO="yes"
WIREGUARD="no"

#Settings for the internal emmc space
#FIXED_IMAGE_SIZE="7456"
ROOTFS_TYPE="ext4"

SRC_EXTLINUX="yes"
declare -g EXTLINUX_UINITRD=no
# TODO hardcoded, derive 
SRC_CMDLINE="systemd.loglevel=info 8250.nr_uarts=0 fbcon=rotate:3 firmware_class.path=/firmware/image aus_armbian"
NAME_INITRD=initrd.img-6.12.1-snapmakerj1-msm8909
BOOTSIZE="120"
BOOTFS_TYPE="ext2"
AUFS="no"
# for testing no compression
COMPRESS_OUTPUTIMAGE="sha,none"
IMAGE_XZ_COMPRESSION_RATIO=1
BOOT_FDT_FILE="snapmakerj1.dtb"


# change "Armbian-unofficial
# No wireguard in a printer...
#PACKAGE_LIST_BOARD="xterm file armbian-config iotop-c"
PACKAGE_LIST_BOARD="xterm file iotop-c i2c-tools spi-tools linux-cpupower openocd moreutils zstd"
PACKAGE_LIST_BOARD_REMOVE="linux-dtb-current-rockchip64 nfs-common vnstat"
REPOSITORY_INSTALL="armbian-config armbian-firmware"
INSTALL_HEADERS="yes" # install kernel headers package
NETWORKING_STACK="network-manager"

function post_family_tweaks__msm8909_some_tweaks() {
    display_alert "${BOARD}"  "Configuring zram" "info"
    #chroot_sdcard sed -i 's/^ENABLED=true$/ENABLED=false/' /etc/default/armbian-zram-config
    printf '\nZRAM_PERCENTAGE=13\nMEM_LIMIT_PERCENTAGE=15\n' >> "${SDCARD}/etc/default/armbian-zram-config"
    # Service is already enabled by the build default (distro-agnostic.sh) + BSP postinst;
    # this is an explicit, correctly-named re-enable (idempotent) so it can't silently regress.
    chroot_sdcard systemctl enable armbian-zram-config.service
    
    display_alert "${BOARD}"  "Disabling ramlog" "info"
    chroot_sdcard systemctl disable armbian-ramlog
    # Masking is the cleanest way of prevent this service, but then armbian-build fails
    # chroot_sdcard systemctl mask armbian-ramlog.service
    chroot_sdcard rm -f /lib/systemd/system/armbian-ramlog.service
        
    display_alert "${BOARD}"  "Disabling default device trees" "info"
    chroot_sdcard apt-mark hold linux-dtb-current-rockchip64 || true
    chroot_sdcard apt-mark hold linux-dtb-current-rockchip || true


    return 0
}

# The panel is physically mounted rotated. Console (fbcon=rotate:3) and KlipperScreen
# compensate in software, but Plymouth renders straight to DRM and ignores fbcon rotation,
# so its splash comes out 90 deg clockwise off. The two-step module has no rotation option,
# so we pre-rotate the theme's image assets 90 deg counter-clockwise to compensate.
# AI generated
function post_family_tweaks__snapmakerj1_rotate_plymouth_splash() {
    [[ $PLYMOUTH != yes ]] && return 0

    local theme_dir="${SDCARD}/usr/share/plymouth/themes/armbian"
    [[ -d "${theme_dir}" ]] || return 0

    display_alert "${BOARD}" "Rotating Plymouth splash assets 90 deg CCW to match panel" "info"
    local img
    for img in "${theme_dir}"/*.png; do
        [[ -f "${img}" ]] || continue
        run_host_command_logged convert "${img}" -rotate -90 "${img}"
    done

    return 0
}

# Protect the custom kernel and the hand-crafted boot setup from unattended-upgrades.
# The kernel debs are installed locally (no repo candidate), so they cannot be upgraded
# today, but we blacklist the kernel/BSP/bootloader package families anyway so that a
# future repo candidate -- or an Armbian BSP update whose maintainer scripts regenerate
# extlinux.conf / armbianEnv.txt / the initramfs -- can never silently desync boot.
# Security updates for everything else keep working.
# AI generated
function post_family_tweaks__snapmakerj1_unattended_upgrades_guard() {
    local conf="${SDCARD}/etc/apt/apt.conf.d/52-snapmakerj1-unattended-blacklist"
    [[ -d "${SDCARD}/etc/apt/apt.conf.d" ]] || return 0

    display_alert "${BOARD}" "Blacklisting kernel/boot packages from unattended-upgrades" "info"
    cat > "${conf}" <<- 'EOF'
		// Snapmaker J1: keep unattended-upgrades away from the custom kernel and
		// the hand-crafted boot artifacts. Entries are regex-matched name prefixes.
		Unattended-Upgrade::Package-Blacklist {
		        "linux-image";
		        "linux-dtb";
		        "linux-headers";
		        "linux-cpupower";
		        "linux-libc-dev";
		        "armbian-bsp";
		        "armbian-bootloader";
		};
	EOF

    return 0
}

# Cap journald so logs can't bloat the eMMC. armbian-ramlog is deliberately disabled on
# this board (RAM logs lose recent messages on a hard power-off, which is bad on a printer),
# so /var/log persists to flash -- without a limit it grows unbounded (seen: 182 MB). A
# drop-in deterministically overrides the main journald.conf regardless of what Armbian's
# zram sed did. SystemMaxUse bounds persistent storage; logs survive power cuts, bounded size.
# AI generated
function post_family_tweaks__snapmakerj1_journald_limits() {
    local dropin_dir="${SDCARD}/etc/systemd/journald.conf.d"
    run_host_command_logged mkdir -p "${dropin_dir}"

    display_alert "${BOARD}" "Capping journald to 50M / 7 days on flash" "info"
    cat > "${dropin_dir}/limits.conf" <<- 'EOF'
		[Journal]
		SystemMaxUse=50M
		SystemKeepFree=100M
		MaxRetentionSec=7day
	EOF

    return 0
}

# Tune VM behavior for a low-RAM, latency-sensitive Klipper host. Complements the small zram
# safety-net (ZRAM_PERCENTAGE=13): swappiness=10 stops the kernel swapping anon pages until it
# truly must, protecting Klipper's near-RT timing; vfs_cache_pressure=50 keeps dentry/inode
# cache resident longer, cutting eMMC metadata re-reads on a 1 GB system.
# AI generated
function post_family_tweaks__snapmakerj1_sysctl_klipper() {
    local dropin="${SDCARD}/etc/sysctl.d/99-klipper.conf"
    [[ -d "${SDCARD}/etc/sysctl.d" ]] || return 0

    display_alert "${BOARD}" "Writing Klipper VM sysctl tuning (swappiness=10)" "info"
    cat > "${dropin}" <<- 'EOF'
		vm.swappiness=10
		vm.vfs_cache_pressure=50
	EOF

    return 0
}

# NOTE: the WCNSS WiFi firmware setup (load from the device's own modem/persist partitions,
# ship no blobs) is static rootfs config, so it lives as real files in userpatches/overlay:
#   etc/tmpfiles.d/wcnss-firmware.conf            per-device prima NV/dict symlinks -> /persist
#   etc/modprobe.d/wcnss-defer.conf               block udev autoload of qcom_wcnss_pil
#   etc/systemd/system/wcnss-firmware.service     modprobe it after the partitions are mounted
#   etc/systemd/system/multi-user.target.wants/   pre-created enable symlink for that service
# The modem/persist mounts it depends on are appended below in the pre_umount fstab hook, and
# firmware_class.path=/firmware/image is already on the kernel cmdline via SRC_CMDLINE.

# Shorten the ext4 root commit interval. partitioning.sh generates the root fstab line as
#   UUID=... / ext4 defaults,,commit=120,errors=remount-ro 0 1
# (the ',,' is an upstream quirk: mountopts[ext4] already starts with a comma). partitioning
# runs AFTER post_family_tweaks and rewrites fstab from scratch, so editing it in those hooks
# would be overwritten -- pre_umount_final_image fires once fstab is in the mounted image
# (${MOUNT}), so we sed it here. 120s -> 60s shrinks the data-loss window on a hard power-off
# (the normal way a printer is switched off); the double comma is collapsed for tidiness.
# relatime stays as-is (kernel default; noatime's marginal eMMC gain isn't worth it).
# AI generated
function pre_umount_final_image__snapmakerj1_fstab_commit() {
    local fstab="${MOUNT}/etc/fstab"
    [[ -f "${fstab}" ]] || return 0

    display_alert "${BOARD}" "Reducing ext4 root commit interval to 60s in fstab" "info"
    # Call sed directly, NOT via run_host_command_logged: that runner re-parses its args
    # through `bash -c "$*"`, which would strip our quoting and choke on the '(' and ';'.
    sed -i -E -e 's/(defaults),,/\1,/' -e 's/commit=[0-9]+/commit=60/' "${fstab}"
    run_host_command_logged cat "${fstab}"

    return 0
}

# Mount the Qualcomm vendor partitions the WLAN/modem stack needs. partitioning.sh
# regenerates fstab from scratch AFTER post_family_tweaks, so (like the commit-interval
# tweak above) these lines have to be appended here in pre_umount_final_image, once fstab
# exists in the mounted image (${MOUNT}). Both are read-only and nofail so a missing or
# unformatted partition never blocks boot on this printer; x-systemd.device-timeout caps
# how long boot waits for the by-partlabel device to appear.
#   - modem   -> /firmware : holds the modem/WLAN firmware images. SRC_CMDLINE already
#                points firmware_class.path at /firmware/image, so this is its mount.
#   - persist -> /persist  : per-device WCNSS WLAN calibration; the tmpfiles.d drop-in
#                symlinks the prima NV files here (see etc/tmpfiles.d/wcnss-firmware.conf).
# modem is FAT-formatted on this device (mmcblk0p9, vfat); persist is ext4 mounted noload
# (skip journal replay on a read-only mount).
# AI generated
function pre_umount_final_image__snapmakerj1_vendor_mounts() {
    local fstab="${MOUNT}/etc/fstab"
    [[ -f "${fstab}" ]] || return 0

    display_alert "${BOARD}" "Appending modem/persist vendor mounts to fstab" "info"
    cat >> "${fstab}" <<- 'EOF'
		/dev/disk/by-partlabel/modem    /firmware  vfat  ro,nofail,x-systemd.device-timeout=10s          0 0
		/dev/disk/by-partlabel/persist  /persist   ext4  ro,noload,nofail,x-systemd.device-timeout=10s   0 0
	EOF
    run_host_command_logged cat "${fstab}"

    return 0
}
