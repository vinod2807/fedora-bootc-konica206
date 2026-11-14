# syntax=docker/dockerfile:1.7
#
# Fedora bootc image with:
#   - Labwc / Waybar / Foot Wayland desktop + greetd/tuigreet login
#   - fuzzel-printjobs desktop helper (CUPS job cancel/restart, W-e)
#   - CUPS and Samba printer sharing (print queues are created locally at
#     runtime, not baked into this image)
#
# The Konica Minolta bizhub 206 is provided at runtime by a restored podman
# container (CUPS on port 6632, queue Konica_Via_Podman); it is intentionally
# not built into this image.
#
# Build:
#   podman build --platform linux/amd64 -t localhost/fedora-bootc-konica206 .
#
# The base follows the moving :latest tag on purpose: each weekly build picks
# up the current Fedora release, so a new Fedora major version lands a few days
# after GA without touching this file. The trade-off is that a Fedora major
# version jump is unattended; the bootloader keeps the previous deployment and
# the GRUB menu waits, so a bad jump can be rolled back by hand. To stop
# following the release train, pin both args (e.g. :45) and bump them by hand.

ARG BASE_IMAGE=quay.io/fedora/fedora-bootc:latest

# ---------------------------------------------------------------------------
# Final bootc image.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

# ZapFast version to install from GitHub releases. Bump for a new release; the
# weekly workflow can resolve the latest tag automatically.
ARG ZAPFAST_VERSION=v0.20.1

# Buys a fresh resolution of the third-party app layer below (see the
# "Third-party desktop applications" section). Bump it for a local rebuild that
# must fetch the current ONLYOFFICE RPM; the weekly workflow passes a unique
# value per run.
ARG BUILD_EPOCH=local

LABEL org.opencontainers.image.title="Fedora bootc - Labwc desktop" \
      org.opencontainers.image.description="Fedora bootc (base follows :latest), Linux/amd64, Labwc/Waybar/Foot desktop, CUPS printer sharing" \
      org.opencontainers.image.source="https://github.com/vinod2807/fedora-bootc-konica206" \
      org.opencontainers.image.licenses="NOASSERTION"

# Weekly builds refresh the base image and packages.
RUN set -eux; \
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
        flatpak \
        gh \
        gh \
        foot \
        fuse \
        fuse-libs \
        fuzzel \
        fastfetch \
        ghostscript \
        gnome-keyring \
        gnome-keyring-pam \
        greetd \
        grim \
        gvfs \
        gvfs-fuse \
        gvfs-gphoto2 \
        gvfs-mtp \
        gvfs-smb \
        hicolor-icon-theme \
        labwc \
        libusb1 \
        lxpolkit \
        mesa-dri-drivers \
        mesa-libEGL \
        mesa-vulkan-drivers \
        alsa-lib \
        libxkbcommon \
        vulkan-loader \
        mousepad \
        NetworkManager-wifi \
        nm-connection-editor \
        pavucontrol \
        Thunar \
        pipewire \
        pipewire-pulseaudio \
        policycoreutils-python-utils \
        qt5-qtbase-gui \
        sane-airscan \
        samba \
        samba-client \
        sfwbar \
        simple-scan \
        slurp \
        swaybg \
        tuigreet \
        udiskie \
        usbutils \
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
        zip \
        zram-generator \
        mako \
        swayidle \
        brightnessctl \
        flatseal \
        network-manager-applet \
        NetworkManager-openconnect \
        NetworkManager-openvpn \
        gnome-font-viewer \
    # xfce4-panel ships with Thunar's libxfce4panel dep; hide its
    # Settings entries (Panel) that labwc/sfwbar ignore. The package
    # itself must stay, only the menu entries go.
    && rm -f /usr/share/applications/panel-preferences.desktop \
             /usr/share/applications/panel-desktop-handler.desktop \
    && dnf clean all

# Third-party desktop applications, from their vendor repository / official
# release assets. Kept in their own layer so a failure is isolated:
#   - NAPS2: official GitHub release asset, pinned to an exact version.
#   - ZapFast: official GitHub release asset, version from ZAPFAST_VERSION arg.
#
# BUILD_EPOCH busts this layer's cache: the weekly workflow passes the run id,
# so NAPS2/ZapFast are re-resolved from GitHub on every published image.
# --refresh additionally expires any metadata that survived into a partial cache.
RUN set -eux; \
    echo "resolving third-party apps (cache epoch: ${BUILD_EPOCH})"; \
    dnf install -y \
        https://github.com/cyanfish/naps2/releases/download/v8.6.0/naps2-8.6.0-linux-x64.rpm; \
    dnf install -y \
        https://github.com/crmne/zapfast/releases/download/${ZAPFAST_VERSION}/zapfast-${ZAPFAST_VERSION#v}-1.x86_64.rpm; \
    dnf clean all

# Epson Printer Utility for Linux is only distributed through Epson's download
# centre, which answers automated requests with HTTP 403 (Akamai), so it cannot
# be fetched here. The vendor RPM is committed under local-rpms/ and installed
# from there. See local-rpms/README.md.
#
# Scriptlets are skipped on purpose: the RPM's %post launches the ecbd daemon in
# the foreground, which never returns inside a container build (the build would
# hang). ecbd is only needed for USB-attached Epson printers; network printing
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

COPY bootc/90-linux-pc-crash-fixes.toml /usr/lib/bootc/kargs.d/90-linux-pc-crash-fixes.toml
COPY modprobe.d/90-linux-pc-crash-fixes.conf /etc/modprobe.d/90-linux-pc-crash-fixes.conf
COPY modprobe.d/90-usblp-blacklist.conf      /etc/modprobe.d/90-usblp-blacklist.conf
COPY systemd/samba-setup.service    /usr/lib/systemd/system/samba-setup.service
COPY systemd/nmb.service.d/10-wait-for-interface.conf /usr/lib/systemd/system/nmb.service.d/10-wait-for-interface.conf
COPY systemd/bootc-upgrade.service    /usr/lib/systemd/system/bootc-upgrade.service
COPY systemd/bootc-upgrade.timer      /usr/lib/systemd/system/bootc-upgrade.timer
COPY systemd/flatpak-update.service   /usr/lib/systemd/system/flatpak-update.service
COPY systemd/flatpak-update.timer     /usr/lib/systemd/system/flatpak-update.timer
COPY systemd/user/flatpak-update.service /usr/lib/systemd/user/flatpak-update.service
COPY systemd/user/flatpak-update.timer   /usr/lib/systemd/user/flatpak-update.timer
COPY systemd/zram-generator.conf      /etc/systemd/zram-generator.conf
COPY systemd/zram-setup-no-fail-on-stop.conf /usr/lib/systemd/system/systemd-zram-setup@zram0.service.d/10-no-fail-on-stop.conf
COPY greetd/config.toml               /etc/greetd/config.toml
COPY greetd/pam.d/greetd              /etc/pam.d/greetd
COPY desktop/labwc/autostart          /etc/xdg/labwc/autostart
COPY desktop/labwc/environment        /etc/xdg/labwc/environment
COPY desktop/labwc/menu.xml           /etc/xdg/labwc/menu.xml
COPY desktop/labwc/rc.xml             /etc/xdg/labwc/rc.xml
COPY desktop/applications/konica206-reboot.desktop   /usr/share/applications/konica206-reboot.desktop
COPY desktop/applications/konica206-poweroff.desktop /usr/share/applications/konica206-poweroff.desktop
COPY desktop/applications/fuzzel-printjobs.desktop  /usr/share/applications/fuzzel-printjobs.desktop
# User-facing print-job manager (no service, no privileges beyond the user's
# own queued jobs). Installed system-wide so every login gets the W-e
# keybind, the Printing menu, and the fuzzel application entry.
COPY scripts/fuzzel-printjobs         /usr/local/bin/fuzzel-printjobs
# Upstream weechat.desktop uses Exec=weechat with Terminal=true. sfwbar's
# appmenu (g_app_info_launch) cannot find a terminal emulator for
# Terminal=true apps ("Unable to find terminal required"), so clicking
# WeeChat in the sfwbar start menu silently does nothing. Point Exec at
# foot (the session terminal, same as desktop/labwc/menu.xml) and mark
# Terminal=false so gio/sfwbar/fuzzel all spawn it in a foot window.
COPY desktop/applications/weechat.desktop /usr/share/applications/weechat.desktop
# sfwbar reads its system-wide default from the XDG *data* dir, not /etc/xdg.
COPY desktop/sfwbar/sfwbar.config     /usr/share/sfwbar/sfwbar.config
COPY scripts/setup-samba              /usr/libexec/setup-samba
COPY samba/smb.conf                   /etc/samba/smb.conf
RUN install -d -m 0755 /etc/flatpak/overrides
COPY flatpak/overrides/com.stremio.Stremio /etc/flatpak/overrides/com.stremio.Stremio

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
    chmod 0755 /usr/libexec/setup-samba; \
    chmod 0755 /usr/local/bin/fuzzel-printjobs; \
    chmod 0644 /etc/greetd/config.toml \
        /etc/pam.d/greetd \
        /etc/systemd/zram-generator.conf \
        /etc/modprobe.d/90-usblp-blacklist.conf \
        /usr/lib/systemd/system/samba-setup.service \
        /usr/lib/systemd/system/nmb.service.d/10-wait-for-interface.conf \
        /etc/samba/smb.conf \
        /etc/flatpak/overrides/com.stremio.Stremio \
        /usr/lib/systemd/system/bootc-upgrade.service \
        /usr/lib/systemd/system/bootc-upgrade.timer \
        /usr/lib/systemd/system/flatpak-update.service \
        /usr/lib/systemd/system/flatpak-update.timer \
        /usr/lib/systemd/user/flatpak-update.service \
        /usr/lib/systemd/user/flatpak-update.timer \
        /etc/xdg/labwc/menu.xml \
        /usr/share/sfwbar/sfwbar.config \
        /usr/share/applications/konica206-reboot.desktop \
        /usr/share/applications/konica206-poweroff.desktop \
        /usr/share/applications/fuzzel-printjobs.desktop \
        /usr/share/applications/weechat.desktop; \
    update-desktop-database /usr/share/applications; \
    chmod 0755 /etc/xdg/labwc/autostart; \
    chmod 0644 /etc/xdg/labwc/rc.xml

# Enable CUPS printer sharing at build time instead of at boot.  cupsd is a
# systemd on-demand service (cupsd -l); when samba-setup.service called
# "cupsctl --share-printers" on every boot, the resulting config PUT made cupsd
# exit and restart, which systemd logged as a cups.service failure ("Scheduler
# shutting down due to program error").  Apply the same settings cupsctl writes
# (LAN listener, Browsing On, DNS-SD, and Allow @LOCAL on <Location />) to the
# packaged config so cupsd starts already shared and the boot log stays clean.
RUN set -eux; \
    conf=/etc/cups/cupsd.conf; \
    test -f "$conf"; \
    sed -i -E \
        -e 's/^[[:space:]]*Browsing[[:space:]].*/Browsing On/' \
        -e 's/^[[:space:]]*BrowseLocalProtocols[[:space:]].*/BrowseLocalProtocols dnssd/' \
        -e '/^[[:space:]]*Listen[[:space:]]+localhost:631[[:space:]]*$/d' \
        "$conf"; \
    grep -qE '^[[:space:]]*Browsing[[:space:]]+On[[:space:]]*$' "$conf" || \
        printf '\nBrowsing On\n' >> "$conf"; \
    grep -qE '^[[:space:]]*BrowseLocalProtocols[[:space:]]+.*dnssd' "$conf" || \
        printf 'BrowseLocalProtocols dnssd\n' >> "$conf"; \
    grep -qE '^[[:space:]]*Port[[:space:]]+631[[:space:]]*$' "$conf" || \
        printf 'Port 631\n' >> "$conf"; \
    if ! sed -n '/^<Location \/>$/,/^<\/Location>$/p' "$conf" | grep -qx '[[:space:]]*Allow @LOCAL'; then \
        sed -i '/^<Location \/>$/,/^<\/Location>$/ s/^[[:space:]]*Order allow,deny[[:space:]]*$/  Order allow,deny\n  Allow @LOCAL/' "$conf"; \
    fi; \
    grep -qE '^[[:space:]]*Browsing[[:space:]]+On[[:space:]]*$' "$conf"; \
    grep -qE '^[[:space:]]*BrowseLocalProtocols[[:space:]]+.*dnssd' "$conf"; \
    grep -qE '^[[:space:]]*Port[[:space:]]+631[[:space:]]*$' "$conf"; \
    sed -n '/^<Location \/>$/,/^<\/Location>$/p' "$conf" | grep -qx '[[:space:]]*Allow @LOCAL'

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
    systemctl enable samba-setup.service; \
    systemctl enable avahi-daemon.service; \
    systemctl enable smb.service nmb.service; \
    if [ -e /usr/lib/systemd/system/ecbd.service ]; then \
        systemctl enable ecbd.service; \
    fi; \
    systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service

# bootc's own image sanity checks (must be last: it inspects the filesystem).
RUN bootc container lint
