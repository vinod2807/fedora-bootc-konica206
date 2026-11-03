# Konica Minolta bizhub 206 on Fedora bootc

This image runs the PAPPL printer application from
[konica206-native-alpine](https://github.com/vinod2807/konica206-native-alpine)
and the pure-C11 encoder from
[konica-native-musl](https://github.com/vinod2807/konica-native-musl).

```
IPP client -> PAPPL -> Ghostscript (builtin renderer) -> konica-native -> libusb -> bizhub 206
```

`konica-native` replaces the proprietary `245igdirf` binary as the device-stream
stage, so no glibc vendor filter or private libcups is required. The PAPPL
application still uses libcups’ raster API and libusb, both from Fedora RPMs.

## Installed pieces

| Piece | Path |
|---|---|
| PAPPL app | `/usr/bin/konica206-native` |
| Manual sender (no PAPPL/CUPS) | `/usr/bin/konica-send` |
| PDF → stream renderer | `/usr/bin/konica-render` |
| C11 encoder | `/usr/bin/konica-native` |
| systemd service | `/usr/lib/systemd/system/konica206-native.service` |
| queue helper | `/usr/libexec/konica206/ensure-queue` |
| vendor data installer | `/usr/bin/konica206-install-vendor-data` |
| preflight | `sudo /usr/bin/konica206-preflight` |
| udev rule (add / queue creation) | `/usr/lib/udev/rules.d/70-konica206.rules` |
| USB presence watcher | `/usr/local/bin/konica-cups-watch.sh` |
| watcher udev rule | `/usr/lib/udev/rules.d/71-konica206-usb-presence.rules` |
| watcher units | `konica-cups-watch.service`, `konica-cups-watch.timer` |
| legacy konica206uri app | `legacy-printer-app.service` (`/usr/bin/legacy-printer-app`, port 8000) |
| legacy queue helper | `/usr/libexec/konica206/ensure-legacy-queue` |
| Wine/Adobe PS MIME rule | `/etc/cups/wineps.convs` |
| Wine/Adobe PS guard | `/usr/local/sbin/check-wineps-route.sh` |
| build commit stamps | `/usr/share/konica206/{app,native,retrofit}-commit` |

The app runs as the system user `konica`, group `konica`, supplementary group
`lp`. It is **not** run as root and has no shell login. PAPPL state is kept in
`/var/lib/konica206`; the service uses `StateDirectory=konica206`.

## Build and tests (CI, no printer needed)

The builder stage runs:

```bash
make -C konica206-native-alpine          # app, sender, renderer, tests
make -C konica206-native-alpine check    # 8192-byte chunking + PPD parser
make -C konica206-native-alpine check-native  # PAPPL job path, stand-in filter

make -C konica-native-musl               # encoder
make -C konica-native-musl check         # reader vs libcups, CMM table,
                                         # geometry, MEDIATYPE, failure modes
```

`make check-native` uses a stand-in filter by default and does not need the
printer or vendor data. The encoder’s `check-lutgen`, `check-geometry` and
`check-mediatype` tests skip cleanly when the vendor runtime data is not
installed; `make check` still exercises the vendor-free reader and failure-mode
tests.

These tests prove compilation and the offline job path. They **do not** prove
that paper comes out.

> **Verified on hardware:** a real A4 simplex job sent to the `konica206`
> queue from the installed desktop printed correctly (2026-10-28).

## Queue

The service listens on loopback only:

```
ipp://127.0.0.1:8001/ipp/print/konica206
```

`konica206-queue.service` runs at boot, and is also requested by the udev rule
when the device is plugged in. It:

1. waits for the PAPPL server;
2. reads the printer serial from sysfs (`/sys/bus/usb/devices/*/serial`) for
   `132b:232b`;
3. creates the `konica206` queue if it does not already exist;
4. creates (or refreshes) the local CUPS queue `konica206` with the shipped
   PPD shim and forces `PageSize=A4`, `Duplex=None`;
5. exits 0 when no printer is attached.

Manual:

```bash
sudo systemctl start konica206-queue.service
konica206-native printers -u ipp://localhost:8001
konica206-native status   -u ipp://localhost:8001
```

If the serial is not exposed by the device, set it explicitly:

```bash
sudo KONICA_SERIAL=YOURSERIAL /usr/libexec/konica206/ensure-queue
```

The native application and the legacy `konica206uri` application both use USB
interface 1, but only when printing: each opens the device per job, so one job
at a time drives the printer. Do not run both queues concurrently in a way
that interleaves jobs on the same physical sheet stack.

## Legacy konica206uri stack

The image also installs the legacy stack from
[konica-retrofit](https://github.com/vinod2807/konica-retrofit), kept as a
second, independent path to the same printer:

| Piece | Path |
|---|---|
| Legacy Printer Application | `/usr/bin/legacy-printer-app` (pappl-retrofit 1.0b2) |
| retrofit PPD driver | `/usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd` |
| chunked USB backend | `/usr/local/libexec/konica-backend/usb` |
| service drop-in (port 8000, `PPD_PATHS`) | `/etc/systemd/system/legacy-printer-app.service.d/90-konica206uri.conf` |
| queue service | `/usr/lib/systemd/system/konica206uri-queue.service` |
| queue helper | `/usr/libexec/konica206/ensure-legacy-queue` |
| state/spool tmpfiles | `/usr/lib/tmpfiles.d/konica206uri.conf` |

```
IPP client -> CUPS queue konica206uri -> Legacy Printer Application :8000
           -> pappl-retrofit raster -> /usr/bin/konica-native -> USB backend -> bizhub 206
```

The retrofit full-bleed PPD is used unchanged except for two build-time edits:
its vendor filter `/usr/local/lib/konica/.../245igdirf` is replaced by the open
`/usr/bin/konica-native`, and the default duplex mode is pinned to `None`.
`*ImageableArea` must stay equal to `*PaperDimension` for every size: an inset
area makes the encoder's raster smaller than the sheet the device declares and
ghosting appears. The build fails if the PPD filter line moves upstream.

`konica206uri-queue.service` runs at boot and on every USB add. It waits for
the application, adds the `konica206uri` printer with
`cups:usb://KONICA%20MINOLTA/206?serial=<serial>&interface=1`, and creates the
two CUPS proxy queues `konica206uri` and `konica206uri-ppd` with the same
pass-through shim PPD as the native queue (A4, simplex defaults). The chunked
USB backend is used because the bizhub 206 re-enumerates when a single bulk
write is too large.

Manual checks:

```bash
systemctl status legacy-printer-app.service konica206uri-queue.service
legacy-printer-app printers
lpstat -p konica206uri konica206uri-ppd
```

Jobs through the legacy queues need the same vendor runtime data as the native
queue (see below); without it the encoder fails the job before sending
anything.

## konica-retrofit integration

The image consumes distro-neutral assets from
[konica-retrofit](https://github.com/vinod2807/konica-retrofit), pinned by
`KONICA_RETROFIT_REF` and stamped into
`/usr/share/konica206/retrofit-commit`:

- **USB queue-presence watcher** — `konica-cups-watch.service` reconciles the
  `konica206`, `konica206uri` and `konica206uri-ppd` CUPS proxy queues with the
  real sysfs state at boot, on udev add/remove, and every five minutes via
  `konica-cups-watch.timer`. It disables the queues with the
  `konica-usb-absent` marker when the printer is off and re-enables only queues
  carrying that marker, so a deliberate manual pause is never undone. This
  complements the add-only `70-konica206.rules`, which cannot disable anything
  on remove.
- **Wine/Adobe PostScript rule** — `/etc/cups/wineps.convs` retypes
  `application/vnd.adobe-reader-postscript` to plain `application/postscript`,
  avoiding the broken `gstoraster` path. The read-only
  `/usr/local/sbin/check-wineps-route.sh` verifies the rule and filter chain.

The upstream scripts are patched at build time for the native queue name, and
the build fails if the patched lines move upstream.

Manual checks:

```bash
systemctl status konica-cups-watch.service konica-cups-watch.timer
sudo /usr/local/bin/konica-cups-watch.sh check
sudo /usr/local/sbin/check-wineps-route.sh
```

## USB permissions

The rule is intentionally narrow:

```
SUBSYSTEM=="usb", ATTR{idVendor}=="132b", ATTR{idProduct}=="232b",
  MODE="0660", GROUP="lp", TAG+="uaccess",
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="konica206-queue.service"
```

- The service user is in group `lp`.
- `uaccess` gives the logged-in desktop user access for `lsusb`/`konica-send`.
- No world-writable device node or broad `MODE="0666"` rule is used.

## Vendor runtime data and licensing

The encoder requires three Konica Minolta files at a fixed compiled-in path.
Because `/usr` is immutable on bootc and `/usr/local` is a normal directory in
the base image, the image ships this symlink:

```
/usr/local/lib/konica  ->  /var/lib/konica206/vendor
```

so the encoder resolves:

```
/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/COPA.DEFAULT.600x600.hft
/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sRGB.icm
/usr/local/lib/konica/KonicaMinolta/245igdi/Profiles/sGrayInv.icm
```

while the files physically live in persistent, writable state:

```
/var/lib/konica206/vendor/KonicaMinolta/245igdi/...
```

The upstream `vendor/NOTICE` says these remain Konica Minolta property and are
not covered by the repository license. Redistributing them requires the
vendor’s permission. Therefore:

- this repository contains no vendor files;
- the container build copies only compiled binaries from the builder stage, not
  `vendor/`;
- public images and public ISO artifacts contain no vendor files;
- you supply the files after installation from your own licensed driver copy.

```bash
sudo konica206-install-vendor-data /path/to/driver-copy
sudo konica206-preflight
```

Accepted input: a directory containing
`KonicaMinolta/245igdi/{Halftones,Profiles}`, or `245igdi/{Halftones,Profiles}`,
or `{Halftones,Profiles}`, or a `.tar`, `.tar.gz`, `.tgz`, `.tar.xz`, `.zip`
archive. The script copies only the required three files plus optional extra
`.icm` profiles and the 1200×600 screen. It prints file names, never contents.

The PPD is optional for the PAPPL side. Page geometry, the tray map and the
duplex back-side rule are compiled into the application, and this repository
does **not** install or redistribute a vendor PPD.

For the CUPS queue the image ships its **own** hand-written PPD
(`/usr/share/ppd/konica206/konica206.ppd`). It contains no Konica data: it
describes the ten media sizes the application itself advertises (A3, A4, A5,
A6, ISO B4, ISO B5, Letter, Legal, Executive, Statement) with realistic
4.2 mm margins, and simplex + long-edge/short-edge duplex. The alternatives are
the CUPS-generated `*.Borderless` names, which the hardware does not support.

If the runtime data is missing:

- the service starts;
- each job aborts before writing to stdout;
- the journal says the filter produced no output / the runtime data is missing;
- nothing is sent to the printer (no half-written PJL job).

The printer feature is therefore **not fully baked in out of the box**.

## Test print

A real print is the only proof. Prepare a PDF and use either PAPPL’s IPP
endpoint directly or a CUPS proxy queue.

### CUPS queue (created automatically)

`konica206-queue.service` creates a local queue named `konica206` that relays to
the PAPPL endpoint above, using the image's own PPD shim:

```bash
lpstat -v konica206
lpoptions -p konica206 -l        # ten real page sizes, duplex options
lp -d konica206 /path/to/test.pdf                 # A4, simplex (defaults)
lp -d konica206 -o Duplex=DuplexNoTumble file.pdf # long-edge duplex
lp -d konica206 -o PageSize=A3 file.pdf
```

Create or repair it by hand:

```bash
sudo systemctl start konica206-queue
sudo lpadmin -p konica206 -E \
  -v ipp://127.0.0.1:8001/ipp/print/konica206 \
  -P /usr/share/ppd/konica206/konica206.ppd \
  -o printer-error-policy=retry-job
sudo lpadmin -p konica206 -o PageSize=A4 -o Duplex=None
```

Print PDF, not PostScript. The application deliberately does not advertise
`application/postscript`; direct IPP PS jobs are rejected, while the CUPS queue
converts PS to PDF before relaying.

### Direct IPP check

If `cups-ipp-utils` is available:

```bash
ipptool -tv ipp://127.0.0.1:8001/ipp/print/konica206 get-printer-attributes.test
```

## Offline render check (no paper)

`konica-render` runs the renderer and filter but never opens USB:

```bash
konica-render /path/to/test.pdf /var/tmp/test.prn
```

This is useful for checking that the vendor runtime data is installed and that
the filter produces a PJL/JBIG stream. It does not prove the printer accepts it.

## Troubleshooting

```bash
systemctl status konica206-native konica206-queue
journalctl -u konica206-native -b --no-pager
sudo konica206-preflight
lsusb -d 132b:232b
lsusb -d 132b:232b -v | grep -i serial
konica206-native printers -u ipp://localhost:8001
```

| Symptom | Check |
|---|---|
| Queue missing | printer attached? `systemctl start konica206-queue`; serial visible? |
| Job aborts, no paper | `sudo konica206-preflight`; install vendor runtime data |
| “permission denied” on USB | udev rule loaded (`udevadm control --reload-rules`), `konica` in `lp`, replug |
| `Unable to claim USB interface: Resource busy` | `usblp` grabbed the device; the image blacklists it (`/etc/modprobe.d/90-konica206-usblp.conf`) — reboot or `rmmod usblp` |
| `konica206-queue` failed: “Printer name already exists” | udev re-trigger race; fixed by the idempotent `ensure-queue` script, safe to `systemctl restart` |
| App starts but no queue | `konica206-native printers -u ipp://localhost:8001` |
| CUPS queue disabled | re-create with `lpadmin -E`; check `cupsaccept` |
| Duplex wrong | app uses compiled-in `cupsBackSide: Rotated`; file a test case |
| Service restarts | expected: `Restart=always`; check `journalctl` and state dir ownership (`/var/lib/konica206`) |

After changing the udev rule:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb
```

## What still needs real-hardware verification

1. A real USB print on the bizhub 206 with the licensed 245igdi data installed.
2. Whether PAPPL’s idle status polling is accepted by this printer.
3. PPD option names (resolution/tray/media) against the real device; the app
   compiles in sensible defaults and does not need a PPD.
4. All trays/duplex combinations on paper.
