# Fedora bootc 44 — Labwc desktop + Konica Minolta bizhub 206

A custom [Fedora bootc](https://bootc.dev/) image for an older x86_64 Intel PC
(the target is an Intel Core i5 650). It provides:

- **Fedora bootc 44**, `linux/amd64`
- **Labwc** Wayland compositor, **sfwbar** panel (openbox-style start menu and
  task buttons), **Foot** terminal
- A desktop with **pcmanfm**, **gthumb**, **evince**, **mousepad**,
  **xarchiver**, **pavucontrol**, GVFS/udisks2, and a right-click menu
- **LibreOffice** (full suite) and **ONLYOFFICE Desktop Editors** (official
  vendor repository)
- **NAPS2** scanning front-end plus **simple-scan**, with **sane-airscan** for
  driverless (eSCL/AirScan) network scanners
- **Flatpak** with the **Flathub** remote preinstalled (xdg-desktop-portal
  GTK/wlr portals for file choosers and screen sharing)
- A real graphical login path: **greetd** on VT1 → **tuigreet** → **labwc**
- NetworkManager, PipeWire/WirePlumber, portals, polkit, XWayland
- The **Konica Minolta bizhub 206** PAPPL printer application
  ([konica206-native-alpine](https://github.com/vinod2807/konica206-native-alpine))
  built for Fedora, with the
  [konica-native](https://github.com/vinod2807/konica-native-musl) C11
  device-stream encoder as the filter stage
- A driverless **Epson L3260** network queue (`ipp://192.168.1.19/ipp/print`,
  IPP Everywhere) created automatically at boot
- The Intel i5 650 crash/freeze kernel arguments from
  [linux-pc-crash-fixes](https://github.com/vinod2807/linux-pc-crash-fixes)

Published image:

```
ghcr.io/vinod2807/fedora-bootc-konica206:latest
```

The installed machine tracks that reference and updates with `bootc upgrade`.
**A new ISO is not needed for routine updates.**

---

## Repository layout

| Path | Purpose |
|---|---|
| `Containerfile` | Multi-stage bootc image build (printer binaries built in a Fedora 44 builder stage) |
| `.github/workflows/weekly-image.yml` | Weekly (Sunday 03:00 UTC) + manual image build/publish; never builds an ISO |
| `.github/workflows/build-iso.yml` | Manual-only Anaconda installer ISO build with El Torito and QEMU SeaBIOS checks |
| `.github/iso/Containerfile` | Anaconda installer container consumed by image-builder `bootc-generic-iso` |
| `.github/iso/iso.yaml` | GRUB/ISO label and kernel command line for the installer media |
| `systemd/` | Printer/queue units, the stage-only (never reboots) bootc update timer, and the daily Flatpak update timers (system + user) |
| `udev/70-konica206.rules` | USB permissions for `132b:232b` (group `lp`, `uaccess`) |
| `greetd/config.toml` | tuigreet → labwc login session |
| `desktop/` | labwc autostart/environment/menu, sfwbar panel config, Waybar fallback config |
| `scripts/install-vendor-data` | Post-install installer for the licensed Konica runtime data |
| `scripts/ensure-queue` | Creates the PAPPL queue and the local CUPS queue with the PPD shim |
| `scripts/ensure-epson-queue` | Creates the driverless Epson L3260 network queue |
| `scripts/preflight` | Read-only diagnostic (`sudo konica206-preflight`) |
| `ppd/konica206.ppd` | Hand-written PPD shim: real media sizes, duplex, A4/simplex defaults |
| `local-rpms/` | Vendored vendor RPMs installed at build time (Epson Printer Utility) |
| `bootc/`, `modprobe.d/` | i5 650 C-state/audio crash fixes |
| `docs/PRINTER.md`, `docs/CRASH-FIXES.md` | Detailed notes |

---

## Build triggers: what runs when

### Weekly image (automatic)

`.github/workflows/weekly-image.yml`

- Cron `0 3 * * 0` (Sunday 03:00 UTC) and `workflow_dispatch`
- Builds `linux/amd64`
- Runs `dnf upgrade --refresh` so the image picks up Fedora 44 updates
- Resolves `konica206-native-alpine` and `konica-native-musl` `main` to full
  commit SHAs with `git ls-remote`, and passes those SHAs as build args. The
  SHAs are baked into image labels and the workflow summary.
- Runs the upstream vendor-free tests in the builder stage:
  - `make check` (chunking + PPD parser)
  - `make check-native` (PAPPL job path with a stand-in filter)
  - `konica-native`: `make check` (raster reader cross-check, CMM table,
    geometry, MEDIATYPE, failure modes)
- Builds the image locally, runs a container smoke test, then pushes to GHCR
  only if the smoke test passed.
- Tags: `latest`, `main`, and `sha-<full-commit>` (rolling + traceable)
- Concurrency group per branch, `cancel-in-progress: false`
- `permissions: contents: read`, `packages: write`
- Uses Buildx/GHA cache; the cache key includes the resolved source SHAs, so a
  new upstream commit cannot be hidden by an old cache.
- **Does not build an ISO.**

### ISO (manual only)

`.github/workflows/build-iso.yml`

- Triggered **only** by `workflow_dispatch` (no schedule, no push)
- Input: `image_tag` (default `latest`)
- Pulls the published image, resolves its **digest**, and bakes that digest into
  the installer so the ISO installs the exact tested image
- Builds an Anaconda installer container, then uses the current image-builder
  path:

  ```text
  ghcr.io/osbuild/image-builder-cli  build ... bootc-generic-iso
  ```

  The legacy `bootc-image-builder --type iso` command is deliberately not used.
  The image-builder CLI is pinned by digest; the Anaconda/`bootc-generic-iso`
  recipe follows the current upstream documentation
  (`doc/40-bootc-generic-iso.md` and `doc/20-advanced/20-bootc/10-isos.md`).
- Verifies the ISO has an **El Torito BIOS boot entry** (grub2 `eltorito.img`
  or isolinux) with `xorriso`.
- Boots the ISO under **QEMU with SeaBIOS** (no OVMF/UEFI firmware) and requires
  the serial console to reach a Linux userspace target.
- Writes SHA-256 and SHA-512 checksums.
- Uploads the ISO, checksums, El Torito metadata and QEMU serial log as a
  30-day artifact.
- Never writes to a physical disk or flashes a USB device.

---

## First image build

From GitHub:

1. Open **Actions → weekly-image → Run workflow** on `main`.
2. Wait for the job. The summary shows the GHCR tags and the exact printer
   source SHAs.
3. Confirm the package is public (see [Repository settings](#repository-settings)).
4. `docker pull ghcr.io/vinod2807/fedora-bootc-konica206:latest` (or
   `podman pull ...`).

From the CLI:

```bash
gh workflow run weekly-image.yml --repo vinod2807/fedora-bootc-konica206
gh run watch --repo vinod2807/fedora-bootc-konica206
```

Local build (Fedora host with podman):

```bash
git clone https://github.com/vinod2807/fedora-bootc-konica206
cd fedora-bootc-konica206
podman build --platform linux/amd64 -t localhost/fedora-bootc-konica206 .
```

### Third-party app versions and the layer cache

ONLYOFFICE Desktop Editors is installed from ONLYOFFICE's own repository, not
from Fedora, so its version is whatever is current **when the image is built**.
The instruction that installs it never changes, which means BuildKit would
replay it from cache and keep the old RPM. To prevent that, the `Containerfile`
takes a `BUILD_EPOCH` build arg that is only used to change this layer's cache
key, and `weekly-image.yml` passes the workflow run id:

```dockerfile
ARG BUILD_EPOCH=local
...
RUN set -eux; \
    echo "resolving third-party apps (cache epoch: ${BUILD_EPOCH})"; \
    dnf install -y onlyoffice-desktopeditors; ...
```

For a local build that must fetch the current RPM instead of reusing your local
cache, pass your own value (anything that differs from the previous build):

```bash
podman build --platform linux/amd64 \
  --build-arg BUILD_EPOCH="$(date +%s)" \
  -t localhost/fedora-bootc-konica206 .
```

NAPS2 is deliberately different: it is pinned to an exact release tag, so it
only changes when that pin is edited in the `Containerfile`.

On an installed system this is the *only* update path for ONLYOFFICE: `/` is
read-only, so `dnf upgrade onlyoffice-desktopeditors` cannot change it. A new
version arrives when a new image is published, is staged by
`bootc-upgrade.timer`, and takes effect on the next reboot.

---

## One-time installation from the ISO

1. Run **Actions → build-iso → Run workflow**, `image_tag=latest`.
2. Download the artifact from the run, verify it:

   ```bash
   sha256sum -c SHA256SUMS
   ```

3. Write it to a USB stick (replace `/dev/sdX` with the **whole device**, not a
   partition; this erases the stick):

   ```bash
   sudo dd if=konica206-bootc-<run>-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
   sync
   ```

4. On the target PC, select the USB device in the **legacy BIOS/CSM** boot menu.
   The ISO is hybrid (BIOS + UEFI), but the firmware mode used to boot Anaconda
   is the mode it installs.
5. Anaconda installs the bootc image referenced by the ISO. Create your own
   user (admin/wheel) and **set the root password** in the installer. **No user
   or password is baked into the image.**
6. Reboot. greetd/tuigreet appears on VT1; log in with the user you created.

The installer pulls the image from GHCR. The GHCR package must be **public**
for an unauthenticated install, or you must provide registry credentials in the
installer environment. Making it public is the documented path.

### Real-hardware checklist for this PC

Before you start: the target disk will be erased, and the installer needs the
internet (it pulls the image, roughly 1 GiB compressed, from GHCR).

1. **Network:** use a **wired Ethernet** connection on the i5 650. Wi-Fi on this
   generation is usually unsupported in the installer; wired avoids that.
2. **Firmware:** legacy BIOS/CSM, USB-HDD as first boot device. Secure Boot is
   not relevant in legacy mode.
3. **Disk:** pick the whole disk (e.g. `/dev/sda`), not a partition. bootc
   creates GPT with a BIOS boot partition.
4. **Account:** in the Anaconda user spoke create your account, tick
   *Make this user administrator*, and set **both** the user password and the
   **root password**. Root is the fallback if the desktop does not start.
5. **Install:** the payload is pulled by digest from
   `ghcr.io/vinod2807/fedora-bootc-konica206`; the installed system tracks
   `:latest` for `bootc upgrade`.
6. **First boot:** log in at tuigreet (VT1) → labwc. Text fallback is
   `Ctrl+Alt+F2` with the same user (or `root` + the root password you set).
   If the user account is unexpectedly missing, log in as `root` on that text
   console and run `useradd -m -G wheel -s /bin/bash <name>` then
   `passwd <name>`.
7. **Post-install:** verify the crash fixes (`cat /proc/cmdline`), then install
   the licensed printer runtime data
   (`sudo konica206-install-vendor-data <path>`) and run
   `sudo konica206-preflight`.

### BIOS installation notes

- The target must be booted in legacy BIOS/CSM mode; then Anaconda writes a
  BIOS/MBR-compatible boot path (GPT with a BIOS boot partition, as bootc
  expects) rather than an EFI-only one.
- The ISO itself is checked for El Torito BIOS boot metadata and booted under
  QEMU SeaBIOS in CI.
- An ISO boot test is **not** a complete install test. A physical install and
  first boot still need to be confirmed on the target PC.
- Do not switch the firmware to UEFI-only after a BIOS install unless you
  reinstall or repair the bootloader.
- The installer pulls the image from GHCR, so the target PC needs working
  network access during installation (or a locally preloaded payload).
- Upstream documents a known Anaconda-installed bootc issue where
  `systemd-remount-fs.service` reports a failure on the installed system
  (fedora atomic-desktops tracker #72, RHBZ 2332319). Check
  `systemctl --failed` after first boot; it is an upstream limitation, not
  specific to this image.

---

## First boot and login

- **Graphical:** greetd starts on VT1, tuigreet asks for the user/password you
  created during installation, then launches `labwc`.
- **Panel:** **sfwbar** autostarts (`/usr/share/sfwbar/sfwbar.config`), in
  openbox/tint2 style: a **Start** button that opens a categorised application
  menu generated from the installed `.desktop` files, terminal and files
  buttons, a window list (click = focus/minimise, middle-click = close,
  right-click = window menu), tray, network, volume, battery and clock.
  Window buttons and the window menu use the compositor's foreign-toplevel
  protocol, so they track labwc windows directly. Waybar is still installed as
  a fallback (`waybar &`).
  The packaged sfwbar (1.0~beta16.1) has no `edge` setting: the bar's edge is
  chosen by `window { -GtkWidget-direction: top; }` in the CSS section — change
  it to `bottom` to move the panel. Sizing/layout notes that matter when
  editing `desktop/sfwbar/sfwbar.config`:
  - comments inside the `#CSS` section must use slash-star form; a `#` comment
    is an ID selector and makes GTK reject the whole stylesheet (the panel then
    falls back to the light GTK theme);
  - never put `-GtkWidget-hexpand: true` on the taskbar: the flow grid gives the
    freed width to the window buttons and one window stretches across the bar.
    A spacer label does the right-side alignment instead.
- **Desktop menu:** right-click the desktop for Files, Terminal, Image viewer,
  Text editor, Archive manager, Document viewer, an **Office** submenu
  (LibreOffice Writer/Calc/Impress, ONLYOFFICE), a **Scanning** submenu, Volume,
  Network and Session actions (`/etc/xdg/labwc/menu.xml`).
- **Application menu:** the **Start** button opens sfwbar's `app_menu_system`
  menu, built from `/usr/share/applications` (so newly installed and Flatpak
  apps appear automatically). `fuzzel` is still available as a keyboard
  launcher (`fuzzel`, or `fuzzel dmenu` for stdin).
- **Applications:** `pcmanfm` (files, with GVFS/udisks2 automount),
  `gthumb` (images), `evince` (PDF), `mousepad` (text), `xarchiver`,
  `pavucontrol`, `nm-connection-editor`, `foot` (terminal),
  **LibreOffice** (Writer/Calc/Impress/Draw/Base/Math) and
  **ONLYOFFICE Desktop Editors** (installed from ONLYOFFICE's own repository).
- **Scanning:** `simple-scan` and **NAPS2**, both backed by `sane-airscan` for
  driverless eSCL/AirScan devices (the Epson L3260 scanner and most modern
  network MFPs).
- **Flatpak:** `flatpak` and the Flathub remote are ready; install apps with
  `flatpak install flathub <app-id>` and run them from the launcher. Installed
  Flatpaks update themselves daily (see *Automatic Flatpak updates*).
- **GitHub CLI:** `gh` is installed (`gh auth login`, `gh repo clone …`,
  `gh workflow run …`).
- **Text fallback:** `Ctrl+Alt+F2` gives a text login. From there, run `labwc`
  to start the Wayland session manually.
- **Audio:** PipeWire, WirePlumber and `pipewire-pulseaudio` are enabled for
  users. Use `wpctl status` / `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`.
- **Networking:** NetworkManager is enabled. Use `nmcli device status` and
  `nmcli connection up <name>`; Wi-Fi needs `NetworkManager-wifi` +
  `wpa_supplicant`, both installed.
- **Printer:** `konica206-native.service` is enabled and restarts on failure;
  `konica206-queue.service` creates the CUPS queue when the printer is
  attached. Install the licensed runtime data with
  `sudo konica206-install-vendor-data <path>`.

No SSH server is installed by default. No default password, SSH key, or
credential is embedded in the image.

---

## Updates on the installed PC

The installed system’s image reference is the `TARGET_IMAGE` baked into the
installer:

```
ghcr.io/vinod2807/fedora-bootc-konica206:latest
```

### Manual update

```bash
sudo bootc status                 # current image, staged image, rollback target
sudo bootc upgrade                # downloads and stages the new deployment
sudo systemctl reboot            # activates it
```

`bootc upgrade` stages by default; it does **not** reboot, which is exactly how
the automatic update below behaves. Passing `--apply` (not used here) would
reboot immediately.

To change the tracked image (for example to a frozen SHA tag):

```bash
sudo bootc switch ghcr.io/vinod2807/fedora-bootc-konica206:sha-<commit>
sudo systemctl reboot
```

### Rollback

```bash
sudo bootc rollback
sudo systemctl reboot
```

The previous deployment remains available in the bootloader. Roll back if a
new image does not boot, the desktop does not start, or printing regresses.

### Automatic updates (download and stage only — never reboot)

Fedora's bootc base image enables `bootc-fetch-apply-updates.timer`, which runs
`bootc upgrade --apply` and **reboots the machine into the new image**. This
desktop must only reboot when you choose, so that timer is masked in the image:

| Unit | State | What it does |
|---|---|---|
| `bootc-fetch-apply-updates.timer` | **masked** (`→ /dev/null`) | would pull, deploy and reboot unattended |
| `bootc-upgrade.timer` | **enabled** | runs `bootc upgrade` — download + stage only, no reboot |

`bootc-upgrade.timer` is scheduled with `OnCalendar=daily`, a 1 h random delay
and `Persistent=true`. Because the machine is switched off overnight, a missed
run executes at the next boot instead of being skipped: the update is staged,
and nothing changes until you reboot.

Reboot when it suits you:

```bash
bootc status                       # current + staged deployment
sudo systemctl reboot             # activates the staged image
```

Check that staging happened:

```bash
systemctl list-timers bootc-upgrade.timer
journalctl -u bootc-upgrade.service
```

Install updates right away instead of waiting for the timer:

```bash
sudo systemctl start bootc-upgrade.service
```

If you ever want fully unattended reboots, un-mask and enable the upstream timer
(and accept that the machine restarts on its own):

```bash
sudo systemctl unmask bootc-fetch-apply-updates.timer
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

Updates pull anonymously from GHCR, so the package must be public or the host
authenticated (see *Registry access* below). A staged update that fails to boot
can be rolled back from the bootloader or with `bootc rollback`.

### Automatic Flatpak updates

Flatpak has no built-in updater, so the image ships two timers that install new
Flatpak versions daily with a 1 h jitter and `Persistent=true` (a run missed
while the machine was off happens at the next boot/login):

| Unit | Scope | Runs |
|---|---|---|
| `flatpak-update.timer` (`/usr/lib/systemd/system/`) | system installation | `flatpak update -y --noninteractive --system`, then `flatpak uninstall --unused -y` |
| `flatpak-update.timer` (`/usr/lib/systemd/user/`, enabled globally) | per-user installation | the same with `--user`, inside the graphical session |

Flatpak updates never reboot and need none: running apps keep running and use
the new version at the next start. Check them with:

```bash
systemctl list-timers flatpak-update.timer
systemctl --user list-timers flatpak-update.timer
journalctl -u flatpak-update.service
journalctl --user -u flatpak-update.service
```

Update immediately instead of waiting:

```bash
sudo systemctl start flatpak-update.service
systemctl --user start flatpak-update.service
```

### Registry access

- The workflow pushes with `GITHUB_TOKEN` (`packages: write`).
- GHCR packages are **private by default**, even for a public repository.
  Make the package public so the installer and installed PC can pull without
  credentials.
- If you keep it private, authenticate both the installer environment and the
  installed system (`bootc` uses the host’s containers auth); otherwise
  `bootc upgrade` will fail with an authentication error.
- A failed update leaves the current deployment running; use `bootc rollback`
  or the bootloader’s previous entry.

Updating an image does **not** guarantee a successful boot, desktop session, or
printer operation. Keep the previous deployment (bootc rollback) available.

---

## Konica Minolta bizhub 206

Full details: [`docs/PRINTER.md`](docs/PRINTER.md).

### What is built

| Component | Source | Installed as |
|---|---|---|
| PAPPL printer application | `konica206-native-alpine` `main` | `/usr/bin/konica206-native`, `/usr/bin/konica-send`, `/usr/bin/konica-render` |
| C11 device-stream encoder | `konica-native-musl` `main` | `/usr/bin/konica-native` (the app’s `KONICA_VENDOR_FILTER`) |

Both are compiled from source in the Fedora 44 builder stage, so no Alpine/musl
binary or OpenRC unit is used. The app runs as the unprivileged `konica` system
user (member of `lp`), under systemd, with the queue served at:

```
ipp://127.0.0.1:8001/ipp/print/konica206
```

USB ID: `132b:232b`. The udev rule sets mode `0660`, group `lp`, and `uaccess`.
The service is not run as root.

The queue is created automatically at boot or on plug-in by
`konica206-queue.service` when the printer’s USB serial is visible. Manual
trigger:

```bash
sudo systemctl start konica206-queue.service
konica206-native printers -u ipp://localhost:8001
```

### Vendor runtime data — required, not redistributed

The native encoder loads three **Konica Minolta-owned** files at runtime,
before it writes any output. It resolves them at its compiled-in path, which is
a symlink into persistent writable state because `/usr` is immutable on bootc:

```
/usr/local/lib/konica  ->  /var/lib/konica206/vendor

/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/COPA.DEFAULT.600x600.hft
/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sRGB.icm
/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sGrayInv.icm
```

The upstream `vendor/NOTICE` says these files remain Konica Minolta property
and are **not** covered by the repository license; redistribution needs the
vendor’s permission. Therefore this repository and the public image contain
**none of them**, and the image build never copies the upstream `vendor/`
directory. The source clone exists only in the builder stage.

Supply them after installation from your own licensed 245igdi driver copy:

```bash
sudo konica206-install-vendor-data /path/to/245igdi-or-archive
sudo konica206-preflight
```

The installer accepts a directory containing `KonicaMinolta/245igdi/...`,
`245igdi/...`, or `Halftones/` + `Profiles/`, or a `.tar/.tar.gz/.tgz/.tar.xz/.zip`
archive. It copies only the required runtime data (plus optional extra `.icm`
and 1200×600 screen if present), restarts the service, and creates the queue if
the printer is attached. It never prints file contents.

Without these files the service still starts, but every print job fails
**clearly and with no output sent to the printer** (`konica-native` exits
non-zero before writing the first byte). The printer feature is therefore
**incomplete until you supply the licensed data**.

The PPD is optional: page geometry, tray mapping and the duplex rule are
compiled into the application. No vendor PPD is installed or redistributed.

### Test print

A CUPS queue named **`konica206`** is created automatically (by
`konica206-queue.service`) once the PAPPL queue exists. It points at
`ipp://127.0.0.1:8001/ipp/print/konica206` and uses the shipped PPD shim
`/usr/share/ppd/konica206/konica206.ppd`, which lists the ten real media sizes
(A3, A4, A5, A6, ISO B4, ISO B5, Letter, Legal, Executive, Statement) with the
device's ~4.2 mm hardware margins — CUPS' auto-generated "everywhere" PPD
labels every size `*.Borderless`, which this printer does not support.

Defaults are **A4 and simplex** (`PageSize=A4`, `Duplex=None`) and are re-applied
on every boot. Duplex is available per job:

```bash
lp -d konica206 /path/to/test.pdf                          # A4, 1-sided
lp -d konica206 -o PageSize=A3 file.pdf                    # A3
lp -d konica206 -o Duplex=DuplexNoTumble file.pdf          # long-edge duplex
lp -d konica206 -o Duplex=DuplexTumble file.pdf            # short-edge duplex
```

Change the persistent defaults:

```bash
sudo lpadmin -p konica206 -o PageSize=Letter -o Duplex=DuplexNoTumble
lpoptions -p konica206 -l          # list every option and its current default
```

Print a **PDF**, not PostScript (the driver deliberately does not advertise
`application/postscript`). A real USB print is required to confirm paper
output; compilation and the offline tests cannot prove the printer works.

Troubleshooting:

```bash
journalctl -u konica206-native -b
systemctl status konica206-native konica206-queue
sudo konica206-preflight
lsusb -d 132b:232b
konica206-native printers -u ipp://localhost:8001
```

Only one process may own the printer’s USB interface at a time. Do not run a
second legacy Konica queue against the same device.

### Licensing status

- Code binaries: built from the upstream repositories at build time.
- Vendor runtime data: **not** redistributed; post-install supply only.
- Vendor PPD: **not** redistributed; not required.
- No vendor files are committed, baked into the image, or uploaded as public
  artifacts.
- The image license metadata is `NOASSERTION`; review the upstream licenses
  before redistributing the image further.

---

## Epson L3260 (network printer)

The Epson L3260 at **192.168.1.19** is configured as a **driverless
(IPP Everywhere / Mopria 2.1)** queue. Nothing Epson-specific is installed: CUPS
reads the printer's own IPP attributes and generates the PPD itself, exactly
like AirPrint.

```
queue name   EPSON_L3260
device URI   ipp://192.168.1.19/ipp/print
model        IPP Everywhere (auto-generated PPD)
```

`epson-l3260-queue.service` (oneshot, enabled at boot) waits for the printer to
answer on port 631 and then creates the queue. It is idempotent, and a printer
that is switched off at boot is not treated as a failure — the unit logs it and
exits successfully.

### Manual setup / repair

```bash
sudo systemctl start epson-l3260-queue      # create it now
lpstat -v EPSON_L3260                       # must show ipp://192.168.1.19/ipp/print
```

Or by hand:

```bash
sudo lpadmin -p EPSON_L3260 -E \
  -v ipp://192.168.1.19/ipp/print -m everywhere \
  -D "Epson L3260 Series" -L "Network"
```

Test print:

```bash
lp -d EPSON_L3260 /usr/share/cups/data/testprint
```

Make it the default printer (optional — the Konica stays the default otherwise):

```bash
lpadmin -d EPSON_L3260
```

### Scanner (L3260 and other network MFPs)

`sane-airscan` talks to the scanner over eSCL/AirScan without a vendor driver;
`simple-scan` and NAPS2 are the front-ends. The L3260 exposes scanning on the
same host as printing:

```bash
scanimage -L                  # should list eSCL/AirScan devices
simple-scan                   # or launch NAPS2 from the menu
```

If nothing is listed, check that `avahi-daemon` is running (mDNS discovery) and
that the printer is on the same L2 network; `scanimage --test` then verifies a
single page.

### Epson Printer Utility (vendor RPM)

Epson ships *Epson Printer Utility for Linux* (ink levels, head cleaning,
nozzle check) only through
<https://download-center.epson.com/> → **L3260 Series** → **Linux RPM(x64)**.
That site (and its API) answers automated clients with **HTTP 403**, so the
image cannot download it at build time.

The current vendor build — `epson-printer-utility-1.2.3-1.x86_64.rpm`, sha256
`58f992ea…76d489` — is committed in `local-rpms/` and installed by every build.
It appears as **Epson Printer Utility** in the application launcher. See
[`local-rpms/README.md`](local-rpms/README.md) for what the build adds on top of
the plain install (Qt5 toolkit, menu entry, skipped vendor scriptlets).

To update it later, drop the newer file into `local-rpms/`, delete the old one,
commit. Printing and scanning do not depend on the utility — the queue is
driverless.

Different address or name, without rebuilding the image:

```bash
sudo EPSON_HOST=192.168.1.50 EPSON_QUEUE=EPSON_L3260_2 \
  /usr/libexec/epson-l3260/ensure-queue
```

The printer is colour, A4/legal, no duplex, and reports
`marker-supply-low-warning` when ink is low. CUPS web UI: `http://localhost:631`
(cups.socket is enabled, so cupsd starts on demand).

Note: the queue lives in `/etc/cups/printers.conf`, which persists across
`bootc upgrade`; if you ever delete it, the boot unit recreates it.

---

## Intel i5 650 crash / freeze fixes

The image applies the settings from
[vinod2807/linux-pc-crash-fixes](https://github.com/vinod2807/linux-pc-crash-fixes):

```
intel_idle.max_cstate=1
snd_hda_intel.power_save=0
snd_hda_intel.power_save_controller=0
```

They are in `/usr/lib/bootc/kargs.d/90-linux-pc-crash-fixes.toml` (applied at
install and by bootc upgrades) and in
`/etc/modprobe.d/90-linux-pc-crash-fixes.conf`. Verify with:

```bash
cat /proc/cmdline
cat /sys/module/intel_idle/parameters/max_cstate                  # 1
cat /sys/module/snd_hda_intel/parameters/power_save               # 0
cat /sys/module/snd_hda_intel/parameters/power_save_controller    # N
```

See [`docs/CRASH-FIXES.md`](docs/CRASH-FIXES.md).

---

## Versioning and maintenance policy

- **Fedora major version:** 44. Changing it requires editing `BASE_IMAGE` and
  `BUILDER_IMAGE` in `Containerfile` and re-testing; it is not automatic.
- **Fedora updates:** each weekly build runs `dnf upgrade --refresh`, so it
  picks up the current Fedora 44 packages.
- **Printer sources:** built from `main` each week. The workflow resolves
  `main` to a full SHA and records it in image labels/summary. This gives
  reproducibility per published image without freezing future weekly builds.
  To pin a specific source revision, run the workflow with build args changed
  (or edit the `KONICA_*_REF` defaults) to a SHA.
- **GitHub Actions:** pinned to full commit SHAs (commented with the release
  tag). Update deliberately and re-run the smoke test.
- **image-builder CLI:** pinned by digest in `build-iso.yml`. Update the digest
  only after checking the current upstream ISO docs and re-running the QEMU
  SeaBIOS test.
- **CPU flags:** no `-march=native` or CPU-specific flags. The printer
  Makefiles use upstream `-O2`; the image targets generic x86_64.

---

## Validation status

This table distinguishes what CI actually proves from what still needs a
machine. It is updated after workflow runs.

| Check | Status |
|---|---|
| Containerfile builds `linux/amd64` | **Passed** — `weekly-image` run [40684026498](https://github.com/vinod2807/fedora-bootc-konica206/actions/runs/40684026498) |
| Upstream printer `make check` / `make check-native` | **Passed** — same run (builder stage) |
| `konica-native` vendor-free test suite | **Passed** — same run (builder stage) |
| Container smoke test (packages, units, binary versions, no vendor files, `/usr/local` symlink, `pdftoraster`) | **Passed** — same run, before the push |
| Weekly push to GHCR + traceable tags | **Passed** — tags `latest`, `main`, `sha-ff563ecb6e91280d01cf3bf0412c588468319837`; all resolve to `sha256:73dee69ab2a2756636a8d680c7941cef0f4516da12fa44e8f473d84ecb325ae9`. Anonymous pull works (public package). |
| ISO El Torito BIOS metadata | **Passed** — `build-iso` run [40688027094](https://github.com/vinod2807/fedora-bootc-konica206/actions/runs/40688027094): `-b '/images/eltorito.img'`, `Boot record: El Torito, grub2-mbr, GPT` |
| ISO boots under QEMU SeaBIOS to Linux userspace | **Passed** — same run; serial log reaches the Anaconda installer UI |
| Full BIOS installation on real hardware | **Passed** — installed on the i5-650 desktop (BIOS boot, NTFS partition preserved) |
| Graphical login (greetd → labwc → sfwbar) on real hardware | **Passed** — graphical session in daily use |
| Real USB printing on bizhub 206 | **Passed** — real A4 simplex job printed from the `konica206` queue (2026-10-28) |
| Printer works with vendor assets installed | **Passed** — same job, licensed runtime data installed |
| Duplex, A3 and other media sizes on real paper | **Not tested** — options are present and selectable, but only A4 simplex has been printed |

Do not treat “ISO file exists” or “compilation succeeded” as proof of a working
BIOS install or a working printer.

---

## Repository settings

After the first push/build:

1. **Actions enabled:** Settings → Actions → General → Allow all actions.
2. **Workflow permissions:** Settings → Actions → General → Workflow
   permissions → **Read and write permissions** (the workflows also declare
   least-privilege `permissions:` blocks; image push needs `packages: write`).
3. **GHCR package visibility:** the first push is already anonymously
   pullable (verified with an anonymous registry token), which is what the ISO
   installer and the installed PC need. If it ever reverts to private:
   Packages → `fedora-bootc-konica206` → Package settings → Change visibility →
   **Public**. Alternatively keep it private and configure registry
   authentication deliberately.
4. **Package linking:** the first push links the package to this repository
   automatically. If not, link it in the package settings.
5. **Artifact retention:** the ISO workflow uses 30 days; adjust in the
   workflow or repository settings if you need longer.

Useful CLI checks:

```bash
gh workflow list --repo vinod2807/fedora-bootc-konica206
gh run list --repo vinod2807/fedora-bootc-konica206
gh run download <run-id> --repo vinod2807/fedora-bootc-konica206
```

To make the package public with a token that has package administration
permission (the GitHub CLI keyring token used here does **not** have
`write:packages`, so `gh auth refresh -s write:packages` or the web UI is
required):

```bash
gh api --method PATCH \
  /user/packages/container/fedora-bootc-konica206 \
  -f visibility=public
```

The workflow’s `GITHUB_TOKEN` cannot change package visibility; the web UI step
is the reliable path.

---

## Security notes

- No passwords, SSH keys, tokens, or personal credentials are in the image.
- The printer service runs as a dedicated unprivileged user in group `lp`;
  USB access is limited by the udev rule to the printer’s vendor/product ID.
- No vendor-owned files are committed, baked in, or uploaded.
- The ISO workflow only reads the registry and writes workflow artifacts; it
  never writes to a physical disk.
- Workflows use least-privilege permissions and pin third-party actions to
  commit SHAs.
