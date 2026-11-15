# `konica206-classic` not printing: CUPS raster filter bypassed

Date: 2026-11-15. Applies to `fedora-bootc-konica206` (commit `19e75a1`).

## Symptom

Jobs sent to the direct USB queue `konica206-classic` (including duplex
long-edge) completed in CUPS with no errors and "0 pages" printed; the printer
produced no output.

## Root cause

The base PPD (`/usr/share/ppd/konica206/konica206.ppd`, used by
`konica206-classic`) declared both a `*cupsFilter` line and several
`*cupsFilter2` lines:

```
*cupsFilter:  "application/vnd.cups-raster 0 /usr/bin/konica-native"
*cupsFilter2: "image/jpeg image/jpeg 0 -"
*cupsFilter2: "image/png image/png 0 -"
*cupsFilter2: "image/urf image/urf 100 -"
```

When any `*cupsFilter2` entry is present, libcups (`ppd_update_filters`) discards
`*cupsFilter` and rebuilds the filter list from `cupsFilter2` only. As a result
the `application/vnd.cups-raster → konica-native` path was lost.

For a PDF job, CUPS selected the chain:

```
pdftopdf → gstoraster (-sDEVICE=appleraster, image/urf, cupsBackSideOrientation=Normal)
        → image/urf passthrough (-) → usb backend
```

`konica-native` never ran, so the job was never encoded into the printer's
245igdi/GDI stream. Raw Apple Raster URF was sent to the USB device, which the
printer ignored; the backend still exited successfully.

(Reference: `github.com/vinod2807/ubuntu-printing` documents the classic queue
using a direct device filter with `*cupsBackSide: Rotated` and duplex driven by
IPP `sides`/`Duplex=DuplexNoTumble`.)

## Fix

1. Added a dedicated PPD `ppd/konica206-classic.ppd` (installed to
   `/usr/share/ppd/konica206/konica206-classic.ppd`) that routes CUPS raster
   to the encoder via `cupsFilter2` only:

   ```
   *cupsFilter2: "application/vnd.cups-raster application/vnd.konica206 0 /usr/bin/konica-native"
   *cupsBackSide: Rotated
   ```

   (No `image/urf` passthrough, so the chain must produce the `konica-native`
   device stream for the USB backend.)

2. `scripts/ensure-classic-queue` now uses `konica206-classic.ppd`.
3. `Containerfile` installs `konica206-classic.ppd` and includes it in the
   image's PPD checks.

The proxy queues (`konica206uri`, `konica206uri-ppd`, and the native `konica206`
CUPS queue) keep using `konica206.ppd`/`konica206-app.ppd`, which deliver
`image/urf` to the PAPPL (IPP) backends.

## Verification

- A duplex long-edge test job to `konica206-classic` ran
  `pdftopdf → gstoraster → konica-native → usb` with all stages exiting
  successfully and the `konica-native` filter present in the chain.
- `konica206uri`/`konica206-app.ppd` behavior unchanged.

## Why not `konica-retrofit`

This is image/CUPS queue plumbing in `fedora-bootc-konica206` (queue PPD and
setup). `konica-retrofit` is the upstream printer-data repo and does not define
these CUPS queues.