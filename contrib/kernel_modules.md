# Processor type and features
```
Processor type and features  --->
  [*] Symmetric multi-processing support
  [*] EFI runtime service support 
  [*]   EFI stub support
  [*]     EFI mixed-mode support
-*- Enable the block layer --->
  Partition Types --->
    [*] Advanced partition selection
    [*] EFI GUID Partition support
Binary Emulations --->
  [*] IA32 Emulation
General architecture-dependent options  --->
  [*] Provide system calls for 32-bit time_t
```
# Drivers
```
Device Drivers  --->
  Generic Driver Options --->
    <*> Maintain a devtmpfs filesystem             (CONFIG_DEVTMPFS)
    [*]   Automount devtmpfs at /dev               (CONFIG_DEVTMPFS_MOUNT)
  NVME Support --->
    <*> NVM Express block device                   (CONFIG_BLK_DEV_NVME)
    [*] NVMe multipath support
    [*] NVMe hardware monitoring
    <M> NVM Express over Fabrics FC host driver
    <M> NVM Express over Fabrics TCP host driver
    <M> NVMe Target support
    [*]   NVMe Target Passthrough support
    <M>   NVMe loopback device support
    <M>   NVMe over Fabrics FC target driver
    < >     NVMe over Fabrics FC Transport Loopback Test driver (NEW)
    <M>   NVMe over Fabrics TCP target support
  SCSI device support --->
    <*> SCSI device support                        (CONFIG_SCSI)
    <*> SCSI disk support                          (CONFIG_BLK_DEV_SD)
  Serial ATA and Parallel ATA drivers (libata)--->
    <*> ATA ACPI support
    [*] SATA Port Multiplier support
    <*> AHCI SATA support (ahci)
    [*] ATA BMDMA support
    [*] ATA SFF support (for legacy IDE and PATA)
    <*> Intel ESB, ICH, PIIX3, PIIX4 PATA/SATA support (ata_piix)
  Multiple devices driver support (RAID and LVM) --->
    <*> Device mapper support                      (CONFIG_BLK_DEV_DM)
    <*>   Crypt target support                     (CONFIG_DM_CRYPT)
    <M>   Snapshot target                          (CONFIG_DM_SNAPSHOT)
  Graphics support  --->
    Frame buffer Devices  --->
      <*> Support for frame buffer devices  --->
        [*]   EFI-based Framebuffer Support
  HID support --->
    -*- HID bus support
    <*>   Generic HID driver
    [*]   Battery level reporting for HID devices
    USB HID support --->
      <*> USB HID transport layer                    (CONFIG_USB_HID)
  USB support --->
    <*> Support for Host-side USB                  (CONFIG_USB)
    <*>   xHCI HCD (USB 3.0)                       (CONFIG_USB_XHCI_HCD)
    <*>   EHCI HCD (USB 2.0)                       (CONFIG_USB_EHCI_HCD)
    <*>   OHCI HCD (USB 1.1)                       (CONFIG_USB_OHCI_HCD)
    <*>   USB mass storage support                 (CONFIG_USB_STORAGE)
    <*>   USB Attached SCSI                        (CONFIG_USB_UAS)
  <*> Unified support for USB4 and Thunderbolt  --->
```

# Cryptographic algorithms
```
Cryptographic API  --->
  Block ciphers --->
    <*> AES (Advanced Encryption Standard)        (CONFIG_CRYPTO_AES)
  Length-preserving ciphers and modes --->
    <*> XTS (XOR Encrypt XOR with ciphertext stealing)
  Hashes and digests --->
    <*> SHA1                                       (CONFIG_CRYPTO_SHA1)
    <*> SHA256                                     (CONFIG_CRYPTO_SHA256)
    <*> SHA512                                     (CONFIG_CRYPTO_SHA512)
  Hardware crypto devices --->
    <*> AES-NI support for Intel CPUs             (CONFIG_CRYPTO_AES_NI_INTEL) # Intel_CPU only
  Hardware crypto devices --->
    [*] Support for AMD secure Processor
    <M>   Secure Processor device driver
    <*>     Cryptographic Coprocessor device
    <M>       Encryption and hashing offload support
    [*]     Platform Security Processor (PSP) device
    [*]   Enable CCP Internals in DebugFS
```

# File systems support
```
File systems --->
  <*> Second extended fs support
  <*> The Extended 3 (ext3) filesystem
  <*> The Extended 4 (ext4) filesystem
  <*> Btrfs filesystem support
  DOS/FAT/NT Filesystems  --->
    <*> MSDOS fs support
    <*> VFAT (Windows-95) fs support
  Pseudo Filesystems --->
    [*] /proc file system support
    [*] Tmpfs virtual memory file system support (former shm fs)
    <*> EFI Variable filesystem
```

# Gentoo
```
Gentoo Linux --->
  [*] Gentoo Linux support
  [*]   Linux dynamic and persistent device naming (userspace devfs) support
  [*]   Select options required by Portage features
  Support for init systems, system and service managers  --->
      [*] OpenRC, runit and other script based systems and managers
```

# SOF firmware (optional)
```
Device Drivers --->
  Sound card support --->
    Advanced Linux Sound Architecture --->
      <M> ALSA for SoC audio support --->
        [*] Sound Open Firmware Support --->
            <M> SOF PCI enumeration support
            <M> SOF ACPI enumeration support
            <M> SOF support for AMD audio DSPs
            [*] SOF support for Intel audio DSPs
```

# Nvidia drivers (optional)
### Read wiki [Nvidia](https://wiki.gentoo.org/wiki/NVIDIA/nvidia-drivers)
```
[*] Enable loadable module support --->
Processor type and features --->
  [*] MTRR (Memory Type Range Register) support
Device Drivers --->
  PCI support --->
    [*] VGA Arbitration
  Character devices --->
    [*] IPMI top-level message handler
  Firmware Drivers  --->
    [*] Mark VGA/VBE/EFI FB as generic system framebuffer
  Graphics support --->
    -*- /dev/agpgart (AGP Support) ---> (Optional for only AGP cards)
    Frame buffer Devices --->
      < > nVidia Framebuffer Support (May confilict with in-kernel framebuffer)
      < > nVidia Riva support        (May confilict with in-kernel framebuffer)
      <*> Support for frame buffer devices  --->
        [*] VESA VGA graphics support
        [*] EFI-based Framebuffer Support
      <*> Simple framebuffer support
    Direct Rendering Manager (XFree86 4.1.0 and higher DRI support)  --->
      < > Nouveau (nVidia) cards     (For now disable Nouveau)
      Drivers for system framebuffers  --->
        < > Simple framebuffer driver
```