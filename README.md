# About
This project is inspired by [oddlama](https://github.com/oddlama/gentoo-install) but differs in several important ways.
## Key differences from the orginal project
- **Openrc support only**
- **Seperated boot drive**
- **Support only EFI system**
- **Encryption using GPG-keyfile only**
- **File system:**
    - btrfs for root
    - vfat for boot 
    - ext4 for boot extended
- **Btrfs subvolumes:**
    - `root`,`home`,`etc`,`var`,`log`,`tmp`

- No interactive GUI configuration — everything is defined in `gentoo.conf`
- Uses gentoo-sources; the user may choose between **make defconfig** or **manual menuconfig**.
- Contribution documentation for required kernel modules is provided in `contrib/kernel_modules.md`.

# Usage
First boot into a live cd from [Arch linux](https://archlinux.org/download/) or [Endeavor os](https://endeavouros.com/) (only this Live cd have been tested):

```
pacman -Sy git # (Archlinux) Install git in live environment
git clone "https://github.com/Minerte/gentoo-install-custom"
cd gentoo-install-custom
```

Edit the gentoo.conf file

- set X from create_boot_storage_disk_layout type=efi /dev/sdX to a USB drive.
- set X from create_gpg_disk_layout swap=8GiB luks=true root_fs=btrfs /dev/sdX to main disk where root will be.
- (Optional) swap size is set at 8Gib by default but it can be change.
- (Optional) an alternative stage3 tarball (default is `hardened-selinux-openrc`).

**And then begin installtion with:**

```
./install
```

**Kernel config** \
During installation, the script will prompt you to select a kernel version.
Afterward, it will ask whether you want to run make defconfig:

- Yes — starts from the kernel defaults, but you must still enable several required modules (see contrib/kernel_modules.md).
- No — menuconfig opens with no preconfiguration.

**Finish** \
After the installation completes, you may chroot into the new system to perform any additional configuration.
