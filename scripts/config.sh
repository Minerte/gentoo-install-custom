# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1


################################################
# Script internal configuration

# The temporary directory for this script,
# must reside in /tmp to allow the chrooted system to access the files
TMP_DIR="/tmp/gentoo-install"
# Mountpoint for the new system
ROOT_MOUNTPOINT="$TMP_DIR/root" # Varible from con TMP_DIR and uses over main.sh and functions.sh
# Mountpoint for the script files for access from chroot
GENTOO_INSTALL_REPO_BIND="$TMP_DIR/bind" #Varible uses over main.sh and functions.sh
# Mountpoint for the script files for access from chroot
UUID_STORAGE_DIR="$TMP_DIR/uuids"
# Backup dir for luks headers
LUKS_HEADER_BACKUP_DIR="$TMP_DIR/luks-headers"

# Flag to track usage of luks (needed to check for cryptsetup existence)
USED_LUKS=false
# Flag to track usage of btrfs
USED_BTRFS=false
# Flag to track usage of encryption
USED_ENCRYPTION=false
# Flag to track whether partitioning or formatting is forbidden
NO_PARTITIONING_OR_FORMATTING=false

# An array of disk related actions to perform
DISK_ACTIONS=()
# An associative array from disk id to a resolvable string
declare -gA DISK_ID_TO_RESOLVABLE
# An associative array from disk id to parent gpt disk id (only for partitions)
declare -gA DISK_ID_PART_TO_GPT_ID
# An associative array from luks id to underlying partition id
declare -gA DISK_ID_LUKS_TO_UNDERLYING_ID
# An associative array to check for existing ids (maps to uuids)
declare -gA DISK_ID_TO_UUID
# An associative set to check for correct usage of size=remaining in gpt tables
declare -gA DISK_GPT_HAD_SIZE_REMAINING

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
	# IMPORTANT: Uses passphrase-based LUKS (not GPG keyfile) to avoid circular dependency
	local gpg_storage_id="part_gpg_storage"
	if [[ "$use_luks" == "true" ]]; then
		create_luks_passphrase new_id=part_luks_gpg_storage name="gpg_storage" id=part_gpg_storage
		gpg_storage_id="part_luks_gpg_storage"
	fi

	# Format the partitions
	format id=part_efi type=efi label=efi
	format id="$gpg_storage_id" type=ext4 label=gpg_storage

	# Set global variables for the installation
	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_efi"
	else
		die "Cant find efi id"
	fi
	DISK_ID_GPG_STORAGE="$gpg_storage_id"
}

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
	local swap_id="part_swap"
	local root_id="part_root"

	if [[ "$use_luks" == "true" ]]; then
		# Encrypt SWAP partition with GPG keyfile
		create_luks new_id=part_luks_swap name="cryptswap" id=part_swap
		swap_id="part_luks_swap"

		# Encrypt ROOT partition with GPG keyfile
		create_luks new_id=part_luks_root name="cryptroot" id=part_root
		root_id="part_luks_root"
	fi

	# Format the partitions
	[[ $size_swap != "false" ]] \
		&& format id="$swap_id" type=swap label=swap
	format id="$root_id" type="$root_fs" label=root

	# Set global variables for the installation
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP="$swap_id"
	DISK_ID_ROOT="$root_id"

	# Set filesystem type and mount options
	if [[ $root_fs == "btrfs" ]]; then
		DISK_ID_ROOT_TYPE="btrfs"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/root"
		DISK_ID_HOME_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/home"
		DISK_ID_ETC_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/etc"
		DISK_ID_VAR_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/var"
		DISK_ID_LOG_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/log"
		DISK_ID_TMP_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/tmp"
	else
		die "Unsupported root filesystem type"
	fi
}

function create_gpt() {
	local known_arguments=('+new_id' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id # from same file
	create_new_id new_id # from same file
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	local new_id="${arguments[new_id]}"
	create_resolve_entry "$new_id" ptuuid "${DISK_ID_TO_UUID[$new_id]}" # From utils.sh
	DISK_ACTIONS+=("action=create_gpt" "$@" ";")
}

function only_one_of() {
	local previous=""
	local a
	for a in "$@"; do
		if [[ -v arguments[$a] ]]; then
			if [[ -z $previous ]]; then
				previous="$a"
			else
				die_trace 2 "Only one of the arguments ($*) can be given"
			fi
		fi
	done
}

function create_new_id() {
	local id="${arguments[$1]}"
	[[ $id == *';'* ]] \
		&& die_trace 2 "Identifier contains invalid character ';'"
	[[ ! -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier '$id' already exists"
	DISK_ID_TO_UUID[$id]="$(load_or_generate_uuid "$(base64 -w 0 <<< "$id")")"
}

function verify_existing_id() {
	local id="${arguments[$1]}"
	[[ -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier $1='$id' not found"
}

function verify_option() {
	local opt="$1"
	shift

	local arg="${arguments[$opt]}"
	local i
	for i in "$@"; do
		[[ $i == "$arg" ]] \
			&& return 0
	done

	die_trace 2 "Invalid option $opt='$arg', must be one of ($*)"
}

function create_partition() {
	local known_arguments=('+new_id' '+id' '+size' '+type')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id # From same file
	verify_existing_id id # From same file
	verify_option type bios efi swap raid luks linux # From same file 

	[[ -v "DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]" ]] \
		&& die_trace 1 "Cannot add another partition to table (${arguments[id]}) after size=remaining was used"

	# shellcheck disable=SC2034
	[[ ${arguments[size]} == "remaining" ]] \
		&& DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]=true

	local new_id="${arguments[new_id]}"
	DISK_ID_PART_TO_GPT_ID[$new_id]="${arguments[id]}"
	create_resolve_entry "$new_id" partuuid "${DISK_ID_TO_UUID[$new_id]}" # From utils.sh
	DISK_ACTIONS+=("action=create_partition" "$@" ";")
}

function create_luks() {
	USED_LUKS=true
	USED_ENCRYPTION=true

	local known_arguments=('+new_id' '+name' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id # from same file
	create_new_id new_id # from same file
	[[ -v arguments[id] ]] \
		&& verify_existing_id id # from same file

	local new_id="${arguments[new_id]}"
	local name="${arguments[name]}"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	if [[ -v arguments[id] ]]; then
		DISK_ID_LUKS_TO_UNDERLYING_ID[$new_id]="${arguments[id]}"
	fi
	create_resolve_entry "$new_id" luks "$name" # from Utils.sh
	DISK_ACTIONS+=("action=create_luks" "$@" ";")
}

function create_luks_passphrase() {
	USED_LUKS=true
	USED_ENCRYPTION=true

	local known_arguments=('+new_id' '+name' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id
	create_new_id new_id
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	local new_id="${arguments[new_id]}"
	local name="${arguments[name]}"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	if [[ -v arguments[id] ]]; then
		DISK_ID_LUKS_TO_UNDERLYING_ID[$new_id]="${arguments[id]}"
	fi
	create_resolve_entry "$new_id" luks "$name"
	DISK_ACTIONS+=("action=create_luks_passphrase" "$@" ";")
}

function format() {
	local known_arguments=('+id' '+type' '?label')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	verify_existing_id id  # From same file
	verify_option type bios efi swap ext4 btrfs # from same file 

	local type="${arguments[type]}"
	if [[ "$type" == "btrfs" ]]; then
		USED_BTRFS=true
	fi

	DISK_ACTIONS+=("action=format" "$@" ";")
}