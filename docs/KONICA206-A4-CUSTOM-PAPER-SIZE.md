# konica206 (PAPPL) “Incorrect paper size” / A4 emitted as CUSTOM

**Date:** 2026-11-15  
**Affected path:** `konica206` queue (CUPS → IPP → `konica206-native` PAPPL app on `:8001` → `konica-native` encoder → USB bizhub 206).  
**Repos:** `vinod2807/konica-native-musl`, `vinod2807/fedora-bootc-konica206` (integration)

## Symptom

Printing A4 (duplex long-edge, Tray 1 selected) to the **`konica206`** (native PAPPL) queue completed successfully in CUPS and PAPPL, but the printer panel showed:

> **CAUTION**  
> **INCORRECT PAPER SIZE**  
> **CHANGE 1 A4 □ → 1 [□]**

(Tray 1 was set/loaded as A4.) The same A4 duplex job printed correctly via **`konica206-classic`** (direct USB, CUPS raster → `konica-native`), confirming the printer/tray/media were fine and isolating the issue to the native/PAPPL pipeline.

## Observations

- **CUPS/PAPPL:** jobs completed (`successful-ok`, PAPPL `job-impressions-completed`, raster pages **4961×7016×8 sGray**, A4@600dpi) but the device rejected/held the job with the panel size error.
- **Capture** (with `KONICA_CAPTURE_DIR` on `konica206-native`, job 10 / `10-in.ras`, `10-out.prn`):
  - Raster page size: **595×841 pt**, pixel dimensions **4961×7016** (A4).
  - Encoder output (PJL): `@PJL SET PAPER=CUSTOM`, `@PJL SET PAPERWIDTH=4958`, `@PJL SET PAPERLENGTH=7008`, `@PJL SET MEDIASOURCE=AUTO`, `@PJL SET RESOLUTION=600` (duplex/binding as requested).

## Root cause

`konica-native` (encoder, `konica-native-musl`) derives `PAPER`/`PAPERWIDTH`/`PAPERLENGTH` (and image geometry) from the raster header **page size in points** via an exact table match (A4 = `595×842`). The builtin renderer in `konica206-native-alpine` produced a raster header reporting A4 as **595×841 pt** (1 pt short in height). With no exact match, the encoder classified the page as **CUSTOM** (`4958×7008` @600dpi for 595×841), so the printer saw a non-A4/custom size request for an A4 tray and raised “INCORRECT PAPER SIZE”.

> Note: `MEDIASOURCE` is emitted as `AUTO` by the encoder regardless of tray selection; the observed failure was driven by the **CUSTOM paper size**, not media source.

## Fix

**`vinod2807/konica-native-musl`** — commit [`f9e5244`](https://github.com/vinod2807/konica-native-musl/commit/f9e5244) (“Accept +/-1 point tolerance when matching page size to named paper”), `src/encode.c` `page_geometry()`:

- Keep exact (and swapped orientation) matching.
- If no exact match, accept a named paper when **both point dimensions are within ±1** of a table entry (e.g. `595×841` → A4 `595×842`).
- On match, emit the named paper’s geometry (`PAPER=A4`, `PAPERWIDTH=4958`, `PAPERLENGTH=7016`, correct `Xd/Yd`) instead of `CUSTOM`.

This makes the encoder tolerant of common rounding/truncation differences from raster producers.

## Deployment

- **Encoder repo:** fixed on `konica-native-musl` `main` (`f9e5244`).
- **Bootc image (`fedora-bootc-konica206`):** builds `konica-native-musl` from `main` (`KONICA_NATIVE_REF` resolved in CI) and installs `/usr/bin/konica-native`. A rebuild + `bootc upgrade` + reboot is required to deploy the fix to `konica206` (and classic) on a running system. Image build triggered: [fedora-bootc-konica206 actions run 43733644956](https://github.com/vinod2807/fedora-bootc-konica206/actions/runs/43733644956).

## Verification (post-deploy)

1. Print A4, Tray 1, duplex long-edge to `konica206` (e.g. `lp -d konica206 /usr/share/cups/data/default-testpage.pdf`).
2. Confirm no “INCORRECT PAPER SIZE” panel error and correct A4 output.
3. (Optional) capture: `PAPER=A4`, `PAPERWIDTH=4958`, `PAPERLENGTH=7016` in the emitted stream.

## Related

- `konica206-native-alpine` (PAPPL app) was pinned to post–Nov 5 state `3ea1c42` in the image; the mis-sized A4 header originated in that pipeline but is corrected by encoder tolerance.
- `konica206-classic` (direct USB) was unaffected by this CUSTOM-paper issue but had a separate vendor-data permission regression on reboot (fixed via `StateDirectoryMode=0755` / permissions handling in `fedora-bootc-konica206`).
