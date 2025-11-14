## Core device mapper and encryption
CONFIG_BLK_DEV_DM=y                    # Device mapper support (required)
CONFIG_DM_CRYPT=y                      # LUKS/dm-crypt encryption (required)
CONFIG_DM_SNAPSHOT=m                   # Snapshot support (useful for LVM)

## cryptographic algorithms
# AES Encryption (essential for LUKS)
CONFIG_CRYPTO_AES=y                    # AES cipher algorithm
CONFIG_CRYPTO_AES_X86_64=y             # x86_64 AES implementation
### For INTEL, use:
### CONFIG_CRYPTO_AES_NI_INTEL=y          # Intel AES-NI acceleration (if Intel CPU)
### For AMD, use:
### CONFIG_CRYPTO_DEV_CCP=y              # AMD Cryptographic Coprocessor

### XTS Mode (standard for LUKS)
CONFIG_CRYPTO_XTS=y                    # XTS cipher mode (required)

### Hashing Algorithms
CONFIG_CRYPTO_SHA256=y                 # SHA-256 (common for LUKS)
CONFIG_CRYPTO_SHA512=y                 # SHA-512 (alternative)
CONFIG_CRYPTO_SHA1=y                   # SHA-1 (older LUKS volumes)

### User-space Crypto API (required for cryptsetup)
CONFIG_CRYPTO_USER_API=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_CRYPTO_USER_API_RNG=y

## File systems support
### Your root filesystem (you mentioned btrfs)
CONFIG_BTRFS_FS=y                      # Btrfs filesystem

### EFI/Boot partition
CONFIG_VFAT_FS=y                       # FAT/VFAT for EFI partition
CONFIG_FAT_FS=y                        # FAT support

### GPG storage partition (you mentioned ext4)
CONFIG_EXT4_FS=y                       # ext4 filesystem

### Swap support
CONFIG_SWAP=y                          # Swap support

## USB support
CONFIG_USB_SUPPORT=y                   # USB support
CONFIG_USB=y                           # USB host controller
CONFIG_USB_XHCI_HCD=y                  # USB 3.0 support
CONFIG_USB_EHCI_HCD=y                  # USB 2.0 support
CONFIG_USB_OHCI_HCD=y                  # USB 1.1 support
CONFIG_USB_STORAGE=y                   # USB mass storage
CONFIG_USB_UAS=y                       # USB Attached SCSI (modern USB drives)

## Storage controllers
CONFIG_SCSI=y                          # SCSI support
CONFIG_BLK_DEV_SD=y                    # SCSI disk support (for SATA/SAS/USB)
CONFIG_SCSI_MOD=y                      # SCSI module support
CONFIG_ATA=y                           # ATA/SATA support
CONFIG_SATA_AHCI=y                     # AHCI SATA support (most modern systems)

### NVMe (if you have NVMe drives)
CONFIG_BLK_DEV_NVME=y                  # NVMe support

## GPG/Console support 
CONFIG_VT=y                            # Virtual terminal
CONFIG_VT_CONSOLE=y                    # VT console
CONFIG_HW_CONSOLE=y                    # Hardware console
CONFIG_UNIX98_PTYS=y                   # Unix98 PTY support
CONFIG_DEVTMPFS=y                      # /dev tmpfs
CONFIG_DEVTMPFS_MOUNT=y                # Auto-mount /dev

## Keyboard support 
CONFIG_INPUT=y                         # Input device support
CONFIG_INPUT_KEYBOARD=y                # Keyboard support
CONFIG_KEYBOARD_ATKBD=y                # AT/PS2 keyboard
CONFIG_USB_HID=y                       # USB HID support
CONFIG_HID=y                           # HID support
CONFIG_HID_GENERIC=y                   # Generic HID driver