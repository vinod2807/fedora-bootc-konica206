# Vendor runtime data permissions: konica-native cannot load halftone

Date: 2026-11-15. Applies to `fedora-bootc-konica206` (commit `f80c9bc`).

## Symptom

Print jobs to `konica206-classic` (and any path running `konica-native` as a
CUPS filter) failed with:

```
konica-native: cannot load halftone screen
/usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/COPA.DEFAULT.600x600.hft
PID ... (/usr/bin/konica-native) stopped with status 1.
Sent 0 bytes...
```

The filter chain was correct (e.g. `gstoraster` → `konica-native` → usb
backend) but the encoder aborted before producing output.

## Root cause

`/usr/local/lib/konica` symlinks to `/var/lib/konica206/vendor` (persistent
vendor runtime data). `/var/lib/konica206` was mode `0750` owned by
`konica:konica`, so it was not traversable by unprivileged users. CUPS filters
run as an unprivileged user (`lp`), therefore `konica-native` could not read the
halftone/profile files even though the files themselves were world-readable.

The `konica206-vendor-data` oneshot exits early when data is already present,
so a restrictive directory mode persisted across reboots/upgrades until fixed.

## Fix

- `scripts/install-vendor-data`: after installing files, ensure the vendor path
  is traversable/readable:
  - `chmod 0755 /var/lib/konica206 /var/lib/konica206/vendor`
  - `chmod -R a+rX /var/lib/konica206/vendor`
- `scripts/konica-vendor-data-boot`: when vendor data is already present,
  ensure the same permissions (instead of exiting without correction).

## Immediate remediation (live system)

```bash
sudo chmod 755 /var/lib/konica206 /var/lib/konica206/vendor
sudo chmod -R a+rX /var/lib/konica206/vendor
```

`/var` is persistent, so this holds until corrected by the updated scripts.

## Verification

```bash
sudo -u lp test -r /usr/local/lib/konica/KonicaMinolta/245igdi/Halftones/COPA.DEFAULT.600x600.hft
echo $?   # expect 0
```

Reprint the job; `konica-native` should run without the halftone-load error.
