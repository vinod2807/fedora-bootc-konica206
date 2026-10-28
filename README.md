# Fedora bootc 44 — Labwc desktop + Konica Minolta bizhub 206

A custom [Fedora bootc](https://bootc.dev/) image for an older x86_64 Intel PC
(the target is an Intel Core i5 650). It provides:

- **Fedora bootc 44**, `linux/amd64`
- **Labwc** Wayland compositor, **Waybar** panel, **Foot** terminal
- A real graphical login path: **greetd** on VT1 → **tuigreet** → **labwc**
- NetworkManager, PipeWire/WirePlumber, portals, polkit, XWayland
- The **Konica Minolta bizhub 206** PAPPL printer application
  ([konica206-native-alpine](https://github.com/vinod2807/konica206-native-alpine))
  built for Fedora, with the
  [konica-native](https://github.com/vinod2807/konica-native-musl) C11
  device-stream encoder as the filter stage
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
| `systemd/` | Printer app, queue creation, and opt-in bootc update units |
| `udev/70-konica206.rules` | USB permissions for `132b:232b` (group `lp`, `uaccess`) |
| `greetd/config.toml` | tuigreet → labwc login session |
| `desktop/` | labwc autostart/environment and Waybar config/style |
| `scripts/install-vendor-data` | Post-install installer for the licensed Konica runtime data |
| `scripts/ensure-queue` | Creates the PAPPL queue when the printer is plugged in |
| `scripts/preflight` | Read-only diagnostic (`konica206-preflight`) |
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
   user (admin/wheel) and set a password in the installer. **No user or password
   is baked into the image.**
6. Reboot. greetd/tuigreet appears on VT1; log in with the user you created.

The installer pulls the image from GHCR. The GHCR package must be **public**
for an unauthenticated install, or you must provide registry credentials in the
installer environment. Making it public is the documented path.

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

---

## First boot and login

- **Graphical:** greetd starts on VT1, tuigreet asks for the user/password you
  created during installation, then launches `labwc`.
- **Panel:** Waybar autostarts at the top (`/etc/xdg/waybar/config`).
- **Terminal:** `foot` is installed. Labwc’s default keybindings/menu are
  available; if your build of labwc has no terminal binding, open a terminal
  from the desktop menu or press `Super+Enter` (labwc default where configured).
- **Text fallback:** `Ctrl+Alt+F2` gives a text login. From there, run `labwc`
  to start the Wayland session manually.
- **Audio:** PipeWire, WirePlumber and `pipewire-pulseaudio` are enabled for
  users. Use `wpctl status` / `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`.
- **Networking:** NetworkManager is enabled. Use `nmcli device status` and
  `nmcli connection up <name>`; Wi-Fi needs `NetworkManager-wifi` +
  `wpa_supplicant`, both installed.

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

`bootc upgrade` stages by default; it does **not** reboot. Check
`bootc upgrade --help` on the installed version before using any optional
flags; this repository does not rely on `--apply`.

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

### Automatic updates (optional, off by default)

The image ships `bootc-upgrade.service` and `bootc-upgrade.timer`, but the timer
is **not enabled**. To opt in:

```bash
sudo systemctl enable --now bootc-upgrade.timer
systemctl list-timers bootc-upgrade.timer
journalctl -u bootc-upgrade.service
```

The timer runs weekly with a random delay, stages the update, and logs to the
journal. It never reboots. Reboot when convenient:

```bash
sudo bootc status
sudo systemctl reboot
```

The trade-off: staging without rebooting is safe and predictable; the new
image is inactive until you reboot. If you want a fully unattended update,
enable the timer **and** schedule your own reboot window; this repository does
not do that for you.

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

```bash
# Optional CUPS proxy queue (CUPS is installed but not enabled by default)
sudo systemctl enable --now cups.service
sudo lpadmin -p konica206-ipp -E \
  -v ipp://127.0.0.1:8001/ipp/print/konica206 -m everywhere
sudo lpadmin -p konica206-ipp -o printer-error-policy=retry-job
lp -d konica206-ipp /path/to/test.pdf
```

Print a **PDF**, not PostScript (the driver deliberately does not advertise
`application/postscript`). A real USB print is required to confirm paper
output; compilation and the offline tests cannot prove the printer works.

Troubleshooting:

```bash
journalctl -u konica206-native -b
systemctl status konica206-native konica206-queue
konica206-preflight
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
| Containerfile builds `linux/amd64` | Requires GitHub Actions run |
| Upstream printer `make check` / `make check-native` | Requires GitHub Actions run |
| `konica-native` vendor-free test suite | Requires GitHub Actions run |
| Container smoke test (packages, units, binary versions, no vendor files) | Requires GitHub Actions run |
| Weekly push to GHCR + traceable tags | Requires GitHub Actions run |
| ISO El Torito BIOS metadata | Requires GitHub Actions run |
| ISO boots under QEMU SeaBIOS to Linux userspace | Requires GitHub Actions run |
| Full BIOS installation on real hardware | **Not tested** — physical PC required |
| Graphical login (greetd → labwc → Waybar) on real hardware | **Not tested** — physical/QEMU desktop test required |
| Real USB printing on bizhub 206 | **Not tested** — printer + licensed runtime data required |
| Printer works with vendor assets installed | **Not tested** — requires the licensed data and paper |

Do not treat “ISO file exists” or “compilation succeeded” as proof of a working
BIOS install or a working printer.

---

## Repository settings

After the first push/build:

1. **Actions enabled:** Settings → Actions → General → Allow all actions.
2. **Workflow permissions:** Settings → Actions → General → Workflow
   permissions → **Read and write permissions** (the workflows also declare
   least-privilege `permissions:` blocks; image push needs `packages: write`).
3. **GHCR package visibility:** Packages → `fedora-bootc-konica206` → Package
   settings → Change visibility → **Public**. This is required for the ISO
   installer and the installed PC to pull anonymously. Alternatively keep it
   private and configure registry authentication deliberately.
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
permission:

```bash
gh api --method PATCH \
  /user/packages/container/fedora-bootc-konica206/visibility \
  -f visibility=public
```

The workflow’s `GITHUB_TOKEN` may not have permission to change package
visibility; the web UI step is the reliable path.

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
