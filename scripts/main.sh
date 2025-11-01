# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1

function main_install() {
	[[ $# == 0 ]] || die "Too many arguments"

	gentoo_umount # is a Function in file "Functions.sh"
	install_stage3 # in main.sh

	[[ $IS_EFI == "true" ]] \
		&& mount_efivars
	gentoo_chroot "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_BIND/install" __install_gentoo_in_chroot

	umount_gpg_storage # from functions.sh
}

function install_stage3() {
	prepare_installation_environment # is a Function in file "Functions.sh"
	apply_disk_configuration # comming from functions.sh
	download_stage3 # Comming from functions.sh
	extract_stage3 # Comming from functions.sh
}

function main_install_gentoo_in_chroot() {
	[[ $# == 0 ]] || die "Too many arguments"

	# Remove the root password, making the account accessible for automated
	# tasks during the period of installation.
	einfo "Clearing root password"
	passwd -d root \
		|| die "Could not change root password"

	# Sync portage
	einfo "Syncing portage tree"
	try emerge --sync --quiet

	if [[ $IS_EFI == "true" ]]; then
		# Mount efi partition
		mount_efivars
		einfo "Mounting efi partition"
		mount_by_id "$DISK_ID_EFI" "/boot/efi"
	else
        # Cant have bios
        exit 0;
	fi

	# Configure basic system things like timezone, locale, ...
	configure_base_system # from same file

	# Prepare portage environment
	configure_portage # from same file

	# Copy GPG keys for LUKS
	if [[ -f "$TMP_DIR/cryptroot-KEY.gpg" ]]; then
		einfo "Copying GPG key for rootfs"
		install -m0600 "$TMP_DIR/cryptroot-KEY.gpg" "/boot/rootfs.luks.gpg" || die "Could not copy GPG key for rootfs"
	fi
	if [[ -f "$TMP_DIP/cryptswap-KEY.gpg" ]]; then
		einfo "Copying GPG key for swap"
		install -m0600 "$TMP_DIR/cryptswap-KEY.gpg" "/boot/swapfs.luks.gpg" || die "Could not copy GPG key for swap"
	fi

	# Install git (for git portage overlays)
	einfo "Installing git"
	try emerge --verbose dev-vcs/git

	einfo "Generating ssh host keys"
	try ssh-keygen -A

	einfo "Enabling urgd and efistub USE flag on sys-kernel/installkernel"
	echo "sys-kernel/installkernel urgd efistub" > /etc/portage/package.use/installkernel \
		|| die "Could not write /etc/portage/package.use/installkernel"

	# Install required programs and kernel now, in order to
	# prevent emerging module before an imminent kernel upgrade
	try emerge --verbose sys-kernel/ugrd sys-kernel/gentoo-sources app-arch/zstd

	einfo "Installing extra tools for kernel config"
	try emerge --verbose sys-apps/pciutils

	# Install cryptsetup if we used LUKS
	if [[ $USED_LUKS == "true" ]]; then
		einfo "Installing cryptsetup"
		try emerge --verbose sys-fs/cryptsetup
	fi

	# Install btrfs-progs if we used Btrfs
	if [[ $USED_BTRFS == "true" ]]; then
		einfo "Installing btrfs-progs"
		try emerge --verbose sys-fs/btrfs-progs
	fi

	try emerge --verbose dev-vcs/git

	# Install kernel and initramfs
	install_kernel # in same file

	# Generate a valid fstab file
	generate_fstab # in same file

	# Install gentoolkit
	einfo "Installing gentoolkit"
	try emerge --verbose app-portage/gentoolkit

	# Install and enable dhcpcd
	einfo "Installing dhcpcd"
	try emerge --verbose net-misc/dhcpcd

	enable_service dhcpcd

	# Install additional packages, if any.
	if [[ ${#ADDITIONAL_PACKAGES[@]} -gt 0 ]]; then
		einfo "Installing additional packages"
		# shellcheck disable=SC2086
		try emerge --verbose --autounmask-continue=y -- "${ADDITIONAL_PACKAGES[@]}"
	fi

	if ask "Do you want to assign a root password now?"; then
		try passwd root
		einfo "Root password assigned"
	else
		try passwd -d root
		ewarn "Root password cleared, set one as soon as possible!"
	fi

	einfo "Gentoo installation complete."
	[[ $USED_LUKS == "true" ]] \
		&& einfo "A backup of your luks headers can be found at '$LUKS_HEADER_BACKUP_DIR', in case you want to have a backup."
	einfo "You may now reboot your system or execute ./install --chroot $ROOT_MOUNTPOINT to enter your system in a chroot."
	einfo "Chrooting in this way is always possible in case you need to fix something after rebooting."
}


function configure_base_system() {
	einfo "Generating locales"
	echo "$LOCALES" > /etc/locale.gen \
		|| die "Could not write /etc/locale.gen"
	locale-gen \
		|| die "Could not generate locales"

	# Set hostname
	einfo "Selecting hostname"
	sed -i "/hostname=/c\\hostname=\"$HOSTNAME\"" /etc/conf.d/hostname \
		|| die "Could not sed replace in /etc/conf.d/hostname"

	einfo "Selecting timezone"
	echo "$TIMEZONE" > /etc/timezone \
		|| die "Could not write /etc/timezone"
	chmod 644 /etc/timezone \
		|| die "Could not set correct permissions for /etc/timezone"
	try emerge -v --config sys-libs/timezone-data

	# Set keymap
	einfo "Selecting keymap"
	sed -i "/keymap=/c\\keymap=\"$KEYMAP\"" /etc/conf.d/keymaps \
		|| die "Could not sed replace in /etc/conf.d/keymaps"

	# Set locale
	einfo "Selecting locale"
	try eselect locale set "$LOCALE"

	# Update environment
	env_update # From functions.sh
}

function configure_portage() {
	# Prepare /etc/portage for autounmask
	mkdir_or_die 0755 "/etc/portage/package.use"
	touch_or_die 0644 "/etc/portage/package.use/zz-autounmask"
	mkdir_or_die 0755 "/etc/portage/package.keywords"
	touch_or_die 0644 "/etc/portage/package.keywords/zz-autounmask"
	touch_or_die 0644 "/etc/portage/package.license"

	chmod 644 /etc/portage/make.conf \
		|| die "Could not chmod 644 /etc/portage/make.conf"
}

function install_kernel() {
	einfo "Avalible kernel version: (from gentoo-sources)"
	try eselect kernel list
	local kernel_choice
	read -p "Enter the number of the kernel to use: " kernel_choice
	if ! [[ "$kernel_choice" =~ ^[0-9]+$ ]]; then
		die "Invalid input. Please enter a number."
	fi 
	try eselect kernel set "$kernel_choice"

	einfo "Compiling kernel with make menuconfig (for manual edits)"
	cd /usr/src/linux || die "Could not cd into /usr/src/linux"
	local config_dist
	read -p "Do you want to use make defconfig? For easier setup later. y/n: " config_dist
	if [[ "$config_dist" == y ]]; then
		try make defconfig
	fi
	try make menuconfig
	try make -j$(nproc)
	try make modules_install
	try make install

	install_kernel_efi

	einfo "Installing linux-firmware"
	echo "sys-kernel/linux-firmware linux-fw-redistributable no-source-code" >> /etc/portage/package.license \
		|| die "Could not write to /etc/portage/package.license"
	try emerge --verbose linux-firmware
}


function install_kernel_efi() {
	try emerge --verbose sys-boot/efibootmgr

	# Copy kernel to EFI
	local kernel_file
	kernel_file="$(find "/boot" \( -name "vmlinuz-*" -or -name 'kernel-*' -or -name 'vmlinuz' \) -printf '%f\n' | sort -V | tail -n 1)" \
		|| die "Could not list newest kernel file"

	try cp "/boot/$kernel_file" "/boot/efi/vmlinuz.efi"

	# TESTING
	local kver
	kver="$(readlink /usr/src/linux)" \
		|| die "Could not figure out kernel version from /usr/src/linux symlink."
	kver="${kver#linux-}"

	local initramfs_name="initramfs-${kver}.img"
	local initramfs_path="/boot/efi/${initramfs_name}"
	# TESTING

	# TESTING
	# Generate initramfs
	generate_initramfs "${initramfs_path}" "${kver}" 
	# TESTING

	# Create boot entry
	einfo "Creating EFI boot entry"
	local efipartdev
	efipartdev="$(resolve_device_by_id "$DISK_ID_EFI")" \
		|| die "Could not resolve device with id=$DISK_ID_EFI"
	efipartdev="$(realpath "$efipartdev")" \
		|| die "Error in realpath '$efipartdev'"

	# Get the sysfs path to EFI partition
	local sys_efipart
	sys_efipart="/sys/class/block/$(basename "$efipartdev")" \
		|| die "Could not construct /sys path to EFI partition"

	# Extract partition number, handling both standard and RAID cases
	local efipartnum
	if [[ -e "$sys_efipart/partition" ]]; then
		efipartnum="$(cat "$sys_efipart/partition")" \
			|| die "Failed to find partition number for EFI partition $efipartdev"
	else
		efipartnum="1" # Assume partition 1 if not found, common for RAID-based EFI
		einfo "Assuming partition 1 for RAID-based EFI on device $efipartdev"
	fi

	# Identify the parent block device and create EFI boot entry
	local gptdev
		# Non-RAID case: Create a single EFI boot entry
	gptdev="/dev/$(basename "$(readlink -f "$sys_efipart/..")")" \
		|| die "Failed to find parent device for EFI partition $efipartdev"
	if [[ ! -e "$gptdev" ]] || [[ -z "$gptdev" ]]; then
		gptdev="$(resolve_device_by_id "${DISK_ID_PART_TO_GPT_ID[$DISK_ID_EFI]}")" \
			|| die "Could not resolve device with id=${DISK_ID_PART_TO_GPT_ID[$DISK_ID_EFI]}"
	fi

	# TESTING
	try efibootmgr --verbose --create --disk "$gptdev" --part "$efipartnum" --label "gentoo" --loader \'\\vmlinuz.efi\' --unicode \'initrd=\\${initramfs_name}\'" $(get_cmdline)"

	# Create script to repeat adding efibootmgr entry
	cat > "/boot/efi/efibootmgr_add_entry.sh" <<EOF
#!/bin/bash
# This is the command that was used to create the efibootmgr entry when the
# system was installed using gentoo-install.
efibootmgr --verbose --create --disk "$gptdev" --part "$efipartnum" --label "gentoo" --loader \'\\\\vmlinuz.efi\' --unicode \'initrd=\\\\${initramfs_name}\'" $(get_cmdline)"
EOF

# TESTING 
}

function generate_initramfs() {
	local output="$1"
	# TESTING
	local kver="$2"

	# Generate initramfs
	einfo "Generating initramfs with ugRD"

	# TESTING 
	#local kver
	#kver="$(readlink /usr/src/linux)" \
	#	|| die "Could not figure out kernel version from /usr/src/linux symlink."
	#kver="${kver#linux-}"
	# TESTING

	# Create ugRD configuration file
	local config_file="/etc/ugrd/config.toml"

	# Build ugRD modules list
	# local ugrd_modules=()
	# ugrd_modules+=("base")  # Base module is always needed
	# [[ $USED_LUKS == "true" ]] \
	#	&& ugrd_modules+=("crypt")
	# [[ $USED_BTRFS == "true" ]] \
	#	&& ugrd_modules+=("btrfs")

# TESTING
# 	# Create temporary ugRD config
# 	cat > "$config_file" <<EOF
# # ugRD configuration generated by gentoo-install
# [config]
# kernel_version = "$kver"
# output = "$output"
# compression = "zstd"
# hostonly = false

# # Modules to include
# modules = [
# $(printf '    "%s",\n' "${ugrd_modules[@]}")
# ]

# # Keymap for initramfs
# [config.init]
# keymap = "$KEYMAP_INITRAMFS"

# EOF

# 	# Add LUKS-specific configuration if needed
# 	if [[ $USED_LUKS == "true" ]]; then
# 		cat >> "$config_file" <<EOF
# [crypt]
# # LUKS/dm-crypt configuration
# gpg_support = true

# EOF

# 		local gpg_mount
# 		gpg_mount="$(mount_gpg_storage)"
# 		mkdir -p /etc/ugrd/gpg
#         cp "$gpg_mount/luks-key.gpg" /etc/ugrd/gpg/

# 	fi

# 	# Generate initramfs with ugRD
# 	try ugrd --config "$config_file" --kernel-version "$kver"

# 	# Alternatively, use command-line options (less recommended):
# 	# try ugrd \
# 	#     --kernel-version "$kver" \
# 	#     --output "$output" \
# 	#     --compression zstd \
# 	#     --modules "${ugrd_modules[*]}"

# 	# Create script to repeat initramfs generation
# 	cat > "$(dirname "$output")/generate_initramfs.sh" <<EOF
# #!/bin/bash
# kver="\$1"
# output="\$2" # At setup time, this was "$output"
# [[ -n "\$kver" ]] || { echo "usage \$0 <kernel_version> <output>" >&2; exit 1; }

# # Generate with ugRD using config file
# ugrd --kernel-version "\$kver" --output "\$output" --config /etc/ugrd/config.toml

# # Or use command-line options:
# # ugrd \\
# #     --kernel-version "\$kver" \\
# #     --output "\$output" \\
# #     --compression zstd \\
# #     --modules ${ugrd_modules[*]}
# EOF

# Need editing to support GPG-keyfile
# TESTING

	# TESTING NEW
	# Create temporary ugRD config
	cat > "$config_file" <<EOF
# ugRD configuration generated by gentoo-install
[config]
output = "$output"
compression = "zstd"
hostonly = false

# Modules to include
modules = [
  "ugrd.kmod.usb",
  "ugrd.crypto.gpg",
  "ugrd.crypto.cryptsetup",
  "ugrd.fs.btrfs",
]

auto_mount = ['/boot']

root_subvol="root"

# Keymap for initramfs
[config.init]
keymap = "$KEYMAP_INITRAMFS"

[cryptsetup]
  [cryptsetup.root]
  key_file = "/boot/rootfs.luks.gpg"
  header_file = "/boot/root_luks_header.img"

  [cryptsetup.swap]
  key_file = "/boot/swapfs.luks.gpg"
  header_file = "/boot/swap_luks_header.img"

# Key have been moved?

EOF

	# Generate initramfs with ugRD
	try ugrd --config "$config_file" --kernel-version "$kver"

	# Alternatively, use command-line options (less recommended):
	# try ugrd \\
	#     --kernel-version "$kver" \\
	#     --output "$output" \\
	#     --compression zstd \\
	#     --modules "${ugrd_modules[*]}"

	# Create script to repeat initramfs generation
	cat > "$(dirname "$output")/generate_initramfs.sh" <<EOF
#!/bin/bash
kver="\\$1"
output="\\$2" # At setup time, this was "$output"
[[ -n "\\$kver" ]] || { echo "usage \\$0 <kernel_version> <output>" >&2; exit 1; }

# Generate with ugRD using config file
ugrd --kernel-version "\\$kver" --output "\\$output" --config /etc/ugrd/config.toml

# Or use command-line options:
# ugrd \\\\
#     --kernel-version "\\$kver" \\\\
#     --output "\\$output" \\\\
#     --compression zstd \\\\
#     --modules ${ugrd_modules[*]}
EOF

# Need editing to support GPG-keyfile
# TESTING NEW
}

function generate_fstab() {
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_INSTALL_REPO_DIR/contrib/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"
	if [[ $USED_ZFS != "true" && -n $DISK_ID_ROOT_TYPE ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_ROOT_MOUNT_OPTS" "0 1"
	fi
	if [[ $IS_EFI == "true" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_EFI")" "/boot/efi" "vfat" "defaults,noatime,fmask=0177,dmask=0077,noexec,nodev,nosuid,discard" "0 2"
	else
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_BIOS")" "/boot/bios" "vfat" "defaults,noatime,fmask=0177,dmask=0077,noexec,nodev,nosuid,discard" "0 2"
	fi
	if [[ -v "DISK_ID_SWAP" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_SWAP")" "none" "swap" "defaults,discard" "0 0"
	fi
}