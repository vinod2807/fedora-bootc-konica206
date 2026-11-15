# Duplex back-side orientation: `Duplex=` vs `sides=` on `konica206uri`

Date: 2026-11-15. Applies to `fedora-bootc-konica206` image `sha256:150309e3…`
(commit `95e4d2b`).

## Symptom

Printing a 2-page A4 portrait PDF **duplex long-edge** to the legacy proxy
queue `konica206uri`:

- **pdfcraft** (IPP client, `sides=two-sided-long-edge`): back side correct.
- **Papers / Document Viewer** (PPD-only clients, `Duplex=DuplexNoTumble`):
  back side printed upside down.

Simplex output and `konica206-classic` (USB) were unaffected.

## Root cause

The host chain for the proxy queues is:

```
application/pdf -> pdftopdf -> gstoraster (image/urf) -> ipp backend -> PAPPL app
```

`cupsd` does **not** translate the PPD option `Duplex=DuplexNoTumble` into the
IPP attribute `sides=two-sided-long-edge`. `scheduler/ipp.c:apply_printer_defaults()`
explicitly skips adding `sides` when a `Duplex` attribute is present. `pdftopdf`
rotates the back side of a duplex sheet **only** when it sees `sides=two-sided-*`;
with only `Duplex=` it leaves the pages upright.

Downstream, the Legacy Printer Application receives `image/urf` with
`cupsBackSideOrientation=Normal` (because `*cupsUrfSupported: ...DM1...`), so
neither `gstoraster` nor the app rotates anything. The result depends entirely
on whether `pdftopdf` pre-rotated the verso.

The classic USB queue avoids this because its chain renders to CUPS raster
(`-sDEVICE=cups`), where `gstoraster` is given
`-scupsBackSideOrientation=Rotated` from `*cupsBackSide: Rotated` and rotates
the back side itself.

## Fix

1. New script `scripts/pdf-duplex-shim` (installed as
   `/usr/libexec/konica206/pdf-duplex-shim`). It appends the matching
   `sides=` value (`DuplexNoTumble` → `two-sided-long-edge`,
   `DuplexTumble` → `two-sided-short-edge`) when the job has `Duplex=` but no
   `sides=`, then runs `pdftopdf` → `gstoraster` (image/urf). IPP-style and
   simplex jobs pass through unchanged.

2. New PPD variant `konica206-app.ppd`, generated in the Containerfile from
   `konica206.ppd` by adding:

   ```
   *cupsFilter2: "application/pdf image/urf 5 /usr/libexec/konica206/pdf-duplex-shim"
   ```

   This makes the shim the cheapest `application/pdf` conversion for the proxy
   queues, so both request styles produce identical Apple Raster.

3. `scripts/ensure-legacy-queue` now uses `konica206-app.ppd` for the
   `konica206uri` and `konica206uri-ppd` queues. The classic queue keeps
   `konica206.ppd` (no shim), since adding `sides=` there would rotate twice.

## Why not upstream `konica-retrofit`

This is image-level CUPS plumbing (PPD filter, systemd queue creation, bootc
image build). `konica-retrofit` is the upstream printer-data repo and contains
no proxy queues or image build, so the workaround belongs in
`fedora-bootc-konica206`.

## Verification

Offline (probe queue + socket sink + URF decode + ink IoU):

- `Duplex=DuplexNoTumble` through the shim → URF byte-identical to the
  `sides=two-sided-long-edge` path (md5 `33cf0da4…`).
- Simplex (`Duplex=None`) through the shim → byte-identical to the base path.
- On real hardware, both Papers and pdfcraft printed duplex long-edge
  correctly to `konica206uri`.
- Classic queue and pdfcraft unchanged.
