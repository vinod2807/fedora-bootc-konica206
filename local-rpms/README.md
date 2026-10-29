# Vendor RPMs

Anything placed in this directory is installed into the image at build time:

```
local-rpms/*.rpm  ->  dnf install -y local-rpms/*.rpm
```

This exists for packages that cannot be fetched automatically because the
vendor blocks scripted downloads.

## Epson Printer Utility for Linux

| | |
|---|---|
| File | `epson-printer-utility-1.2.3-1.x86_64.rpm` |
| sha256 | `58f992ea28f4b2b010ba0a4b1bf213deeabf7ad02cd9927de19db0676c76d489` |
| Source | <https://download-center.epson.com/> → **L3260 Series** → **Linux RPM(x64)** |
| Vendor | Seiko Epson Corporation, package dated 2026-05-12 |

Epson's download centre and its API answer non-browser clients with **HTTP 403**
(Akamai), so the build cannot fetch this file. It is therefore committed here.

What the build does beyond `dnf install`:

- **Scriptlets are skipped** (`--setopt=tsflags=noscripts`). The RPM's `%post`
  launches the `ecbd` daemon in the foreground; inside a container build that
  call never returns, so a plain `dnf install` hangs the build forever.
- `qt5-qtbase-gui` is installed explicitly — the RPM declares no Qt5
  dependency, but the binary links `libQt5Core/Gui/Widgets`.
- `/usr/share/applications/epson-printer-utility.desktop` is symlinked to the
  vendor's `/opt/epson-printer-utility/epson-printer-utility.desktop`, because
  the RPM keeps its menu entry inside `/opt` where no XDG menudir looks.

`ecbd` is Epson's backend daemon: it is required only for **USB-attached**
Epson printers. The network `EPSON_L3260` queue is driverless and the utility
queries a network printer directly, so the daemon is left disabled. On a machine
with an Epson printer on USB, enable it manually:

```bash
sudo systemctl enable --now ecbd.service
sudo semodule -i /usr/lib/epson-backend/epson_pol.pp   # if SELinux blocks it
```

The utility shows ink levels / runs head cleaning and nozzle checks for the
L3260. Printing and scanning do **not** require it.

### Updating

Replace the file with a newer vendor build, update the sha256 above, commit.
The RPM is redistributed unmodified under Epson's own licence
(`/usr/share/doc/COPYING.EPSON`) and is not covered by this repository's
licence; remove it from the repository if you would rather install it locally
only.
