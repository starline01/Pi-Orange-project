#!/usr/bin/env bash
# Turn a fresh Armbian (Debian Bookworm, minimal/CLI) install on an
# Orange Pi One into a full-screen lobby queue monitor.
#
# Usage (as root):
#   sudo bash setup-kiosk.sh
#   sudo KIOSK_URL="https://visit.starlinesecuritygroup.com/monitor" bash setup-kiosk.sh
#
# Safe to run again: every step overwrites its own files.
set -euo pipefail

KIOSK_URL="${KIOSK_URL:-https://visit.starlinesecuritygroup.com/monitor}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
# Daily reboot hour (0-23) keeps a 1GB board fresh; set to "off" to disable.
REBOOT_HOUR="${REBOOT_HOUR:-3}"
# Rotate the screen: normal | left | right | inverted
ROTATE="${ROTATE:-normal}"

log() { printf '\n==> %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

case "$ROTATE" in normal|left|right|inverted) ;; *)
  echo "ROTATE must be normal, left, right or inverted" >&2; exit 1 ;;
esac

log "Installing packages (this takes a while on an Orange Pi One)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
if ! apt-cache show chromium >/dev/null 2>&1; then
  echo "The 'chromium' apt package is not available on this image." >&2
  echo "Use an Armbian Debian Bookworm (minimal) image, not an Ubuntu one." >&2
  exit 1
fi
apt-get install -y --no-install-recommends \
  xserver-xorg xinit x11-xserver-utils openbox unclutter \
  chromium fonts-noto-core fonts-noto-color-emoji \
  alsa-utils curl ca-certificates \
  speech-dispatcher espeak-ng

log "Creating kiosk user '$KIOSK_USER'"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$KIOSK_USER"
fi
usermod -aG audio,video,tty,input "$KIOSK_USER"
KHOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

log "Auto-login on the console (tty1)"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF
# Armbian asks to create a user on first login; make sure that is done.
rm -f /root/.not_logged_in_yet

log "Allowing the kiosk user to start X"
cat > /etc/X11/Xwrapper.config <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

log "Routing sound to HDMI (TV speakers)"
HDMI_CARD="$(aplay -l 2>/dev/null | awk -F'[ :]+' 'tolower($0) ~ /hdmi/ && /^card/ {print $2; exit}')"
if [ -n "$HDMI_CARD" ]; then
  cat > /etc/asound.conf <<EOF
defaults.pcm.card $HDMI_CARD
defaults.ctl.card $HDMI_CARD
EOF
  amixer -c "$HDMI_CARD" sset Master unmute 100% >/dev/null 2>&1 || true
  amixer -c "$HDMI_CARD" sset PCM unmute 100% >/dev/null 2>&1 || true
  alsactl store >/dev/null 2>&1 || true
  echo "HDMI audio is card $HDMI_CARD"
else
  echo "WARNING: no HDMI sound card found (aplay -l). Is the TV connected?"
  echo "Re-run this script with the TV plugged in and switched on."
fi

log "Disabling console screen blanking"
if [ -f /boot/armbianEnv.txt ]; then
  if grep -q '^extraargs=' /boot/armbianEnv.txt; then
    grep -q 'consoleblank=0' /boot/armbianEnv.txt || \
      sed -i 's/^extraargs=\(.*\)$/extraargs=\1 consoleblank=0/' /boot/armbianEnv.txt
  else
    echo 'extraargs=consoleblank=0' >> /boot/armbianEnv.txt
  fi
fi

log "Writing the kiosk launcher"
cat > /usr/local/bin/lobby-kiosk <<EOF
#!/usr/bin/env bash
# Started by X (~/.xinitrc). Opens the lobby monitor and restarts it if it closes.
URL="$KIOSK_URL"
PROFILE="\$HOME/.config/chromium"

xset s off; xset s noblank; xset -dpms
[ "$ROTATE" = normal ] || xrandr -o "$ROTATE" || true
unclutter -idle 0.5 -root &
openbox-session &

# Wait up to 2 minutes for the network so the first load does not show an error.
for _ in \$(seq 1 60); do
  curl -sfI --max-time 3 "\$URL" >/dev/null && break
  sleep 2
done

while true; do
  # Stop the "Chromium didn't shut down correctly" bar after a power cut.
  if [ -f "\$PROFILE/Default/Preferences" ]; then
    sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' \
      "\$PROFILE/Default/Preferences"
  fi
  chromium \\
    --kiosk "\$URL" \\
    --user-data-dir="\$PROFILE" \\
    --autoplay-policy=no-user-gesture-required \\
    --noerrdialogs --disable-infobars --no-first-run \\
    --disable-session-crashed-bubble --disable-features=Translate \\
    --check-for-update-interval=31536000 \\
    --overscroll-history-navigation=0 --disable-pinch \\
    --renderer-process-limit=2 \\
    --enable-speech-dispatcher
  sleep 3
done
EOF
chmod 755 /usr/local/bin/lobby-kiosk

cat > "$KHOME/.xinitrc" <<'EOF'
exec /usr/local/bin/lobby-kiosk
EOF

cat > "$KHOME/.bash_profile" <<'EOF'
# Start the lobby monitor on the physical console only (not over SSH).
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
  exec startx -- -nocursor >"$HOME/.kiosk-x.log" 2>&1
fi
EOF
chown "$KIOSK_USER:$KIOSK_USER" "$KHOME/.xinitrc" "$KHOME/.bash_profile"

log "Daily reboot"
if [ "$REBOOT_HOUR" = off ]; then
  rm -f /etc/cron.d/lobby-kiosk-reboot
else
  echo "0 $REBOOT_HOUR * * * root /sbin/shutdown -r now" > /etc/cron.d/lobby-kiosk-reboot
  chmod 644 /etc/cron.d/lobby-kiosk-reboot
fi

systemctl daemon-reload
systemctl set-default multi-user.target >/dev/null

log "Done. Reboot to start the lobby monitor:  sudo reboot"
echo "URL:  $KIOSK_URL"
echo "To change the URL later:  sudo KIOSK_URL=https://... bash setup-kiosk.sh"
