# Processor type and features
```
Processor type and features  --->
    [*] EFI runtime service support 
    [*]   EFI stub support
    [*]     EFI mixed-mode support
-*- Enable the block layer --->
  Partition Types --->
    [*] Advanced partition selection
    [*] EFI GUID Partition support
```
# Drivers
```
Device Drivers  --->
  Generic Driver Options --->
    <*> Maintain a devtmpfs filesystem             (CONFIG_DEVTMPFS)
    [*]   Automount devtmpfs at /dev               (CONFIG_DEVTMPFS_MOUNT)
  Graphics support  --->
      Frame buffer Devices  --->
          <*> Support for frame buffer devices  --->
              [*]   EFI-based Framebuffer Support
  NVME Support --->
    <*> NVM Express block device                   (CONFIG_BLK_DEV_NVME)
  SCSI device support --->
    <*> SCSI device support                        (CONFIG_SCSI)
    <*> SCSI disk support                          (CONFIG_BLK_DEV_SD)
  Serial ATA and Parallel ATA drivers (libata)--->
    <*> ATA ACPI support
    <*> SATA support                               (CONFIG_ATA)
    <*> AHCI SATA support                          (CONFIG_SATA_AHCI)
  Multiple devices driver support (RAID and LVM) --->
    <*> Device mapper support                      (CONFIG_BLK_DEV_DM)
    <*>   Crypt target support                     (CONFIG_DM_CRYPT)
    <M>   Snapshot target                          (CONFIG_DM_SNAPSHOT)
  HID support --->
    <*> HID bus support                            (CONFIG_HID)
    <*>   Generic HID driver                       (CONFIG_HID_GENERIC)
    USB HID support --->
      <*> USB HID transport layer                    (CONFIG_USB_HID)
  USB support --->
    <*> Support for Host-side USB                  (CONFIG_USB)
    <*>   xHCI HCD (USB 3.0)                       (CONFIG_USB_XHCI_HCD)
    <*>   EHCI HCD (USB 2.0)                       (CONFIG_USB_EHCI_HCD)
    <*>   OHCI HCD (USB 1.1)                       (CONFIG_USB_OHCI_HCD)
    <*>   USB mass storage support                 (CONFIG_USB_STORAGE)
    <*>   USB Attached SCSI                        (CONFIG_USB_UAS)
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
  <*> Btrfs filesystem                              (CONFIG_BTRFS_FS)
  <*> Ext4 filesystem                               (CONFIG_EXT4_FS)
  Pseudo filesystems  --->
    <*> EFI Variable filesystem
  DOS/FAT/EXFAT/NT Filesystems --->
    <*> MSDOS fs support                            (CONFIG_FAT_FS)
    <*> VFAT (Windows-95) fs support                (CONFIG_VFAT_FS)
    <*> exFAT filesystem support                    (....)

```

