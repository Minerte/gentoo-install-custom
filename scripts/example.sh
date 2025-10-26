#!/bin/bash
# Example implementation of custom disk layout functions
# This file shows how to implement create_boot_storage_disk_layout and create_gpg_disk_layout
# 
# Usage in gentoo.conf:
# function disk_configuration() {
#   create_boot_storage_disk_layout type=efi luks=true /dev/sdBOOT
#   create_gpg_disk_layout swap=8GiB luks=true root_fs=btrfs /dev/sdROOT
# }

# This function should be added to scripts/config.sh
function create_boot_storage_disk_layout() {
	local known_arguments=('?type' '?luks' '?boot_fs')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -eq 1 ]] \
		|| die_trace 1 "Expected exactly one positional argument (the device)"
	
	local device="${extra_arguments[0]}"
	local type="${arguments[type]:-efi}"
	local use_luks="${arguments[luks]:-false}"
	local boot_fs="${arguments[boot_fs]:-ext4}"

	# Create GPT partition table on boot device
	create_gpt new_id=gpt_boot device="$device"
	
	# Create EFI partition (partition 1)
	create_partition new_id=part_efi id=gpt_boot size=512MiB type=efi
	
	# Create GPG keyfile storage partition (partition 2)
	create_partition new_id=part_gpg_storage id=gpt_boot size=remaining type=linux

	# Optionally encrypt the GPG storage partition
	local gpg_storage_id="part_gpg_storage"
	if [[ "$use_luks" == "true" ]]; then
		create_luks new_id=part_luks_gpg_storage name="gpg_storage" id=part_gpg_storage
		gpg_storage_id="part_luks_gpg_storage"
	fi

	# Format the partitions
	# BOOT1: EFI partition formatted as FAT32 (vfat)
	format id=part_efi type=efi label=efi
	# BOOT2: GPG storage partition formatted as ext4 (ignoring boot_fs parameter)
	format id="$gpg_storage_id" type=ext4 label=gpg_storage

	# Set global variables for the installation
	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_efi"
	else
		DISK_ID_BIOS="part_efi"
	fi
	DISK_ID_GPG_STORAGE="$gpg_storage_id"
}

# This function should be added to scripts/config.sh
function create_gpg_disk_layout() {
	local known_arguments=('+swap' '?type' '?luks' '?root_fs')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -eq 1 ]] \
		|| die_trace 1 "Expected exactly one positional argument (the device)"

	local device="${extra_arguments[0]}"
	local size_swap="${arguments[swap]}"
	local type="${arguments[type]:-efi}"
	local use_luks="${arguments[luks]:-false}"
	local root_fs="${arguments[root_fs]:-ext4}"

	# Create GPT partition table on root device
	create_gpt new_id=gpt_root device="$device"
	
	# Create swap partition (partition 1)
	create_partition new_id=part_swap id=gpt_root size="$size_swap" type=swap
	
	# Create root partition (partition 2)
	create_partition new_id=part_root id=gpt_root size=remaining type=linux

	# Optionally encrypt the root partition
	local root_id="part_root"
	if [[ "$use_luks" == "true" ]]; then
		create_luks new_id=part_luks_root name="root" id=part_root
		root_id="part_luks_root"
	fi

	# Format the partitions
	[[ $size_swap != "false" ]] \
		&& format id=part_swap type=swap label=swap
	format id="$root_id" type="$root_fs" label=root

	# Set global variables for the installation
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP=part_swap
	DISK_ID_ROOT="$root_id"

	# Set filesystem type and mount options
	if [[ $root_fs == "btrfs" ]]; then
		DISK_ID_ROOT_TYPE="btrfs"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/root"
	elif [[ $root_fs == "ext4" ]]; then
		DISK_ID_ROOT_TYPE="ext4"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,errors=remount-ro,discard"
	else
		die "Unsupported root filesystem type"
	fi
}

# Additional functions that may be needed in scripts/functions.sh for GPG keyfile support

function mount_gpg_storage() {
	# Mount point for GPG storage partition (BOOT2 - ext4 formatted)
	local gpg_mount="$TMP_DIR/gpg_storage"
	
	if [[ ! -v DISK_ID_GPG_STORAGE ]]; then
		die "DISK_ID_GPG_STORAGE is not set. Did you use create_boot_storage_disk_layout?"
	fi

	# Check if already mounted
	if mountpoint -q -- "$gpg_mount"; then
		echo "$gpg_mount"
		return 0
	fi

	# Mount the GPG storage partition (ext4 formatted)
	einfo "Mounting GPG storage partition (BOOT2, ext4) to $gpg_mount"
	mount_by_id "$DISK_ID_GPG_STORAGE" "$gpg_mount"
	
	echo "$gpg_mount"
}

function umount_gpg_storage() {
	local gpg_mount="$TMP_DIR/gpg_storage"
	
	if mountpoint -q -- "$gpg_mount"; then
		einfo "Unmounting GPG storage partition"
		umount "$gpg_mount" \
			|| die "Could not unmount GPG storage partition"
	fi
}

function read_gpg_keyfile() {
	local gpg_mount
	gpg_mount="$(mount_gpg_storage)"
	
	local keyfile="$gpg_mount/luks-key.gpg"
	
	if [[ ! -f "$keyfile" ]]; then
		die "GPG keyfile not found at $keyfile"
	fi

	# Decrypt the GPG keyfile and return the key
	# This assumes you have a GPG-encrypted file containing your LUKS key
	gpg --decrypt "$keyfile" 2>/dev/null \
		|| die "Could not decrypt GPG keyfile"
}

function setup_gpg_keyfile() {
	local gpg_mount
	gpg_mount="$(mount_gpg_storage)"
	
	local keyfile="$gpg_mount/luks-key.gpg"
	
	if [[ -f "$keyfile" ]]; then
		ewarn "GPG keyfile already exists at $keyfile"
		ask "Do you want to overwrite it?" || return 0
	fi

	einfo "Creating GPG-encrypted keyfile for LUKS"
	einfo "GPG storage is mounted at: $gpg_mount (BOOT2, ext4 formatted)"
	einfo "The script has full read/write access to this partition"
	
	# Generate a random key and encrypt it with GPG
	# You'll need to have GPG keys set up beforehand
	dd if=/dev/urandom bs=512 count=1 2>/dev/null \
		| gpg --encrypt --armor --recipient "$GPG_KEY_ID" \
		> "$keyfile" \
		|| die "Could not create GPG-encrypted keyfile"
	
	chmod 600 "$keyfile" \
		|| die "Could not set permissions on GPG keyfile"
	
	einfo "GPG keyfile created at $keyfile"
	einfo "You can read/write additional files to $gpg_mount while it's mounted"
}

function mount_efi_partition() {
	# Mount the EFI partition (BOOT1 - FAT32/vfat formatted) for bootloader installation
	local efi_mount="$ROOT_MOUNTPOINT/boot"
	
	if [[ ! -v DISK_ID_EFI ]]; then
		die "DISK_ID_EFI is not set"
	fi

	# Check if already mounted
	if mountpoint -q -- "$efi_mount"; then
		return 0
	fi

	# Mount the EFI partition (FAT32 formatted, BOOT1)
	einfo "Mounting EFI partition (BOOT1, vfat/FAT32) to $efi_mount"
	mount_by_id "$DISK_ID_EFI" "$efi_mount"
}

# Modified disk_create_luks function that uses GPG keyfile
# This would replace or extend the function in scripts/functions.sh
function disk_create_luks_with_gpg() {
	local new_id="${arguments[new_id]}"
	local name="${arguments[name]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		if [[ -v arguments[id] ]]; then
			add_summary_entry "${arguments[id]}" "$new_id" "luks" "" ""
		else
			add_summary_entry __root__ "$new_id" "${arguments[device]}" "(luks)" ""
		fi
		return 0
	fi

	local device
	local device_desc=""
	if [[ -v arguments[id] ]]; then
		device="$(resolve_device_by_id "${arguments[id]}")"
		device_desc="$device ($id)"
	else
		device="${arguments[device]}"
		device_desc="$device"
	fi

	local uuid="${DISK_ID_TO_UUID[$new_id]}"

	einfo "Creating luks ($new_id) on $device_desc using GPG keyfile"
	
	# Get the encryption key from GPG keyfile
	local encryption_key
	encryption_key="$(read_gpg_keyfile)" \
		|| die "Could not read GPG keyfile"
	
	cryptsetup luksFormat \
			--type luks2 \
			--uuid "$uuid" \
			--key-file <(echo -n "$encryption_key") \
			--cipher aes-xts-plain64 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			--key-size 512 \
			--batch-mode \
			"$device" \
		|| die "Could not create luks on $device_desc"
	
	mkdir -p "$LUKS_HEADER_BACKUP_DIR" \
		|| die "Could not create luks header backup dir '$LUKS_HEADER_BACKUP_DIR'"
	
	local header_file="$LUKS_HEADER_BACKUP_DIR/luks-header-$id-${uuid,,}.img"
	[[ ! -e $header_file ]] \
		|| rm "$header_file" \
		|| die "Could not remove old luks header backup file '$header_file'"
	
	cryptsetup luksHeaderBackup "$device" \
			--header-backup-file "$header_file" \
		|| die "Could not backup luks header on $device_desc"
	
	cryptsetup open --type luks2 \
			--key-file <(echo -n "$encryption_key") \
			"$device" "$name" \
		|| die "Could not open luks encrypted device $device_desc"
}

# Example of how to modify the apply_disk_action function to use GPG
# This would be added to the case statement in scripts/functions.sh
function apply_disk_action_gpg_example() {
	unset known_arguments
	unset arguments; declare -A arguments; parse_arguments "$@"
	case "${arguments[action]}" in
		'existing')          disk_existing         ;;
		'create_gpt')        disk_create_gpt       ;;
		'create_partition')  disk_create_partition ;;
		'create_luks')       
			# Check if GPG keyfile should be used
			if [[ -v DISK_ID_GPG_STORAGE ]]; then
				disk_create_luks_with_gpg
			else
				disk_create_luks
			fi
			;;
		'create_dummy')      disk_create_dummy     ;;
		'format')            disk_format           ;;
		'format_btrfs')      disk_format_btrfs     ;;
		*) echo "Ignoring invalid action: ${arguments[action]}" ;;
	esac
}

# ===============================================================================
# EXECUTION ORDER AND TIMING
# ===============================================================================
#
# These functions should be called at specific points in the installation flow:
#
# DURING DISK CONFIGURATION (Before chroot, in main_install -> install_stage3):
# -----------------------------------------------------------------------------
# 1. After apply_disk_configuration() completes:
#    - Partitions are created and formatted
#    - LUKS volumes are created but NOT yet opened with GPG key
#
# 2. Call setup_gpg_keyfile():
#    - Mounts BOOT2 (GPG storage partition)
#    - Creates the GPG-encrypted keyfile
#    - This should be done BEFORE creating LUKS on ROOT2 if you want to use
#      the GPG keyfile for encryption
#
# ALTERNATIVE: If you want to use GPG keyfile for existing LUKS:
# -----------------------------------------------------------------------------
# - You would need to modify disk_create_luks() in functions.sh to call
#   read_gpg_keyfile() instead of using GENTOO_INSTALL_ENCRYPTION_KEY
# - This happens automatically during apply_disk_configuration()
#
# DURING STAGE3 EXTRACTION (Before chroot):
# -----------------------------------------------------------------------------
# 3. After download_stage3() and before/during extract_stage3():
#    - mount_root() is called (mounts ROOT2)
#    - The GPG storage may need to remain mounted if you need to access
#      the keyfile during later stages
#
# DURING CHROOT OPERATIONS (Inside chroot, in main_install_gentoo_in_chroot):
# -----------------------------------------------------------------------------
# 4. After entering chroot, before bootloader installation:
#    - mount_efi_partition() is called to mount BOOT1 to /boot/efi
#    - This is done in the existing code at line 39 of main.sh:
#      mount_by_id "$DISK_ID_EFI" "/boot/efi"
#
# 5. During initramfs generation (in generate_initramfs()):
#    - If using GPG keyfile for LUKS unlock at boot, you need to:
#      a) Copy the GPG keyfile to the initramfs
#      b) Configure ugRD to use GPG for LUKS unlock
#      c) This requires modifying generate_initramfs() function
#
# CLEANUP (After installation completes):
# -----------------------------------------------------------------------------
# 6. Before final reboot:
#    - umount_gpg_storage() - Unmount the GPG storage partition
#    - This would be added to the cleanup section in main_install()
#
# ===============================================================================
# RECOMMENDED INTEGRATION POINTS
# ===============================================================================
#
# A) In scripts/main.sh, modify install_stage3():
#
#    function install_stage3() {
#        prepare_installation_environment
#        apply_disk_configuration
#        
#        # NEW: Set up GPG keyfile after disk configuration
#        if [[ -v DISK_ID_GPG_STORAGE ]]; then
#            setup_gpg_keyfile
#        fi
#        
#        download_stage3
#        extract_stage3
#    }
#
# B) In scripts/main.sh, modify main_install():
#
#    function main_install() {
#        [[ $# == 0 ]] || die "Too many arguments"
#        
#        gentoo_umount
#        install_stage3
#        
#        [[ $IS_EFI == "true" ]] \
#            && mount_efivars
#        gentoo_chroot "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_BIND/install" __install_gentoo_in_chroot
#        
#        # NEW: Clean up GPG storage mount after chroot exits
#        if [[ -v DISK_ID_GPG_STORAGE ]]; then
#            umount_gpg_storage
#        fi
#    }
#
# C) In scripts/main.sh, the mount_efi_partition() function is already
#    essentially implemented at line 39:
#        mount_by_id "$DISK_ID_EFI" "/boot/efi"
#    So you don't need to change this, unless you want a dedicated function.
#
# D) In scripts/functions.sh, modify disk_create_luks() to use GPG keyfile:
#
#    function disk_create_luks() {
#        # ... existing code ...
#        
#        # Determine which key source to use
#        local key_source
#        if [[ -v DISK_ID_GPG_STORAGE && -n "$DISK_ID_GPG_STORAGE" ]]; then
#            # Use GPG keyfile
#            key_source="$(read_gpg_keyfile)"
#        else
#            # Use traditional password
#            key_source="$GENTOO_INSTALL_ENCRYPTION_KEY"
#        fi
#        
#        cryptsetup luksFormat \
#            --type luks2 \
#            --uuid "$uuid" \
#            --key-file <(echo -n "$key_source") \
#            # ... rest of options ...
#    }
#
# E) In scripts/main.sh, modify generate_initramfs() to include GPG support:
#
#    function generate_initramfs() {
#        local output="$1"
#        
#        # ... existing code ...
#        
#        if [[ $USED_LUKS == "true" ]]; then
#            cat >> "$config_file" <<EOF
#    [crypt]
#    # LUKS/dm-crypt configuration
#    gpg_support = true
#    
#    EOF
#            
#            # NEW: Copy GPG keyfile to initramfs
#            if [[ -v DISK_ID_GPG_STORAGE ]]; then
#                local gpg_mount
#                gpg_mount="$(mount_gpg_storage)"
#                mkdir -p /etc/ugrd/gpg
#                cp "$gpg_mount/luks-key.gpg" /etc/ugrd/gpg/
#            fi
#        fi
#        
#        # ... rest of function ...
#    }
#
# ===============================================================================
# Summary:
# 
# To integrate this into your installation:
# 
# 1. Add create_boot_storage_disk_layout() to scripts/config.sh
# 2. Add create_gpg_disk_layout() to scripts/config.sh
# 3. Add the following functions to scripts/functions.sh:
#    - mount_gpg_storage()
#    - umount_gpg_storage()
#    - read_gpg_keyfile()
#    - setup_gpg_keyfile()
#    - mount_efi_partition()
# 4. Modify disk_create_luks() in scripts/functions.sh to optionally use GPG keyfile
# 5. Add DISK_ID_GPG_STORAGE variable tracking to scripts/config.sh (after line 27)
# 6. Set up your GPG keys before running the installation
# 7. Create the GPG-encrypted keyfile on the boot storage partition
# 
# The layout will be:
# 
# /dev/sdBOOT1 - EFI partition (512MB, FAT32/vfat formatted)
#                Format: mkfs.fat -F 32 (via format type=efi)
#                Mounted to: $ROOT_MOUNTPOINT/boot (typically /tmp/gentoo-install/root/boot)
#                Purpose: Boot files, EFI bootloader
# 
# /dev/sdBOOT2 - GPG keyfile storage (remaining space, ext4 formatted, optionally LUKS encrypted)
#                Format: mkfs.ext4 (via format type=ext4)
#                Mounted to: $TMP_DIR/gpg_storage (typically /tmp/gentoo-install/gpg_storage)
#                Purpose: Stores the GPG-encrypted LUKS keyfile for unlocking /dev/sdROOT2
#                Access: Full read/write access while mounted - you can store any files here
# 
# /dev/sdROOT1 - Swap partition (8GiB, swap formatted)
#                Format: mkswap (via format type=swap)
#                No mount point (activated with swapon)
# 
# /dev/sdROOT2 - Root partition (remaining space, LUKS encrypted with GPG keyfile, btrfs formatted)
#                Format: mkfs.btrfs (via format type=btrfs)
#                Mounted to: $ROOT_MOUNTPOINT (typically /tmp/gentoo-install/root)
#                Purpose: Root filesystem for Gentoo installation
#                Encryption: The LUKS encryption key is read from the GPG keyfile on /dev/sdBOOT2
#
# Mounting workflow:
# 1. mount_gpg_storage() - Mounts BOOT2 (ext4) to $TMP_DIR/gpg_storage for keyfile access
# 2. read_gpg_keyfile() - Decrypts and reads the LUKS key from the mounted partition
# 3. The key is used to unlock ROOT2 (LUKS encrypted)
# 4. mount_root() - Mounts the unlocked ROOT2 (btrfs) to $ROOT_MOUNTPOINT
# 5. mount_efi_partition() - Mounts BOOT1 (vfat) to $ROOT_MOUNTPOINT/boot for bootloader installation
