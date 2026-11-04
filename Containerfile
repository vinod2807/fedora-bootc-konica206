# syntax=docker/dockerfile:1.7
#
# Fedora bootc image with:
#   - Labwc / Waybar / Foot Wayland desktop + greetd/tuigreet login
#   - Konica Minolta bizhub 206 PAPPL printer application
#   - konica-native (C11) device-stream encoder
#   - konica-retrofit CUPS integration assets (USB queue-presence watcher and
#     the Wine/Adobe PostScript MIME rule), retargeted at the native queue
#   - the legacy konica206uri stack (pappl-retrofit Legacy Printer Application
#     plus the konica206uri and konica206uri-ppd CUPS queues), driven from the
#     retrofit PPD through the open konica-native encoder
#   - authenticated Samba folder and CUPS printer sharing
#
# Vendor-owned runtime data (halftone screen + ICC profiles) is deliberately
# NOT copied into this image. See docs/PRINTER.md and scripts/install-vendor-data.
#
# Build:
#   podman build --platform linux/amd64 -t localhost/fedora-bootc-konica206 .
#
# The two printer source refs default to the upstream default branches. The
# weekly GitHub workflow resolves each branch to a commit SHA and passes the
# SHAs as build args, so every published image is traceable while the next
# weekly run still picks up new upstream commits.
#
# The base follows the moving :latest tag on purpose: each weekly build picks
# up the current Fedora release, so a new Fedora major version lands a few days
# after GA without touching this file. The trade-off is that a Fedora major
# version jump is unattended; the bootloader keeps the previous deployment and
# the GRUB menu waits, so a bad jump can be rolled back by hand. To stop
# following the release train, pin both args (e.g. :45) and bump them by hand.

ARG BASE_IMAGE=quay.io/fedora/fedora-bootc:latest
ARG BUILDER_IMAGE=quay.io/fedora/fedora:latest

ARG KONICA_APP_REPO=https://github.com/vinod2807/konica206-native-alpine.git
ARG KONICA_NATIVE_REPO=https://github.com/vinod2807/konica-native-musl.git
ARG KONICA_RETROFIT_REPO=https://github.com/vinod2807/konica-retrofit.git
ARG KONICA_APP_REF=main
ARG KONICA_NATIVE_REF=main
ARG KONICA_RETROFIT_REF=main

# ZapFast version to install from GitHub releases. Bump for a new release; the
# weekly workflow resolves the latest tag automatically.
ARG ZAPFAST_VERSION=v0.20.1

# Storytold Crafting Apps versions. Bump for new releases; the weekly workflow
# resolves the latest tags automatically.
ARG PDFCRAFT_VERSION=v0.18.0
ARG WORDCRAFT_VERSION=v0.15.0
ARG DECKCRAFT_VERSION=v0.15.0
ARG GRIDCRAFT_VERSION=v0.16.0

# ---------------------------------------------------------------------------
# Build the printer application and the native encoder.
# ---------------------------------------------------------------------------
FROM ${BUILDER_IMAGE} AS printer-builder

ARG KONICA_APP_REPO
ARG KONICA_NATIVE_REPO
ARG KONICA_RETROFIT_REPO
ARG KONICA_APP_REF
ARG KONICA_NATIVE_REF
ARG KONICA_RETROFIT_REF

ENV LANG=C.UTF-8

RUN dnf install -y --setopt=install_weak_deps=False \
        ca-certificates \
        cups-devel \
        gcc \
        ghostscript \
        git \
        libusb1-devel \
        make \
        pappl-devel \
        pkgconf-pkg-config \
        findutils \
        diffutils \
        python3 \
    && dnf clean all

WORKDIR /src

RUN set -eux; \
    git clone --depth 1 "${KONICA_APP_REPO}" app; \
    git -C app fetch --depth 1 origin "${KONICA_APP_REF}"; \
    git -C app checkout --detach FETCH_HEAD; \
    git -C app rev-parse HEAD > /src/app-commit

RUN set -eux; \
    git clone --depth 1 "${KONICA_NATIVE_REPO}" native; \
    git -C native fetch --depth 1 origin "${KONICA_NATIVE_REF}"; \
    git -C native checkout --detach FETCH_HEAD; \
    git -C native rev-parse HEAD > /src/native-commit

# konica-retrofit is a legacy CUPS/legacy-printer-app kit. This image consumes
# both its hardening pieces (the USB queue-presence watcher and the Wine/Adobe
# PostScript retype rule) and the assets of its legacy konica206uri stack: the
# full-bleed PPD, and the chunked USB backend that keeps the bizhub 206 from
# dropping off the bus on large writes.
RUN set -eux; \
    git clone --depth 1 "${KONICA_RETROFIT_REPO}" retrofit; \
    git -C retrofit fetch --depth 1 origin "${KONICA_RETROFIT_REF}"; \
    git -C retrofit checkout --detach FETCH_HEAD; \
    git -C retrofit rev-parse HEAD > /src/retrofit-commit

COPY cups/wineps.convs /tmp/retrofit-wineps.convs
COPY udev/71-konica206-usb-presence.rules /tmp/retrofit-usb-presence.rules
COPY scripts/ensure-legacy-queue /tmp/retrofit-ensure-legacy-queue
COPY systemd/konica206uri-queue.service /tmp/retrofit-konica206uri-queue.service
COPY systemd/legacy-printer-app.service.d/90-konica206uri.conf /tmp/retrofit-legacy-app.conf
COPY systemd/tmpfiles.d/konica206uri.conf /tmp/retrofit-konica206uri.tmpfiles.conf

# Assemble and patch the retrofit files in the builder stage, laid out exactly
# as they must appear in the final image. The final stage then needs a single
# COPY: each extra layer counts against Docker's 125-layer overlay2 limit, and
# the published image is already near it.
RUN set -eux; \
    root=/out/retrofit-root; \
    install -d "$root/etc/cups" \
               "$root/etc/systemd/system/legacy-printer-app.service.d" \
               "$root/usr/local/bin" \
               "$root/usr/local/sbin" \
               "$root/usr/local/libexec/konica-backend" \
               "$root/usr/local/share/konica-retrofit" \
               "$root/usr/lib/systemd/system" \
               "$root/usr/lib/tmpfiles.d" \
               "$root/usr/lib/udev/rules.d" \
               "$root/usr/libexec/konica206" \
               "$root/usr/share/konica206/legacy-ppd"; \
    sed 's/^QUEUES="konica206uri konica206uri-ppd"$/QUEUES="konica206 konica206uri konica206uri-ppd"/' \
        retrofit/konica-cups-watch.sh > "$root/usr/local/bin/konica-cups-watch.sh"; \
    grep -qx 'QUEUES="konica206 konica206uri konica206uri-ppd"' \
        "$root/usr/local/bin/konica-cups-watch.sh"; \
    sed 's#/etc/cups/ppd/konica206uri.ppd#/etc/cups/ppd/konica206.ppd#' \
        retrofit/check-wineps-route.sh > "$root/usr/local/sbin/check-wineps-route.sh"; \
    grep -q '/etc/cups/ppd/konica206.ppd' "$root/usr/local/sbin/check-wineps-route.sh"; \
    chmod 0755 "$root/usr/local/bin/konica-cups-watch.sh" \
               "$root/usr/local/sbin/check-wineps-route.sh"; \
    install -m 0644 retrofit/tests/min-ar.ps \
        "$root/usr/local/share/konica-retrofit/min-ar.ps"; \
    install -m 0644 retrofit/konica-cups-watch.service \
                    retrofit/konica-cups-watch.timer \
        "$root/usr/lib/systemd/system/"; \
    install -m 0644 /tmp/retrofit-wineps.convs \
        "$root/etc/cups/wineps.convs"; \
    install -m 0644 /tmp/retrofit-usb-presence.rules \
        "$root/usr/lib/udev/rules.d/71-konica206-usb-presence.rules"; \
    install -m 0644 /src/retrofit-commit \
        "$root/usr/share/konica206/retrofit-commit"; \
    install -m 0755 /tmp/retrofit-ensure-legacy-queue \
        "$root/usr/libexec/konica206/ensure-legacy-queue"; \
    install -m 0644 /tmp/retrofit-konica206uri-queue.service \
        "$root/usr/lib/systemd/system/konica206uri-queue.service"; \
    install -m 0644 /tmp/retrofit-legacy-app.conf \
        "$root/etc/systemd/system/legacy-printer-app.service.d/90-konica206uri.conf"; \
    install -m 0644 /tmp/retrofit-konica206uri.tmpfiles.conf \
        "$root/usr/lib/tmpfiles.d/konica206uri.conf"; \
    sed -e 's#^\*cupsFilter: .*#*cupsFilter: "application/vnd.cups-raster 0 /usr/bin/konica-native"#' \
        -e 's#^\*DefaultDuplex:.*#*DefaultDuplex: None#' \
        -e 's#^\*cupsManualCopies:.*#*cupsManualCopies: True#' \
        -e '/^\*OCM_resourceDir:/d' \
        retrofit/backup/var/lib/legacy-printer-app/ppd/KonicaMinolta-206-fullbleed.ppd \
        > "$root/usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd"; \
    grep -qxF '*cupsFilter: "application/vnd.cups-raster 0 /usr/bin/konica-native"' \
        "$root/usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd"; \
    grep -qxF '*DefaultDuplex: None' \
        "$root/usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd"; \
    ! grep -q '^\*OCM_resourceDir:' \
        "$root/usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd"; \
    gcc -O2 -std=gnu17 -Wall -Wextra \
        -o "$root/usr/local/libexec/konica-backend/usb" \
        retrofit/backup/source/konica-usb-backend/konica-usb-backend.c \
        $(pkg-config --cflags --libs libusb-1.0); \
    chmod 0755 "$root/usr/local/libexec/konica-backend/usb"; \
    test -x "$root/usr/local/libexec/konica-backend/usb"

# Upstream tests that need no printer, no USB device and no vendor runtime data.
# make check        -> chunking + PPD parser regression
# make check-native -> full PAPPL job path against a stand-in filter
RUN set -eux; \
    make -C /src/app -j"$(nproc)"; \
    make -C /src/app check

# check-native must not run as root (root would use the real service's PAPPL
# state file), so run that one test as an unprivileged builder user.
RUN set -eux; \
    useradd --create-home --shell /bin/bash tester; \
    runuser -u tester -- env HOME=/home/tester make -C /src/app check-native

# konica-native: reader/CMM/geometry/mediatype/failure-mode tests are vendor-free.
RUN set -eux; \
    make -C /src/native -j"$(nproc)"; \
    make -C /src/native check

# Collect only the binaries. The upstream clone (which contains a vendor/
# directory in the public source tree) is never copied into the final image.
RUN set -eux; \
    install -D -m 0755 /src/app/konica206-native /out/usr/bin/konica206-native; \
    install -D -m 0755 /src/app/konica-send     /out/usr/bin/konica-send; \
    install -D -m 0755 /src/app/konica-render   /out/usr/bin/konica-render; \
    install -D -m 0755 /src/native/konica-native /out/usr/bin/konica-native

# ---------------------------------------------------------------------------
# Final bootc image.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG KONICA_APP_REF=main
ARG KONICA_NATIVE_REF=main
ARG KONICA_RETROFIT_REF=main

# ZapFast version to install from GitHub releases. Bump for a new release; the
# weekly workflow can resolve the latest tag automatically.
ARG ZAPFAST_VERSION=v0.20.1

# Storytold Crafting Apps versions. Bump for new releases; the weekly workflow
# can resolve the latest tags automatically.
ARG PDFCRAFT_VERSION=v0.18.0
ARG WORDCRAFT_VERSION=v0.15.0
ARG DECKCRAFT_VERSION=v0.15.0
ARG GRIDCRAFT_VERSION=v0.16.0

# Buys a fresh resolution of the third-party app layer below (see the
# "Third-party desktop applications" section). Bump it for a local rebuild that
# must fetch the current ONLYOFFICE RPM; the weekly workflow passes a unique
# value per run.
ARG BUILD_EPOCH=local

LABEL org.opencontainers.image.title="Fedora bootc - Labwc + Konica bizhub 206" \
      org.opencontainers.image.description="Fedora bootc (base follows :latest), Linux/amd64, Labwc/Waybar/Foot desktop, PAPPL printer application with the konica-native C11 encoder" \
      org.opencontainers.image.source="https://github.com/vinod2807/fedora-bootc-konica206" \
      org.opencontainers.image.licenses="NOASSERTION" \
      org.vinod2807.konica.app-ref="${KONICA_APP_REF}" \
      org.vinod2807.konica.native-ref="${KONICA_NATIVE_REF}" \
      org.vinod2807.konica.retrofit-ref="${KONICA_RETROFIT_REF}"

# Weekly builds update the base packages as well as the two printer sources.
RUN set -eux; \
    dnf -y upgrade --refresh; \
    dnf install -y --setopt=install_weak_deps=False \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm; \
    dnf -y upgrade --refresh; \
    dnf install -y --setopt=install_weak_deps=False \
        adwaita-cursor-theme \
        adwaita-icon-theme \
        avahi \
        cups \
        cups-filters \
        dbus-daemon \
        default-fonts \
        desktop-file-utils \
        evince \
        firefox \
        flatpak \
        gpodder \
        gh \
        gh \
        foot \
        fuse \
        fuse-libs \
        fuzzel \
        ffmpeg \
        fastfetch \
        gstreamer1-libav \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-ugly \
        ghostscript \
        gnome-keyring \
        gnome-keyring-pam \
        greetd \
        grim \
        gthumb \
        gvfs \
        gvfs-fuse \
        gvfs-gphoto2 \
        gvfs-mtp \
        gvfs-smb \
        hicolor-icon-theme \
        labwc \
        legacy-printer-app \
        libavcodec-freeworld \
        libreoffice \
        libusb1 \
        lxpolkit \
        mesa-dri-drivers \
        mesa-libEGL \
        alsa-lib \
        libxkbcommon \
        vulkan-loader \
        mousepad \
        NetworkManager-wifi \
        nm-connection-editor \
        pappl \
        pavucontrol \
        Thunar \
        pipewire \
        pipewire-pulseaudio \
        policycoreutils-python-utils \
        qt5-qtbase-gui \
        qt5-qtwayland \
        retroarch \
        sane-airscan \
        samba \
        samba-client \
        sfwbar \
        simple-scan \
        slurp \
        swaybg \
        tuigreet \
        transmission \
        udiskie \
        usbutils \
        vlc \
        mpv \
        waybar \
        wdisplays \
        weechat \
        wl-clipboard \
        wob \
        wpa_supplicant \
        xarchiver \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        xdg-desktop-portal-wlr \
        xdg-user-dirs \
        xdg-utils \
        xorg-x11-server-Xwayland \
        wine \
        wine-mono \
        winetricks \
        zip \
        zram-generator \
        mako \
        swayidle \
        brightnessctl \
        plank \
        lxappearance \
        adw-gtk3-theme \
        kvantum \
        qt5ct \
        qt6ct \
        flatseal \
        network-manager-applet \
        NetworkManager-openconnect \
        NetworkManager-openvpn \
        gnome-font-viewer \
        gparted \
        thunderbird \
    && dnf clean all

# Third-party desktop applications, from their vendor repository / official
# release assets. Kept in their own layer so a failure is isolated:
#   - ONLYOFFICE Desktop Editors: official repo RPM (it also installs its own
#     GPG key at /etc/pki/rpm-gpg/RPM-GPG-KEY-ONLYOFFICE).
#   - NAPS2: official GitHub release asset, pinned to an exact version.
#   - ZapFast: official GitHub release asset, version from ZAPFAST_VERSION arg.
#
# This instruction never changes, so BuildKit would happily replay it from the
# cache and keep whatever ONLYOFFICE version the cache was built with. BUILD_EPOCH
# is only there to change the cache key: the weekly workflow passes the run id,
# so the RPM is re-resolved from ONLYOFFICE's repo on every published image.
# --refresh additionally expires any metadata that survived into a partial cache.
RUN set -eux; \
    echo "resolving third-party apps (cache epoch: ${BUILD_EPOCH})"; \
    curl --retry 3 --retry-delay 5 -fsSL \
        -o /etc/yum.repos.d/brave-browser.repo \
        https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo; \
    dnf install -y --nogpgcheck \
        https://download.onlyoffice.com/repo/centos/main/noarch/onlyoffice-repo.noarch.rpm; \
    dnf install -y --refresh onlyoffice-desktopeditors; \
    dnf install -y brave-browser; \
    dnf install -y \
        https://github.com/cyanfish/naps2/releases/download/v8.6.0/naps2-8.6.0-linux-x64.rpm; \
    dnf install -y \
        https://github.com/crmne/zapfast/releases/download/${ZAPFAST_VERSION}/zapfast-${ZAPFAST_VERSION#v}-1.x86_64.rpm; \
    dnf clean all

# Storytold Crafting Apps (official GitHub release RPMs).
# These are glibc-linked x86_64 RPMs from the upstream storytold repos.
# Versions are controlled by PDFCRAFT_VERSION, WORDCRAFT_VERSION, DECKCRAFT_VERSION,
# GRIDCRAFT_VERSION args; the weekly workflow resolves latest release tags.
RUN set -eux; \
    echo "installing storytold crafting apps"; \
    dnf install -y \
        https://github.com/storytold/pdfcraft/releases/download/${PDFCRAFT_VERSION}/pdfcraft-${PDFCRAFT_VERSION#v}-linux-x86_64.rpm \
        https://github.com/storytold/wordcraft/releases/download/${WORDCRAFT_VERSION}/wordcraft-${WORDCRAFT_VERSION#v}-linux-x86_64.rpm \
        https://github.com/storytold/deckcraft/releases/download/${DECKCRAFT_VERSION}/deckcraft-${DECKCRAFT_VERSION#v}-linux-x86_64.rpm \
        https://github.com/storytold/gridcraft/releases/download/${GRIDCRAFT_VERSION}/gridcraft-${GRIDCRAFT_VERSION#v}-linux-x86_64.rpm; \
    dnf clean all

# Epson Printer Utility for Linux is only distributed through Epson's download
# centre, which answers automated requests with HTTP 403 (Akamai), so it cannot
# be fetched here. The vendor RPM is committed under local-rpms/ and installed
# from there. See local-rpms/README.md.
#
# Scriptlets are skipped on purpose: the RPM's %post launches the ecbd daemon in
# the foreground, which never returns inside a container build (the build would
# hang). ecbd is only needed for USB-attached Epson printers; the network queue
# and the utility itself work without it. Enable it by hand on such a machine:
#   sudo systemctl enable --now ecbd.service
COPY local-rpms/ /tmp/local-rpms/
RUN set -eux; \
    if compgen -G '/tmp/local-rpms/*.rpm' >/dev/null; then \
        dnf install -y --setopt=tsflags=noscripts /tmp/local-rpms/*.rpm; \
        if [ -f /usr/lib/epson-backend/ecbd.service ]; then \
            install -D -m 0644 /usr/lib/epson-backend/ecbd.service \
                /usr/lib/systemd/system/ecbd.service; \
        fi; \
    else \
        echo 'no vendor RPM in local-rpms/, skipping'; \
    fi; \
    rm -rf /tmp/local-rpms; \
    dnf clean all

# The Epson RPM ships its menu entry inside /opt (and declares no dependency on
# Qt5), so expose it to the launcher and make sure its toolkit is present.
RUN set -eux; \
    if [ -f /opt/epson-printer-utility/epson-printer-utility.desktop ]; then \
        ln -sf /opt/epson-printer-utility/epson-printer-utility.desktop \
               /usr/share/applications/epson-printer-utility.desktop; \
    fi

# Dedicated unprivileged account for the printer application. USB access comes
# from the udev rule (group lp, mode 0660), not from running as root.
RUN set -eux; \
    useradd --system --user-group --no-create-home \
            --home-dir /var/lib/konica206 --shell /usr/sbin/nologin konica; \
    usermod -aG lp konica

# The encoder looks for its Konica-owned runtime data at a fixed absolute path
# under /usr/local/lib.  On bootc /usr is immutable, so that path is a symlink
# into persistent writable state: the licensed files are installed after the
# fact by konica206-install-vendor-data, never baked into the image.
RUN set -eux; \
    install -d -m 0755 /var/lib/konica206/vendor; \
    install -d -m 0755 /usr/local/lib; \
    ln -sTf /var/lib/konica206/vendor /usr/local/lib/konica

COPY --from=printer-builder /out/usr/bin/konica206-native /usr/bin/konica206-native
COPY --from=printer-builder /out/usr/bin/konica-send     /usr/bin/konica-send
COPY --from=printer-builder /out/usr/bin/konica-render   /usr/bin/konica-render
COPY --from=printer-builder /out/usr/bin/konica-native   /usr/bin/konica-native
COPY --from=printer-builder /src/app-commit              /usr/share/konica206/app-commit
COPY --from=printer-builder /src/native-commit           /usr/share/konica206/native-commit
# konica-retrofit integration assets, assembled and patched in the builder
# stage so this costs a single layer. Docker's overlay2 cannot load an image
# with more than ~125 layers, and the published image is already near that.
COPY --from=printer-builder /out/retrofit-root/ /

COPY bootc/90-linux-pc-crash-fixes.toml /usr/lib/bootc/kargs.d/90-linux-pc-crash-fixes.toml
COPY modprobe.d/90-linux-pc-crash-fixes.conf /etc/modprobe.d/90-linux-pc-crash-fixes.conf
COPY modprobe.d/90-konica206-usblp.conf      /etc/modprobe.d/90-konica206-usblp.conf
COPY systemd/konica206-native.service /usr/lib/systemd/system/konica206-native.service
COPY systemd/konica206-queue.service  /usr/lib/systemd/system/konica206-queue.service
COPY systemd/epson-l3260-queue.service /usr/lib/systemd/system/epson-l3260-queue.service
COPY systemd/konica206-classic-queue.service /usr/lib/systemd/system/konica206-classic-queue.service
COPY systemd/samba-setup.service    /usr/lib/systemd/system/samba-setup.service
COPY systemd/bootc-upgrade.service    /usr/lib/systemd/system/bootc-upgrade.service
COPY systemd/bootc-upgrade.timer      /usr/lib/systemd/system/bootc-upgrade.timer
COPY systemd/flatpak-update.service   /usr/lib/systemd/system/flatpak-update.service
COPY systemd/flatpak-update.timer     /usr/lib/systemd/system/flatpak-update.timer
COPY systemd/user/flatpak-update.service /usr/lib/systemd/user/flatpak-update.service
COPY systemd/user/flatpak-update.timer   /usr/lib/systemd/user/flatpak-update.timer
COPY systemd/zram-generator.conf      /etc/systemd/zram-generator.conf
COPY udev/70-konica206.rules          /usr/lib/udev/rules.d/70-konica206.rules
COPY greetd/config.toml               /etc/greetd/config.toml
COPY greetd/pam.d/greetd              /etc/pam.d/greetd
COPY desktop/labwc/autostart          /etc/xdg/labwc/autostart
COPY desktop/labwc/environment        /etc/xdg/labwc/environment
COPY desktop/labwc/menu.xml           /etc/xdg/labwc/menu.xml
COPY desktop/labwc/rc.xml             /etc/xdg/labwc/rc.xml
COPY desktop/applications/konica206-reboot.desktop   /usr/share/applications/konica206-reboot.desktop
COPY desktop/applications/konica206-poweroff.desktop /usr/share/applications/konica206-poweroff.desktop
COPY desktop/applications/mpv.desktop                /usr/share/applications/mpv.desktop
COPY desktop/waybar/config            /etc/xdg/waybar/config
COPY desktop/waybar/style.css         /etc/xdg/waybar/style.css
# sfwbar reads its system-wide default from the XDG *data* dir, not /etc/xdg.
COPY desktop/sfwbar/sfwbar.config     /usr/share/sfwbar/sfwbar.config
COPY scripts/install-vendor-data      /usr/libexec/konica206/install-vendor-data
COPY scripts/ensure-queue             /usr/libexec/konica206/ensure-queue
COPY scripts/preflight                /usr/libexec/konica206/preflight
COPY scripts/ensure-epson-queue       /usr/libexec/epson-l3260/ensure-queue
COPY scripts/ensure-classic-queue     /usr/libexec/konica206/ensure-classic-queue
COPY scripts/setup-samba              /usr/libexec/setup-samba
COPY samba/smb.conf                   /etc/samba/smb.conf
RUN install -d -m 0755 /etc/flatpak/overrides
COPY flatpak/overrides/com.stremio.Stremio /etc/flatpak/overrides/com.stremio.Stremio
COPY ppd/konica206.ppd                /usr/share/ppd/konica206/konica206.ppd

# Give the GRUB menu long enough to pick an older deployment by hand. The
# timeout lives in bootupd's static config, which bootupd concatenates into
# /boot/grub2/grub.cfg at install time. bootc runs bootupd only during
# installation and never regenerates grub.cfg afterwards, so this covers fresh
# installs; an already-installed machine keeps its own /boot/grub2/grub.cfg and
# is patched in place (see "Boot menu" in README.md).
RUN set -eux; \
    cfg=/usr/lib/bootupd/grub2-static/grub-static-pre.cfg; \
    sed -i -E 's/^set timeout=[0-9]+$/set timeout=10/' "$cfg"; \
    grep -qx 'set timeout=10' "$cfg"

RUN set -eux; \
    chmod 0755 /usr/bin/konica206-native /usr/bin/konica-send /usr/bin/konica-render /usr/bin/konica-native; \
    chmod 0755 /usr/libexec/konica206/install-vendor-data /usr/libexec/konica206/ensure-queue /usr/libexec/konica206/preflight /usr/libexec/konica206/ensure-legacy-queue; \
     chmod 0755 /usr/libexec/epson-l3260/ensure-queue; \
     chmod 0755 /usr/libexec/konica206/ensure-classic-queue; \
     chmod 0755 /usr/libexec/setup-samba; \
    chmod 0755 /usr/local/bin/konica-cups-watch.sh \
               /usr/local/sbin/check-wineps-route.sh \
               /usr/local/libexec/konica-backend/usb; \
    chmod 0644 /etc/greetd/config.toml \
        /etc/pam.d/greetd \
        /etc/systemd/zram-generator.conf \
        /etc/modprobe.d/90-konica206-usblp.conf \
        /usr/lib/systemd/system/konica206-native.service \
        /usr/lib/systemd/system/konica206-queue.service \
        /usr/lib/systemd/system/epson-l3260-queue.service \
        /usr/lib/systemd/system/samba-setup.service \
         /etc/samba/smb.conf \
        /etc/flatpak/overrides/com.stremio.Stremio \
        /usr/lib/systemd/system/bootc-upgrade.service \
        /usr/lib/systemd/system/bootc-upgrade.timer \
        /usr/lib/systemd/system/flatpak-update.service \
        /usr/lib/systemd/system/flatpak-update.timer \
        /usr/lib/systemd/user/flatpak-update.service \
        /usr/lib/systemd/user/flatpak-update.timer \
        /usr/lib/udev/rules.d/70-konica206.rules \
        /etc/xdg/labwc/menu.xml \
        /etc/cups/wineps.convs \
        /usr/local/share/konica-retrofit/min-ar.ps \
        /usr/share/konica206/retrofit-commit \
        /usr/lib/systemd/system/konica-cups-watch.service \
        /usr/lib/systemd/system/konica-cups-watch.timer \
        /usr/lib/systemd/system/konica206uri-queue.service \
        /etc/systemd/system/legacy-printer-app.service.d/90-konica206uri.conf \
        /usr/lib/tmpfiles.d/konica206uri.conf \
        /usr/share/konica206/legacy-ppd/KonicaMinolta-206-fullbleed.ppd \
        /usr/lib/udev/rules.d/71-konica206-usb-presence.rules \
        /usr/share/sfwbar/sfwbar.config \
        /usr/share/applications/konica206-reboot.desktop \
        /usr/share/applications/konica206-poweroff.desktop \
        /usr/share/applications/mpv.desktop \
        /usr/share/ppd/konica206/konica206.ppd; \
    chmod 0755 /etc/xdg/labwc/autostart; \
    chmod 0644 /etc/xdg/labwc/rc.xml; \
    ln -sf /usr/libexec/konica206/install-vendor-data /usr/bin/konica206-install-vendor-data; \
    ln -sf /usr/libexec/konica206/preflight /usr/bin/konica206-preflight; \
    install -d -m 0755 /usr/share/konica206

# Flathub is a system remote out of the box. flatpak imports entries from
# /etc/flatpak/remotes.d into /var/lib/flatpak the first time it runs, so no
# manual "flatpak remote-add" is needed on the installed system.
RUN set -eux; \
    install -d -m 0755 /etc/flatpak/remotes.d; \
    curl --retry 3 --retry-delay 5 -fsSL \
        -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo

# Graphical login by default (greetd on VT1 -> tuigreet -> labwc).
# Updates: the base image enables bootc-fetch-apply-updates.timer, which runs
# "bootc upgrade --apply" and REBOOTS into the new image. This machine must only
# reboot when the user says so, so that timer is masked and the repository's own
# bootc-upgrade.timer is used instead: it stages the update and never reboots.
# Masking also survives base-image updates (unlike a plain disable).
#
# Suspend/hibernate are not usable on this Ironlake hardware: the BIOS exposes
# no S3 and s2idle hangs on suspend. Mask the targets so no session (or
# leftover user config) can put the machine into a frozen state.
RUN set -eux; \
    systemctl set-default graphical.target; \
    systemctl mask bootc-fetch-apply-updates.timer; \
    rm -f /etc/systemd/system/timers.target.wants/bootc-fetch-apply-updates.timer; \
    systemctl mask suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target; \
    systemctl enable bootc-upgrade.timer; \
    systemctl enable flatpak-update.timer; \
    systemctl --global enable flatpak-update.timer; \
    systemctl enable NetworkManager.service; \
    systemctl enable greetd.service; \
    systemctl enable konica206-native.service; \
    systemctl enable konica206-queue.service; \
    systemctl enable legacy-printer-app.service; \
    systemctl enable konica206uri-queue.service; \
    systemctl enable konica-cups-watch.service; \
    systemctl enable konica-cups-watch.timer; \
    systemctl enable epson-l3260-queue.service; \
    systemctl enable konica206-classic-queue.service; \
    systemctl enable samba-setup.service; \
    systemctl enable avahi-daemon.service; \
    systemctl enable smb.service nmb.service; \
    if [ -e /usr/lib/systemd/system/ecbd.service ]; then \
        systemctl enable ecbd.service; \
    fi; \
    systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service

# bootc's own image sanity checks (must be last: it inspects the filesystem).
RUN bootc container lint
