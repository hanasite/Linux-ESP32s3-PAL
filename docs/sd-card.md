# SD Card on SPI2 (ESP32-S3 NOMMU Linux)

## Wiring

Use the DevKitC-1 GPIO labels, not the header pin numbers.

| SD module | ESP32-S3 | Notes |
|---|---|---|
| VCC | 3V3 | 3.3 V only; do not use 5 V |
| GND | GND | |
| CS | GPIO10 | FSPICS0 |
| SCK | GPIO12 | FSPICLK |
| MOSI | GPIO11 | FSPID |
| MISO | GPIO13 | FSPIQ |

The module and card must be 3.3 V. Format the card as FAT32.

## Device tree

`arch/xtensa/boot/dts/esp32s3-devkit-c1.dts` already has the slot:

```dts
spi2_pins: spi2_pins {
    pinctrl-single,pins = <
        PIN(10) (FUN_SEL(4) | FUN_DRV_20MA)        /* CS0 */
        PIN(11) (FUN_SEL(4) | FUN_DRV_40MA)        /* MOSI */
        PIN(12) (FUN_SEL(4) | FUN_DRV_40MA)        /* SCK */
        PIN(13) (FUN0_20MA_IE_WPU)>;               /* MISO */
};

&spi2 {
    pinctrl-0 = <&spi2_pins>;
    pinctrl-names = "default";
    status = "ok";

    mmc_spi@0 {
        compatible = "mmc-spi-slot";
        reg = <0>;
    };
};
```

## Kernel configuration

The 0.9.1 image has no MMC/MMC_SPI/VFAT, so `/dev/mmcblk*` never appears.
This branch adds to `new-files/board/espressif/esp32s3/devkit_c1_16m_linux.config`:

```text
CONFIG_BLOCK=y
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_MMC_SPI=y
CONFIG_MSDOS_PARTITION=y
CONFIG_FAT_FS=y
CONFIG_VFAT_FS=y
CONFIG_NLS=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NLS_UTF8=y
CONFIG_NLS_DEFAULT="utf8"
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_FAT_DEFAULT_IOCHARSET="utf8"
CONFIG_SPI_SPIDEV=y
```

`CONFIG_SPI` and `CONFIG_SPI_ESP32` are already enabled. The block layer
and MMC/FAT code fit in the 4 MiB `linux` partition (0.9.1 `xipImage` is
2.4 MiB).

## Build

Requires Docker and about 21 GB free, on a clean checkout:

```sh
git checkout sd-card
JOBS=8 bash build/reproduce.sh
```

The artifacts are under `build-output/reproduce.XXXXXX/artifacts/`.
The kernel is `xipImage`.

## Flash the kernel only

The `linux` partition starts at `0x00140000` and is 4 MiB. Writing only
`xipImage` preserves `/etc`, `/home`, the Guarded MVP, and the boot splash.

```sh
esptool --chip esp32s3 --port COM8 --baud 460800 write-flash \
  --flash-mode dio --flash-size 16MB --flash-freq 80m \
  0x140000 build-output/reproduce.XXXXXX/artifacts/xipImage
```

A full-image or `flash.sh --parts` write also rewrites `/etc` and the
rootfs; if you use it, re-run `/etc/pal/install.sh` for the agent user.

## Verify and mount

```sh
dmesg | grep -i mmc
ls /dev/mmcblk*
mkdir -p /mnt
mount -t vfat /dev/mmcblk0p1 /mnt
ls /mnt
```

If the card has no partition table, mount `/dev/mmcblk0` directly.
