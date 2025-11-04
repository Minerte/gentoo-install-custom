# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1

function preprocess_config() {
	disk_configuration # in gentoo.conf

	check_config
}

function check_config() {
	[[ $KEYMAP =~ ^[0-9A-Za-z-]*$ ]] \
		|| die "KEYMAP contains invalid characters"

	if [[ "$STAGE3_BASENAME" != *systemd* ]]; then
		[[ "$STAGE3_BASENAME" != *systemd* ]] \
			|| die "Using OpenRC requires a non-systemd stage3 archive!"
	else
			die "Failed"
	fi

	# Check hostname per RFC1123
	local hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
	[[ $HOSTNAME =~ $hostname_regex ]] \
		|| die "'$HOSTNAME' is not a valid hostname"

	[[ -v "DISK_ID_ROOT" && -n $DISK_ID_ROOT ]] \
		|| die "You must assign DISK_ID_ROOT"
	[[ -v "DISK_ID_EFI" && -n $DISK_ID_EFI ]] \
		|| die "You must assign DISK_ID_EFI"

	[[ -v "DISK_ID_EFI" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_EFI]" ]] \
		&& die "Missing uuid for DISK_ID_EFI, have you made sure it is used?"
	[[ -v "DISK_ID_SWAP" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_SWAP]" ]] \
		&& die "Missing uuid for DISK_ID_SWAP, have you made sure it is used?"
	[[ -v "DISK_ID_ROOT" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_ROOT]" ]] \
		&& die "Missing uuid for DISK_ID_ROOT, have you made sure it is used?"

	if [[ -v "DISK_ID_EFI" ]]; then
		IS_EFI=true # Taken from main
	else
		die
	fi
}

function gentoo_umount() {
	if mountpoint -q -- "$ROOT_MOUNTPOINT"; then
		einfo "Unmounting root filesystem"
		umount -R -l "$ROOT_MOUNTPOINT" \
			|| die "Could not unmount filesystems"
	fi
}

function prepare_installation_environment() {
	einfo "Preparing installation environment"

	local wanted_programs=(
		gpg
		hwclock
		lsblk
		ntpd
		partprobe
		python3
		"?rhash"
		sha512sum
		sgdisk
		uuidgen
		wget
	)

	# Check for existence of required programs
	check_wanted_programs "${wanted_programs[@]}" # Function from utils.sh

	# Sync time now to prevent issues later
	sync_time # funtion is in same functions.sh file
}

function sync_time() {
	einfo "Syncing time"
	if command -v ntpd &> /dev/null; then
		try ntpd -g -q
	elif command -v chrony &> /dev/null; then
		# See https://github.com/oddlama/gentoo-install/pull/122
		try chronyd -q
	else
		# why am I doing this?
		try date -s "$(curl -sI http://example.com | grep -i ^date: | cut -d' ' -f3-)"
	fi

	einfo "Current date: $(LANG=C date)"
	einfo "Writing time to hardware clock"
	hwclock --systohc --utc \
		|| die "Could not save time to hardware clock"
}


function apply_disk_configuration() {
	summarize_disk_actions # fucntion in same file

	if [[ $NO_PARTITIONING_OR_FORMATTING == true ]]; then
		elog "You have chosen an existing disk configuration. No devices will"
		elog "actually be re-partitioned or formatted. Please make sure that all"
		elog "devices are already formatted."
	else
		ewarn "Please ensure that all selected devices are fully unmounted and are"
		ewarn "not otherwise in use by the system. This includes stopping mdadm arrays"
		ewarn "and closing opened luks volumes if applicable for all relevant devices."
		ewarn "Otherwise, automatic partitioning may fail."
	fi
	ask "Do you really want to apply this disk configuration?" \
		|| die "Aborted"
	countdown "Applying in " 5

	einfo "Applying disk configuration"
	apply_disk_actions # fucntion in same file

	einfo "Disk configuration was applied successfully"
	elog "[1mNew lsblk output:[m"
	for_line_in <(lsblk \
		|| die "Error in lsblk") elog
}

function summarize_disk_actions() {
	elog "[1mCurrent lsblk output:[m"
	for_line_in <(lsblk \
		|| die "Error in lsblk") elog

	local disk_action_summarize_only=true
	declare -A summary_tree
	declare -A summary_name
	declare -A summary_hint
	declare -A summary_ptr
	declare -A summary_desc
	declare -A summary_depth_continues
	apply_disk_actions # fucntion in same file

	local depth=-1
	elog
	elog "[1mConfigured disk layout:[m"
	elog ────────────────────────────────────────────────────────────────────────────────
	elog "$(printf '%-26s %-28s %s' NODE ID OPTIONS)"
	elog ────────────────────────────────────────────────────────────────────────────────
	print_summary_tree __root__
	elog ────────────────────────────────────────────────────────────────────────────────
}

function print_summary_tree() {
	local root="$1"
	local depth="$((depth + 1))"
	local has_children=false

	if [[ -v "summary_tree[$root]" ]]; then
		local children="${summary_tree[$root]}"
		has_children=true
		summary_depth_continues[$depth]=true
	else
		summary_depth_continues[$depth]=false
	fi

	if [[ $root != __root__ ]]; then
		print_summary_tree_entry "$root"
	fi

	if [[ $has_children == "true" ]]; then
		local count
		count="$(tr ';' '\n' <<< "$children" | grep -c '\S')" \
			|| count=0
		local idx=0
		# Splitting is intentional here
		# shellcheck disable=SC2086
		for id in ${children//';'/ }; do
			idx="$((idx + 1))"
			[[ $idx == "$count" ]] \
				&& summary_depth_continues[$depth]=false
			print_summary_tree "$id"
			# separate blocks by newline
			[[ ${summary_depth_continues[0]} == "true" ]] && [[ $depth == 1 ]] && [[ $idx == "$count" ]] \
				&& elog
		done
	fi
}

function print_summary_tree_entry() {
	local indent_chars=""
	local indent="0"
	local d="1"
	local maxd="$((depth - 1))"
	while [[ $d -lt $maxd ]]; do
		if [[ ${summary_depth_continues[$d]} == "true" ]]; then
			indent_chars+='│ '
		else
			indent_chars+='  '
		fi
		indent=$((indent + 2))
		d="$((d + 1))"
	done
	if [[ $maxd -gt 0 ]]; then
		if [[ ${summary_depth_continues[$maxd]} == "true" ]]; then
			indent_chars+='├─'
		else
			indent_chars+='└─'
		fi
		indent=$((indent + 2))
	fi

	local name="${summary_name[$root]}"
	local hint="${summary_hint[$root]}"
	local desc="${summary_desc[$root]}"
	local ptr="${summary_ptr[$root]}"
	local id_name="[2m[m"
	if [[ $root != __* ]]; then
		if [[ $root == _* ]]; then
			id_name="[2m${root:1}[m"
		else
			id_name="[2m${root}[m"
		fi
	fi

	local align=0
	if [[ $indent -lt 33 ]]; then
		align="$((33 - indent))"
	fi

	elog "$indent_chars$(printf "%-${align}s %-47s %s" \
		"$name [2m$hint[m" \
		"$id_name $ptr" \
		"$desc")"
}

function apply_disk_actions() {
	local param
	local current_params=()
	for param in "${DISK_ACTIONS[@]}"; do
		if [[ $param == ';' ]]; then
			apply_disk_action "${current_params[@]}" # fucntion in same file
			current_params=()
		else
			current_params+=("$param")
		fi
	done
}

function apply_disk_action() {
	unset known_arguments
	unset arguments; declare -A arguments; parse_arguments "$@"
	case "${arguments[action]}" in
		'existing')          disk_existing         						;;
		'create_gpt')        disk_create_gpt       						;;
		'create_partition')  disk_create_partition 						;;
		'create_luks')		 disk_create_luks_with_gpg					;;
		'create_luks_passphrase')    disk_create_luks_with_passphrase	;;
		'create_dummy')      disk_create_dummy     						;;
		'format')            disk_format           						;;
		'format_btrfs')      disk_format_btrfs     						;;
		*) echo "Ignoring invalid action: ${arguments[action]}" ;;
	esac
}

function add_summary_entry() {
	local parent="$1"
	local id="$2"
	local name="$3"
	local hint="$4"
	local desc="$5"

	local ptr
	case "$id" in
		"${DISK_ID_BIOS-__unused__}")  ptr="[1;32m← bios[m" ;;
		"${DISK_ID_EFI-__unused__}")   ptr="[1;32m← efi[m"  ;;
		"${DISK_ID_SWAP-__unused__}")  ptr="[1;34m← swap[m" ;;
		"${DISK_ID_ROOT-__unused__}")  ptr="[1;33m← root[m" ;;
		# \x1f characters compensate for printf byte count and unicode character count mismatch due to '←'
		*)                             ptr="[1;32m[m$(echo -e "\x1f\x1f")" ;;
	esac

	summary_tree[$parent]+=";$id"
	summary_name[$id]="$name"
	summary_hint[$id]="$hint"
	summary_ptr[$id]="$ptr"
	summary_desc[$id]="$desc"
}

function summary_color_args() {
	for arg in "$@"; do
		if [[ -v "arguments[$arg]" ]]; then
			printf '%-28s ' "[1;34m$arg[2m=[m${arguments[$arg]}"
		fi
	done
}

function disk_existing() {
	local new_id="${arguments[new_id]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		add_summary_entry __root__ "$new_id" "${arguments[device]}" "(no-format, existing)" "" # funtions from same file
	fi
	# no-op;
}

function disk_create_gpt() {
	local new_id="${arguments[new_id]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		if [[ -v arguments[id] ]]; then
			add_summary_entry "${arguments[id]}" "$new_id" "gpt" "" ""  # funtions in same file
		else
			add_summary_entry __root__ "$new_id" "${arguments[device]}" "(gpt)" ""  # funtions in same file
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

	local ptuuid="${DISK_ID_TO_UUID[$new_id]}"

	einfo "Creating new gpt partition table ($new_id) on $device_desc"
	wipefs --quiet --all --force "$device" \
		|| die "Could not erase previous file system signatures from '$device'" # OS app
	sgdisk -Z -U "$ptuuid" "$device" >/dev/null \
		|| die "Could not create new gpt partition table ($new_id) on '$device'" # OS app
	partprobe "$device" # OS app
}

function disk_create_partition() {
	local new_id="${arguments[new_id]}"
	local id="${arguments[id]}"
	local size="${arguments[size]}"
	local type="${arguments[type]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		add_summary_entry "$id" "$new_id" "part" "($type)" "$(summary_color_args size)" # Funtion in same file
		return 0
	fi

	if [[ $size == "remaining" ]]; then
		arg_size=0
	else
		arg_size="+$size"
	fi

	local device
	device="$(resolve_device_by_id "$id")" \
		|| die "Could not resolve device with id=$id" # Funtion from  utils.sh 
	local partuuid="${DISK_ID_TO_UUID[$new_id]}"
	local extra_args=""
	case "$type" in
		'efi')   type='ef00' ;;
		'swap')  type='8200' ;;
		'luks')  type='8309' ;;
		'linux') type='8300' ;;
		*) ;;
	esac

	einfo "Creating partition ($new_id) with type=$type, size=$size on $device"
	# shellcheck disable=SC2086
	sgdisk -n "0:0:$arg_size" -t "0:$type" -u "0:$partuuid" $extra_args "$device" >/dev/null \
		|| die "Could not create new gpt partition ($new_id) on '$device' ($id)"  # OS app
	partprobe "$device" # OS app

	# On some system, we need to wait a bit for the partition to show up.
	local new_device
	new_device="$(resolve_device_by_id "$new_id")" \
		|| die "Could not resolve new device with id=$new_id"
	for i in {1..10}; do
		[[ -e "$new_device" ]] && break
		[[ "$i" -eq 1 ]] && printf "Waiting for partition (%s) to appear..." "$new_device"
		printf " %s" "$((10 - i + 1))"
		sleep 1
		[[ "$i" -eq 10 ]] && echo
	done
}

function disk_create_luks_with_passphrase() {
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
		# Wait for device to appear (fixes the blkid error)
		device="$(resolve_device_by_id "${arguments[id]}")"
		device_desc="$device ($new_id)"
		
		# Wait for device to actually exist
		for i in {1..10}; do
			[[ -e "$device" ]] && break
			[[ "$i" -eq 1 ]] && printf "Waiting for device (%s) to appear..." "$device"
			printf " %s" "$((10 - i + 1))"
			sleep 1
			[[ "$i" -eq 10 ]] && echo
		done
		
		[[ -e "$device" ]] \
			|| die "Device $device does not exist after waiting"
	else
		device="${arguments[device]}"
		device_desc="$device"
	fi

	local uuid="${DISK_ID_TO_UUID[$new_id]}"

	einfo "Creating LUKS ($new_id) on $device_desc with passphrase"
	einfo "You will be prompted to enter a passphrase for '$name'"

	# Create LUKS partition with passphrase (no keyfile, no GPG)
	# User will be prompted to enter passphrase interactively
	cryptsetup luksFormat \
			--type luks2 \
			--uuid "$uuid" \
			--cipher aes-xts-plain64 \
			--key-size 512 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			"$device" \
		|| die "Could not create LUKS on $device_desc"
	
	# Backup LUKS header
	mkdir -p "$LUKS_HEADER_BACKUP_DIR" \
		|| die "Could not create LUKS header backup dir '$LUKS_HEADER_BACKUP_DIR'"
	
	local header_file="$LUKS_HEADER_BACKUP_DIR/luks-header-${new_id}-${uuid,,}.img"
	[[ ! -e $header_file ]] \
		|| rm "$header_file" \
		|| die "Could not remove old LUKS header backup file '$header_file'"
	
	cryptsetup luksHeaderBackup "$device" \
			--header-backup-file "$header_file" \
		|| die "Could not backup LUKS header on $device_desc"
	
	# Open the LUKS device with passphrase
	einfo "Now opening the encrypted device '$name'"
	cryptsetup open --type luks2 \
			"$device" "$name" \
		|| die "Could not open LUKS encrypted device $device_desc"
	
	einfo "LUKS device $name created and opened successfully"
}

function disk_create_luks_with_gpg() {
	export GPG_TTY=$(tty)
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
		device_desc="$device ($new_id)"
	else
		device="${arguments[device]}"
		device_desc="$device"
	fi

	local uuid="${DISK_ID_TO_UUID[$new_id]}"

	einfo "Creating luks ($new_id) on $device_desc using GPG keyfile"

	# Create keys directory if it doesn't exist
	mkdir -p /mnt/keys \
		|| die "Could not create keys directory"

	# Generate a unique keyfile name based on the mapper name
	local keyfile="/mnt/keys/${name}_key.luks.gpg"

	# Generate random key and encrypt it with GPG
	# Using 8MB (8388608 bytes) of random data for strong key
	dd bs=8388608 count=1 if=/dev/urandom \
		| gpg --symmetric --cipher-algo AES256 --output "$keyfile" \
		|| die "Could not generate GPG encrypted keyfile"
	
	einfo "Generated GPG encrypted keyfile: $keyfile"

	# Use the GPG keyfile to format LUKS partition
	# Pipe decrypted key directly to cryptsetup (never stored unencrypted on disk)
	gpg --batch --yes --decrypt "$keyfile" \
		| cryptsetup luksFormat \
			--type luks2 \
			--uuid "$uuid" \
			--key-file=- \
			--cipher aes-xts-plain64 \
			--key-size 512 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			--batch-mode \
			"$device" \
		|| die "Could not create luks on $device_desc"
	
	mkdir -p "$LUKS_HEADER_BACKUP_DIR" \
		|| die "Could not create luks header backup dir '$LUKS_HEADER_BACKUP_DIR'"
	
	local header_file="$LUKS_HEADER_BACKUP_DIR/luks-header-${new_id}-${uuid,,}.img"
	[[ ! -e $header_file ]] \
		|| rm "$header_file" \
		|| die "Could not remove old luks header backup file '$header_file'"
	
	cryptsetup luksHeaderBackup "$device" \
			--header-backup-file "$header_file" \
		|| die "Could not backup luks header on $device_desc"

	# Open the LUKS device using the GPG keyfile
	gpg --batch --yes --decrypt "$keyfile" \
		| cryptsetup open --type luks2 \
			"$device" "$name" \
			--key-file=- \
		|| die "Could not open luks encrypted device $device_desc"

	einfo "LUKS device $name created and opened successfully"
}

function disk_create_dummy() {
	local new_id="${arguments[new_id]}"
	local device="${arguments[device]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		add_summary_entry __root__ "$new_id" "$device" "" ""  # funtion in same file
		return 0
	fi
}

function disk_format() {
	local id="${arguments[id]}"
	local type="${arguments[type]}"
	local label="${arguments[label]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		add_summary_entry "${arguments[id]}" "__fs__${arguments[id]}" "${arguments[type]}" "(fs)" "$(summary_color_args label)"
		return 0
	fi

	local device
	device="$(resolve_device_by_id "$id")" \
		|| die "Could not resolve device with id=$id"

	einfo "Formatting $device ($id) with $type"
	wipefs --quiet --all --force "$device" \
		|| die "Could not erase previous file system signatures from '$device' ($id)"

	case "$type" in
		'bios'|'efi')
			if [[ -v "arguments[label]" ]]; then
				mkfs.fat -F 32 -n "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkfs.fat -F 32 "$device" \
					|| die "Could not format device '$device' ($id)"
			fi
			;;
		'swap')
			if [[ -v "arguments[label]" ]]; then
				mkswap -L "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkswap "$device" \
					|| die "Could not format device '$device' ($id)"
			fi

			# Try to swapoff in case the system enabled swap automatically
			swapoff "$device" &>/dev/null
			;;
		'ext4')
			if [[ -v "arguments[label]" ]]; then
				mkfs.ext4 -q -L "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkfs.ext4 -q "$device" \
					|| die "Could not format device '$device' ($id)"
			fi
			;;
		'btrfs')
			if [[ -v "arguments[label]" ]]; then
				mkfs.btrfs -q -L "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkfs.btrfs -q "$device" \
					|| die "Could not format device '$device' ($id)"
			fi

			init_btrfs "$device" "'$device' ($id)" # function in same file
			;;
		*) die "Unknown filesystem type" ;;
	esac
}

function disk_format_btrfs() {
	local ids="${arguments[ids]}"
	local label="${arguments[label]}"
	local raid_type="${arguments[raid_type]}"
	if [[ ${disk_action_summarize_only-false} == "true" ]]; then
		local id
		# Splitting is intentional here
		# shellcheck disable=SC2086
		for id in ${ids//';'/ }; do
			add_summary_entry "$id" "__fs__$id" "btrfs" "(fs)" "$(summary_color_args label)"
		done
		return 0
	fi

	local devices_desc=""
	local devices=()
	local id
	local dev
	# Splitting is intentional here
	# shellcheck disable=SC2086
	for id in ${ids//';'/ }; do
		dev="$(resolve_device_by_id "$id")" \
			|| die "Could not resolve device with id=$id"
		devices+=("$dev")
		devices_desc+="$dev ($id), "
	done
	devices_desc="${devices_desc:0:-2}"

	wipefs --quiet --all --force "${devices[@]}" \
		|| die "Could not erase previous file system signatures from $devices_desc"

	# Collect extra arguments
	extra_args=()
	if [[ "${#devices}" -gt 1 ]] && [[ -v "arguments[raid_type]" ]]; then
		extra_args+=("-d" "$raid_type")
	fi

	if [[ -v "arguments[label]" ]]; then
		extra_args+=("-L" "$label")
	fi

	einfo "Creating btrfs on $devices_desc"
	mkfs.btrfs -q "${extra_args[@]}" "${devices[@]}" \
		|| die "Could not create btrfs on $devices_desc"

	init_btrfs "${devices[0]}" "btrfs array ($devices_desc)" # function in same file
}

function init_btrfs() {
	local device="$1"
	local desc="$2"
	mkdir -p /btrfs \
		|| die "Could not create /btrfs directory"
	mount "$device" /btrfs \
		|| die "Could not mount $desc to /btrfs"
	btrfs subvolume create /btrfs/root \
		|| die "Could not create btrfs subvolume /root on $desc"
	btrfs subvolume set-default /btrfs/root \
		|| die "Could not set default btrfs subvolume to /root on $desc"
	umount /btrfs \
		|| die "Could not unmount btrfs on $desc"
}

function download_stage3() {
	cd "$TMP_DIR" \
		|| die "Could not cd into '$TMP_DIR'"

	local STAGE3_BASENAME_FINAL
	if [[ ("$GENTOO_ARCH" == "amd64" && "$STAGE3_VARIANT" == *x32*) || ("$GENTOO_ARCH" == "x86" && -n "$GENTOO_SUBARCH") ]]; then
		STAGE3_BASENAME_FINAL="$STAGE3_BASENAME_CUSTOM"
	else
		STAGE3_BASENAME_FINAL="$STAGE3_BASENAME"
	fi

	local STAGE3_RELEASES="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/current-$STAGE3_BASENAME_FINAL/"

	# Download upstream list of files
	CURRENT_STAGE3="$(download_stdout "$STAGE3_RELEASES")" \
		|| die "Could not retrieve list of tarballs"
	# Decode urlencoded strings
	CURRENT_STAGE3=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))' <<< "$CURRENT_STAGE3")
	# Parse output for correct filename
	CURRENT_STAGE3="$(grep -o "\"${STAGE3_BASENAME_FINAL}-[0-9A-Z]*.tar.xz\"" <<< "$CURRENT_STAGE3" \
		| sort -u | head -1)" \
		|| die "Could not parse list of tarballs"
	# Strip quotes
	CURRENT_STAGE3="${CURRENT_STAGE3:1:-1}"
	# File to indiciate successful verification
	CURRENT_STAGE3_VERIFIED="${CURRENT_STAGE3}.verified"

	# Download file if not already downloaded
	if [[ -e $CURRENT_STAGE3_VERIFIED ]]; then
		einfo "$STAGE3_BASENAME_FINAL tarball already downloaded and verified"
	else
		einfo "Downloading $STAGE3_BASENAME_FINAL tarball"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}" "${CURRENT_STAGE3}"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}.DIGESTS" "${CURRENT_STAGE3}.DIGESTS"

		# Import gentoo keys
		einfo "Importing gentoo gpg key"
		local GENTOO_GPG_KEY="$TMP_DIR/gentoo-keys.gpg"
		download "https://gentoo.org/.well-known/openpgpkey/hu/wtktzo4gyuhzu8a4z5fdj3fgmr1u6tob?l=releng" "$GENTOO_GPG_KEY" \
			|| die "Could not retrieve gentoo gpg key"
		gpg --quiet --import < "$GENTOO_GPG_KEY" \
			|| die "Could not import gentoo gpg key"

		# Verify DIGESTS signature
		einfo "Verifying tarball signature"
		gpg --quiet --verify "${CURRENT_STAGE3}.DIGESTS" \
			|| die "Signature of '${CURRENT_STAGE3}.DIGESTS' invalid!"

		# Check hashes
		einfo "Verifying tarball integrity"
		# Replace any absolute paths in the digest file with just the stage3 basename, so it will be found by rhash
		digest_line=$(grep 'tar.xz$' "${CURRENT_STAGE3}.DIGESTS" | sed -e 's/  .*stage3-/  stage3-/')
		if type rhash &>/dev/null; then
			rhash -P --check <(echo "# SHA512"; echo "$digest_line") \
				|| die "Checksum mismatch!"
		else
			sha512sum --check <<< "$digest_line" \
				|| die "Checksum mismatch!"
		fi

		# Create verification file in case the script is restarted
		touch_or_die 0644 "$CURRENT_STAGE3_VERIFIED"
	fi
}

function touch_or_die() {
	touch "$2" \
		|| die "Could not touch '$2'"
	chmod "$1" "$2"
}

function mkdir_or_die() {
	# shellcheck disable=SC2174
	mkdir -m "$1" -p "$2" \
		|| die "Could not create directory '$2'"
}

function extract_stage3() {
	mount_root # in same file

	[[ -n $CURRENT_STAGE3 ]] \
		|| die "CURRENT_STAGE3 is not set"
	[[ -e "$TMP_DIR/$CURRENT_STAGE3" ]] \
		|| die "stage3 file does not exist"

	# Go to root directory
	cd "$ROOT_MOUNTPOINT" \
		|| die "Could not move to '$ROOT_MOUNTPOINT'"
	# Ensure the directory is empty
	find . -mindepth 1 -maxdepth 1 -not -name 'lost+found' \
		| grep -q . \
		&& die "root directory '$ROOT_MOUNTPOINT' is not empty"

	# Extract tarball
	einfo "Extracting stage3 tarball"
	tar xpf "$TMP_DIR/$CURRENT_STAGE3" --xattrs --numeric-owner \
		|| die "Error while extracting tarball"
	cd "$TMP_DIR" \
		|| die "Could not cd into '$TMP_DIR'"
}

function mount_root() {
	if ! mountpoint -q -- "$ROOT_MOUNTPOINT"; then
		mount_by_id "$DISK_ID_ROOT" "$ROOT_MOUNTPOINT"
	fi
}

function mount_efivars() {
	# Skip if already mounted
	mountpoint -q -- "/sys/firmware/efi/efivars" \
		&& return

	# Mount efivars
	einfo "Mounting efivars"
	mount -t efivarfs efivarfs "/sys/firmware/efi/efivars" \
		|| die "Could not mount efivarfs"
}

function mount_by_id() {
	local dev
	local id="$1"
	local mountpoint="$2"

	# Skip if already mounted
	mountpoint -q -- "$mountpoint" \
		&& return

	# Mount device
	einfo "Mounting device with id=$id to '$mountpoint'"
	mkdir -p "$mountpoint" \
		|| die "Could not create mountpoint directory '$mountpoint'"
	dev="$(resolve_device_by_id "$id")" \
		|| die "Could not resolve device with id=$id"
	mount "$dev" "$mountpoint" \
		|| die "Could not mount device '$dev'"
}

function gentoo_chroot() {
	if [[ $# -eq 1 ]]; then
		einfo "To later unmount all virtual filesystems, simply use umount -l ${1@Q}"
		gentoo_chroot "$1" /bin/bash --init-file <(echo 'init_bash')
	fi

	[[ ${EXECUTED_IN_CHROOT-false} == "false" ]] \
		|| die "Already in chroot"

	local chroot_dir="$1"
	shift

	# Bind repo directory to tmp
	bind_repo_dir # same file

	# Copy resolv.conf
	einfo "Preparing chroot environment"
	install --mode=0644 /etc/resolv.conf "$chroot_dir/etc/resolv.conf" \
		|| die "Could not copy resolv.conf"

	# Mount virtual filesystems
	einfo "Mounting virtual filesystems"
	(
		mountpoint -q -- "$chroot_dir/proc" || mount -t proc /proc "$chroot_dir/proc" || exit 1
		mountpoint -q -- "$chroot_dir/run"  || {
			mount --rbind /run  "$chroot_dir/run" &&
			mount --make-rslave "$chroot_dir/run"; } || exit 1
		mountpoint -q -- "$chroot_dir/tmp"  || {
			mount --rbind /tmp  "$chroot_dir/tmp" &&
			mount --make-rslave "$chroot_dir/tmp"; } || exit 1
		mountpoint -q -- "$chroot_dir/sys"  || {
			mount --rbind /sys  "$chroot_dir/sys" &&
			mount --make-rslave "$chroot_dir/sys"; } || exit 1
		mountpoint -q -- "$chroot_dir/dev"  || {
			mount --rbind /dev  "$chroot_dir/dev" &&
			mount --make-rslave "$chroot_dir/dev"; } || exit 1
	) || die "Could not mount virtual filesystems"

	# Cache lsblk output, because it doesn't work correctly in chroot (returns almost no info for devices, e.g. empty uuids)
	cache_lsblk_output # from utils.sh

	# Execute command
	einfo "Chrooting..."
	EXECUTED_IN_CHROOT=true \
		TMP_DIR="$TMP_DIR" \
		CACHED_LSBLK_OUTPUT="$CACHED_LSBLK_OUTPUT" \
		exec chroot -- "$chroot_dir" "$GENTOO_INSTALL_REPO_DIR/scripts/dispatch_chroot.sh" "$@" \
			|| die "Failed to chroot into '$chroot_dir'."
}

function bind_repo_dir() {
	# Use new location by default
	export GENTOO_INSTALL_REPO_DIR="$GENTOO_INSTALL_REPO_BIND"

	# Bind the repo dir to a location in /tmp,
	# so it can be accessed from within the chroot
	mountpoint -q -- "$GENTOO_INSTALL_REPO_BIND" \
		&& return

	# Mount root device
	einfo "Bind mounting repo directory"
	mkdir -p "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not create mountpoint directory '$GENTOO_INSTALL_REPO_BIND'"
	mount --bind "$GENTOO_INSTALL_REPO_DIR_ORIGINAL" "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not bind mount '$GENTOO_INSTALL_REPO_DIR_ORIGINAL' to '$GENTOO_INSTALL_REPO_BIND'"
}

################################################
# Functions in chroot

function env_update() {
	env-update \
		|| die "Error in env-update"
	source /etc/profile \
		|| die "Could not source /etc/profile"
	umask 0077
}	

function enable_service() {
		try rc-update add "$1" default
}