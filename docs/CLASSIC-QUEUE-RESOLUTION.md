# `konica206-classic` prints at 1/4 page size (300 dpi vs 600 dpi)

Date: 2026-11-15. Applies to `fedora-bootc-konica206` (commit `d356531`).

## Symptom

A duplex long-edge job sent to `konica206-classic` printed, but the content
appeared at roughly 1/4 of the page area (about half size in each dimension),
e.g. in one corner of the sheet.

## Root cause

The Konica Minolta bizhub 206 / 245igdi pipeline runs at 600 dpi. The PPDs
mapped the default `cupsPrintQuality` **Normal** to `300x300` dpi:

```
*cupsPrintQuality Normal: "<</HWResolution[300 300]>>setpagedevice"
*cupsPrintQuality High:   "<</HWResolution[600 600]>>setpagedevice"
```

With Normal selected by default, `gstoraster` produced a 300 dpi CUPS raster.
`konica-native` warned:

```
konica-native: raster is 300dpi; the device is 600dpi and the vendor forces RESOLUTION=600
```

but encoded the 300 dpi pixels into a 600 dpi device stream without scaling, so
the image rendered at half width and half height.

(Job 436 showed `gs ... -sDEVICE=cups ... -r300x300 ... -scupsBackSideOrientation=Rotated` and the filter chain
`pdftopdf → gstoraster → konica-native → usb` all exited successfully.)

## Fix

Set Normal quality to 600 dpi in both PPDs:

- `ppd/konica206.ppd`
- `ppd/konica206-classic.ppd`

```
*cupsPrintQuality Normal: "<</HWResolution[600 600]>>setpagedevice"
```

(Draft remains `300x150`, High remains `600x600`.) The app/proxy PPD
(`konica206-app.ppd`) is derived from `konica206.ppd` at image build time, so
it inherits the change.

Live remediation for an existing queue:

```bash
sudo lpadmin -p konica206-classic -P /usr/share/ppd/konica206/konica206-classic.ppd
# or, on a mutable path: sudo lpadmin -p konica206-classic -P /path/to/konica206-classic.ppd
```

## Verification

- Resend a duplex long-edge job with Normal/default quality to
  `konica206-classic`; content prints at full page size.
- Confirm: `lpoptions -p konica206-classic -l` shows `cupsPrintQuality: Draft *Normal High` and the PPD maps Normal to `600 600`.
