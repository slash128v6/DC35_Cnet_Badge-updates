# DC35 CNet badge — firmware updates and guides

This repository is where DC35 CNet radar badges look for new firmware, and
where the badge's guides are published. Its history is replaced on every
release, so it only ever holds the current one.

## Guides

**Read them as web pages at https://slash128v6.github.io/DC35_Cnet_Badge-updates/**

| Guide | What it covers |
| --- | --- |
| [Assembly guide](https://slash128v6.github.io/DC35_Cnet_Badge-updates/docs/assembly_guide.html) | soldering a rev G badge together: parts, build order, first power-up |
| [SAO assembly guide](https://slash128v6.github.io/DC35_Cnet_Badge-updates/docs/sao_assembly_guide.html) | building the four reef SAOs: three parts each, which way round, plugging one in |
| [Flash from your browser](https://slash128v6.github.io/DC35_Cnet_Badge-updates/install.html) | installing this firmware over USB from Chrome or Edge, for a badge that can't update over Wi-Fi |
| [Flash by cable](flash/README.md) | the same with esptool from a command line, for other browsers or no browser |
| [User guide](docs/USER_GUIDE.md) | every mode, every button, setup, updates, troubleshooting |
| [Badge guide](https://slash128v6.github.io/DC35_Cnet_Badge-updates/docs/badge_guide.html) | the same, as an illustrated page |
| [Sneak rulebook](https://slash128v6.github.io/DC35_Cnet_Badge-updates/docs/sneak_rulebook.html) | how to run a game of Red Light, Green Light with one badge |
| [Duel rulebook](https://slash128v6.github.io/DC35_Cnet_Badge-updates/docs/duel_rulebook.html) | the two-badge standoff: setup, the round, fair play |

## Firmware

| File | What it is |
| --- | --- |
| `manifest.json` | the current version, and the size and SHA-256 of its firmware image |
| `manifest.json.sig` | an ECDSA P-256 signature over the manifest |
| `cnet-badge-<version>.bin` | the firmware image |
| `flash/` | a kit for installing it over a USB cable, which checks the signature first |

**A badge installs nothing it cannot verify.** It checks the manifest's
signature against public keys built into its own firmware, then checks the
downloaded image against the hash in that signed manifest, and only then
writes it. A file changed here, or anywhere between here and the badge, is
refused. That is why these files can be public, and why they have to be: a
badge carries no credentials.

**Badges on firmware 1.0.20 or older** look for updates at an address that
no longer serves them, so they need one update over USB; after that they
update over Wi-Fi again. See [Flash from your browser](https://slash128v6.github.io/DC35_Cnet_Badge-updates/install.html)
or [Flash by cable](flash/README.md).

A badge checks about every ten minutes when it has Wi-Fi and automatic updates
are on, and straight away from **Settings → Updates → Check now**.

These files are published by the badge's release tooling. Please don't open
issues or pull requests here.
