#!/bin/bash
# NyxLite builder: text-only live/installable Ubuntu 26.04 (resolute) for HP Stream 11 (x86_64, UEFI/BIOS)
set -euo pipefail
SUITE=${SUITE:-resolute}
MIRROR=${MIRROR:-http://archive.ubuntu.com/ubuntu}
W=${W:-/tmp/nyx}
ROOT=$W/rootfs; ISO=$W/iso
rm -rf "$W"; mkdir -p "$ROOT" "$ISO/casper" "$ISO/boot/grub"

[ -e /usr/share/debootstrap/scripts/$SUITE ] || ln -s gutsy /usr/share/debootstrap/scripts/$SUITE
debootstrap --variant=minbase --components=main,universe --include=ca-certificates "$SUITE" "$ROOT" "$MIRROR"

mount --bind /dev "$ROOT/dev"; mount -t devpts devpts "$ROOT/dev/pts"; mount -t proc proc "$ROOT/proc"; mount -t sysfs sys "$ROOT/sys"
trap 'umount -lf "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" 2>/dev/null || true' EXIT
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"

cat > "$ROOT/etc/apt/sources.list" <<S
deb $MIRROR $SUITE main universe
deb $MIRROR $SUITE-updates main universe
deb http://security.ubuntu.com/ubuntu $SUITE-security main universe
S
echo nyxlite > "$ROOT/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 nyxlite\n' > "$ROOT/etc/hosts"

install -m755 overlay/nyx-menu "$ROOT/usr/local/bin/nyx-menu"
install -m755 overlay/nyx-install "$ROOT/usr/local/bin/nyx-install"

chroot "$ROOT" /bin/bash -e <<'C'
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get update -qq
apt-get install -y --no-install-recommends \
  linux-image-generic casper initramfs-tools systemd-sysv udev dbus \
  network-manager wpasupplicant iw rfkill isc-dhcp-client iproute2 iputils-ping \
  linux-firmware \
  nano mc htop tmux less file curl wget lynx ncdu bash-completion sudo kbd console-setup locales \
  parted gdisk dosfstools e2fsprogs rsync grub-efi-amd64 grub-pc-bin efibootmgr dialog \
  squashfs-tools pciutils usbutils man-db
useradd -m -s /bin/bash -G sudo,adm,netdev,audio,video nyx
echo 'nyx:nyx' | chpasswd
echo 'root:nyx' | chpasswd
echo 'nyx ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/nyx
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; locale-gen >/dev/null; echo 'LANG=en_US.UTF-8' > /etc/default/locale
# text-only boot, autologin on tty1 into the NyxLite menu
systemctl set-default multi-user.target
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<G
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin nyx --noclear %I \$TERM
G
cat >> /home/nyx/.profile <<'P'
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$NYX_SKIP" ]; then exec /usr/local/bin/nyx-menu; fi
P
chown nyx:nyx /home/nyx/.profile
cat > /etc/motd <<'M'
NyxLite - type 'nyx-menu' for the menu, 'nmtui' for wifi.
M
systemctl enable NetworkManager >/dev/null 2>&1 || true
systemctl disable NetworkManager-wait-online.service >/dev/null 2>&1 || true
# shrink
apt-get purge -y --autoremove snapd 2>/dev/null || true
apt-get clean; rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/??  /var/cache/* /tmp/* 
C
umount -lf "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" 2>/dev/null || true; trap - EXIT

cp "$ROOT"/boot/vmlinuz-* "$ISO/casper/vmlinuz"
cp "$ROOT"/boot/initrd.img-* "$ISO/casper/initrd"
rm -f "$ROOT/etc/resolv.conf"
mksquashfs "$ROOT" "$ISO/casper/filesystem.squashfs" -comp xz -Xbcj x86 -b 1M -e boot/initrd.img* -noappend
cat > "$ISO/boot/grub/grub.cfg" <<'G'
set default=0
set timeout=3
menuentry "NyxLite (text mode)" {
  linux /casper/vmlinuz boot=casper quiet loglevel=3 nomodeset systemd.show_status=0 ---
  initrd /casper/initrd
}
menuentry "NyxLite (verbose)" {
  linux /casper/vmlinuz boot=casper nomodeset ---
  initrd /casper/initrd
}
G
grub-mkrescue -o "$W/nyxlite.iso" "$ISO" -- -volid NYXLITE
ls -lh "$W/nyxlite.iso"
