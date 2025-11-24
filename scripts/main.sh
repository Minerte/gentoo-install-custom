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

	einfo "Generating ssh host keys"
	try ssh-keygen -A

	einfo "Enabling ugrd and efistub USE flag on sys-kernel/installkernel"
	echo "sys-kernel/installkernel -systemd ugrd efistub" > /etc/portage/package.use/installkernel \
		|| die "Could not write /etc/portage/package.use/installkernel"

	# Install required programs and kernel now, in order to
	# prevent emerging module before an imminent kernel upgrade
	try emerge --verbose sys-kernel/ugrd sys-kernel/gentoo-sources app-arch/zstd

	einfo "Installing extra tools for kernel config"
	try emerge --verbose sys-apps/pciutils

	# Install cryptsetup if we used LUKS
	einfo "Installing cryptsetup and gnupg"
	try emerge --verbose sys-fs/cryptsetup app-crypt/gnupg

	# Install btrfs-progs if we used Btrfs
	einfo "Installing btrfs-progs, ext4 and vfat"
	try emerge --verbose sys-fs/btrfs-progs
	try emerge --verbose sys-fs/e2fsprogs
	try emerge --verbose sys-fs/dosfstools

	einfo "Installing git"
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
	echo "sys-kernel/linux-firmware savedconfig initramfs compress-zstd" >> /etc/portage/package.use \
		|| die "Could not write to /etc/portage/package.use"
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
	local initramfs_path="/boot/efi/${initramfs_name}.img"
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
	try efibootmgr --verbose --create --disk "$gptdev" --part "$efipartnum" --label "gentoo" --loader '\vmlinuz.efi' --unicode 'initrd=\${initramfs_name}'" $(get_cmdline)"

	# Create script to repeat adding efibootmgr entry
	cat > "/boot/efi/efibootmgr_add_entry.sh" <<EOF
#!/bin/bash
# This is the command that was used to create the efibootmgr entry when the
# system was installed using gentoo-install.
efibootmgr --verbose --create --disk "$gptdev" --part "$efipartnum" --label "gentoo" --loader '\\vmlinuz.efi' --unicode 'initrd=\\${initramfs_name}'" $(get_cmdline)"
EOF

# TESTING 
}

function generate_initramfs() {
	local initramfs_path="$1"
	# TESTING
	local kver="$2"

	# Generate initramfs
	einfo "Generating initramfs with ugRD"

	# Create ugRD configuration file
	local config_file="/etc/ugrd/config.toml"

	# TESTING NEW
	# Create temporary ugRD config
	cat > "$config_file" <<EOF
# ugRD configuration generated by gentoo-install
# Modules to include
modules = [
	"ugrd.kmod.usb",
	"ugrd.crypto.gpg",
	"ugrd.crypto.cryptsetup",
	]

auto_mounts = ['/boot']

# Keymap for initramfs
# [config.init]
keymap = "$KEYMAP_INITRAMFS"
EOF

	# GET ROOT UUID
	local root_uuid_id="$DISK_ID_ROOT"
    root_uuid_id="${DISK_ID_LUKS_TO_UNDERLYING_ID[$root_uuid_id]}"
	local root_uuid
	root_uuid="$(get_blkid_uuid_for_id "$root_uuid_id")"

cat >> "$config_file" <<EOF

[cryptsetup.cryptroot]
uuid = "$root_uuid"
key_type = "gpg"
key_file = "/boot/cryptroot_key.luks.gpg"
EOF

	# GET SWAP UUID
	if [[ -v "DISK_ID_SWAP" ]]; then
		local swap_uuid_id="$DISK_ID_SWAP"
		swap_uuid_id="${DISK_ID_LUKS_TO_UNDERLYING_ID[$swap_uuid_id]}"
		local swap_uuid
		swap_uuid="$(get_blkid_uuid_for_id "$swap_uuid_id")"

		cat >> "$config_file" <<EOF

[cryptsetup.cryptswap]
uuid = "$swap_uuid"
key_type = "gpg"
key_file = "/boot/cryptswap_key.luks.gpg"
EOF

	fi # This ends the SWAP UUID

	# Generate initramfs with ugRD
	try ugrd --kver "$kver" "$initramfs_path"

	# Alternatively, use command-line options (less recommended):
	# try ugrd \\
	#     --kernel-version "$kver" \\
	#     --output "$initramfs_path" \\
	#     --compression zstd \\

	# Create script to repeat initramfs generation
	cat > "$(dirname "$initramfs_path")/generate_initramfs.sh" <<EOF
#!/bin/bash
kver="\\$1"
output="\\$2" # At setup time, this was "$initramfs_path"
[[ -n "\\$kver" ]] || { echo "usage \\$0 <kernel_version> <output>" >&2; exit 1; }

# Generate with ugRD using config file
ugrd --kernel-version "\\$kver" --output "\\$initramfs_path" --config /etc/ugrd/config.toml

# Or use command-line options:
# ugrd \\
#     --kernel-version "\\$kver" \\
#     --output "\\$initramfs_path" \\
#     --compression zstd \\
EOF

# Need editing to support GPG-keyfile
# TESTING NEW
}

function get_cmdline() {
    local cmdline=("rd.vconsole.keymap=$KEYMAP_INITRAMFS")
    
	# For LUKS, root should point to the mapper device, not the UUID
    cmdline+=("root=/dev/mapper/cryptroot")
    
    # Add filesystem type
    cmdline+=("rootfstype=btrfs")
    
    # Add btrfs subvolume if you're using one
    cmdline+=("rootflags=subvol=root")
    
    # Additional options
    cmdline+=("ro" "quiet")
    
    echo -n "${cmdline[*]}"
}

function generate_fstab() {
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_INSTALL_REPO_DIR/contrib/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"
	if [[ -n $DISK_ID_ROOT_TYPE ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_ROOT_MOUNT_OPTS" "0 1"
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_HOME_MOUNT_OPTS"	"0 0"
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_ETC_MOUNT_OPTS"	"0 0"
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_VAR_MOUNT_OPTS"	"0 0"
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_LOG_MOUNT_OPTS"	"0 0"
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_TMP_MOUNT_OPTS"	"0 0"
	fi
	if [[ $IS_EFI == "true" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_EFI")" "/boot/efi" "vfat" "defaults,noatime,fmask=0177,dmask=0077,noexec,nodev,nosuid,discard" "0 2"
	fi
	if [[ -v "DISK_ID_SWAP" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_SWAP")" "none" "swap" "defaults,discard" "0 0"
	fi
}

function add_fstab_entry() {
	printf '%-46s  %-24s  %-6s  %-96s %s\n' "$1" "$2" "$3" "$4" "$5" >> /etc/fstab \
		|| die "Could not append entry to fstab"
}

###############################
## mount chroot after install

function main_chroot() {
	# Skip if already mounted
	mountpoint -q -- "$1" \
		|| die "'$1' is not a mountpoint"

	gentoo_chroot "$@"
}