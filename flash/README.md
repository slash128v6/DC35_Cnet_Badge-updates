# Flash a badge by USB cable

> **Easiest: [flash from your browser](https://slash128v6.github.io/DC35_Cnet_Badge-updates/install.html).**
> In Chrome or Edge it needs no downloads at all, and it makes the same checks
> as this kit. Use this kit with Firefox or Safari, without a browser, or if you
> prefer a command line.

Most badges never need this: they update themselves over Wi-Fi. Use a cable
when a badge can't:

- it is on firmware **1.0.20 or older**, which looks for updates at an address
  that no longer serves them;
- it has no Wi-Fi to reach, or an update went wrong and it won't start;
- you want to wipe it completely before passing it on (`-Erase`).

This folder flashes the release in the folder above it, which is firmware
**1.0.32**. It checks the files before writing anything:

1. `manifest.json.sig` must be a valid signature over `manifest.json` under one
   of the public keys in `keys/`. These are the same keys built into every
   badge, so a release a badge would refuse over Wi-Fi is refused here too.
2. The firmware image must have exactly the size and SHA-256 that the signed
   manifest gives.

If either check fails, nothing is written.

**The badge keeps** its name, Wi-Fi details, settings, best scores and CTF
progress. Only the firmware is replaced. `-Erase` wipes all of that as well.

## Windows

1. Download this repository: **Code → Download ZIP**, then unzip it. Keep the
   `flash` folder where it is, next to `manifest.json`.
2. Get **esptool**, Espressif's flashing tool. Already have the Arduino IDE
   with the **esp32** boards package, or Python with `pip install esptool`?
   Then you have it; skip to step 3. Otherwise use the standalone Windows
   build, which needs nothing else installed:
   1. Open [esptool's releases page](https://github.com/espressif/esptool/releases) and, under the newest
      release's **Assets**, download `esptool-v…-windows-amd64.zip`.
   2. Unzip it **into the `flash` folder**, so you end up with something like
      `flash\esptool-windows-amd64\esptool.exe`. `flash.cmd` looks there
      by itself.
   3. If Windows SmartScreen warns about `esptool.exe` the first time, choose
      **More info → Run anyway** — but only for a copy you downloaded from
      that page yourself.
3. Plug the badge in with a USB cable that carries data, and switch it on.
4. Double-click `flash\flash.cmd`. Windows may ask whether to run a file from
   the internet; it is a short script you can read first.

It finds the badge's port by itself when only one USB serial device is plugged
in. The checks use Windows' own cryptography, so nothing else needs installing.

| Option | What it does |
| --- | --- |
| `-Port COM5` | which badge, when more than one USB serial device is plugged in |
| `-Baud 115200` | slower writing, for a flaky cable (default 921600) |
| `-Full` | also write the bootloader and partition table, for a badge that was flashed with something else |
| `-Erase` | wipe the badge completely first; implies `-Full` |
| `-VerifyOnly` | check the files and stop; needs no esptool and no badge |
| `-DryRun` | check the files and print the esptool command, without writing |
| `-Esptool <path>` | use a particular esptool |

Run it with options from a Command Prompt or PowerShell window in the unzipped
folder, for example `flash\flash.cmd -Port COM5 -Erase`.

If esptool can't connect, hold the badge's **BOOT** button while it says
`Connecting...`, try `-Baud 115200`, or try another cable. If there is no COM
port at all, see [Drivers](#drivers).

## Drivers

The badge's ESP32 board reaches the computer through a USB-to-serial chip,
and the computer needs that chip's driver. The badges use a **Silicon Labs
CP210x**; some other ESP32 boards use a **WCH CH340**. Rule out a
charge-only cable first, then:

- **Windows.** Open **Device Manager** with the badge plugged in. Under
  **Ports (COM & LPT)** it should appear as `Silicon Labs CP210x USB to UART
  Bridge (COM…)`. If it isn't there, or appears under **Other devices** with
  a warning sign, install the driver: the **CP210x Universal Windows Driver**
  from [Silicon Labs](https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers) (unzip it, right-click
  `silabser.inf`, **Install**), or for a CH340 board `CH341SER.EXE` from
  [WCH](https://www.wch-ic.com/downloads/CH341SER_EXE.html). Then unplug the badge and plug it in again.
- **macOS.** Recent versions usually need nothing. If no `/dev/cu.*` port
  appears, install the macOS driver from the same Silicon Labs page and allow
  it in **System Settings → Privacy & Security** when asked.
- **Linux.** The driver is built in. If esptool says permission denied, add
  yourself to the `dialout` group (`uucp` on Arch) and log out and back in.

## macOS and Linux

From the unzipped folder, check the signature and the image:

```bash
openssl dgst -sha256 -verify flash/keys/owner.pem -signature manifest.json.sig manifest.json
```

```bash
shasum -a 256 cnet-badge-1.0.32.bin
```

The first should print `Verified OK` (if it doesn't, try `flash/keys/recovery.pem`;
if neither verifies, don't flash). The second (`sha256sum` on Linux
does the same) should match `sha256` in `manifest.json`. Then write it, with `pip install esptool` if you don't have it:

```bash
esptool --chip esp32 --port /dev/ttyUSB0 write-flash -z 0xe000 flash/boot_app0.bin 0x10000 cnet-badge-1.0.32.bin
```

The port is usually `/dev/ttyUSB0` or `/dev/ttyACM0` on Linux, and
`/dev/cu.usbserial-*` or `/dev/cu.SLAB_USBtoUART` on macOS. esptool 4 spells
the command `write_flash`. For the equivalent of `-Full`, add
`0x1000 flash/bootloader.bin 0x8000 flash/partitions.bin`; for `-Erase`, add
`--erase-all` after `write-flash` as well.

## The files here

| File | What it is |
| --- | --- |
| `flash.cmd`, `flash.ps1` | the Windows flasher: checks the release, then runs esptool |
| `keys/owner.pem` | the key that signs routine releases |
| `keys/recovery.pem` | a key kept offline, for the day the owner key is lost |
| `boot_app0.bin` | resets the boot selector. Always written: a badge that has updated over Wi-Fi runs from its second firmware slot, and without this it would keep booting the old firmware |
| `bootloader.bin`, `partitions.bin` | written only with `-Full` |

**What the check does and doesn't prove.** It proves the firmware is intact and
was signed by a key the badges trust. The bootloader, partition table and boot
selector are not covered by the signature; they are the standard files from the
Arduino ESP32 core the firmware was built with. And because the keys come from
this same repository, a cable flash trusts this copy of them. A badge updating
over Wi-Fi trusts only the keys already inside it.
