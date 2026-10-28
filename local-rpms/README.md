# Local vendor RPMs

Anything placed in this directory is installed into the image at build time:

```
local-rpms/*.rpm  ->  dnf install -y local-rpms/*.rpm
```

This exists for packages that cannot be fetched automatically because the
vendor blocks scripted downloads.

## Epson Printer Utility for Linux

- Source: <https://download-center.epson.com/> → select **L3260 Series** →
  **Linux RPM(x64)** → *Epson Printer Utility for Linux* (currently 1.2.3).
- The resulting file is named like `epson-printer-utility-1.2.3-1.x86_64.rpm`.
- Epson's download centre and its API return **HTTP 403** to non-browser
  clients, so the build cannot download it. Put the file here, commit it (or
  copy the repo directory into the build context) and rebuild:

  ```bash
  cp epson-printer-utility-*.rpm local-rpms/
  git add local-rpms/*.rpm && git commit -m "vendor: add Epson Printer Utility RPM"
  ```

- The utility needs Qt5 and the `ecbd` backend, which its RPM pulls in; it
  shows ink levels and maintenance functions for the L3260. Printing itself is
  driverless and does not depend on it.
