# Pi-Orange-project — Lobby Queue Monitor

Turns an **Orange Pi One** connected to a TV into a full-screen lobby monitor for
`https://visit.starlinesecuritygroup.com/?kiosk=monitor`. It shows Now Serving / Waiting / Queued
and plays the page's sounds through the TV speakers, without anyone tapping the screen.

## What you need

- Orange Pi One + 16GB microSD card
- 5V **2A** USB power adapter (weak chargers cause freezes)
- HDMI cable to a TV/monitor **with speakers** (sound goes over HDMI; the board has no audio jack)
- LAN cable to the router (the Orange Pi One has no WiFi), or a USB WiFi dongle (RTL8188 / MT7601)

## Setup

1. Download **Armbian for Orange Pi One — Debian Bookworm, Minimal/CLI** from
   https://www.armbian.com/orange-pi-one/ (do not use the Ubuntu or Desktop image).
2. Write it to the microSD card with **balenaEtcher** or **Raspberry Pi Imager**.
3. Insert the card, connect the TV (switched on), the LAN cable, then power.
4. Log in on the TV with a USB keyboard (or SSH) as `root`, password `1234`.
   Armbian asks you to set a new root password and create a user. Do that.
5. Copy `setup-kiosk.sh` onto the board (USB stick, `scp`, or `curl` from this repo), then run:

   ```bash
   sudo bash setup-kiosk.sh
   sudo reboot
   ```

After the reboot the TV opens the lobby monitor full-screen. Sound plays automatically.

### Options

Set these before the command, e.g. `sudo ROTATE=left bash setup-kiosk.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `KIOSK_URL` | `https://visit.starlinesecuritygroup.com/?kiosk=monitor` | Page to show |
| `ROTATE` | `normal` | `left` / `right` / `inverted` for a portrait-mounted TV |
| `REBOOT_HOUR` | `3` | Daily reboot at 3 AM; `off` to disable |
| `KIOSK_USER` | `kiosk` | Account that runs the display |

Running the script again is safe; use it to change any option.

## Troubleshooting

- **No sound:** switch the TV on and plug it in *before* running the script, then run it again.
  Test with `speaker-test -c2 -t wav -l1`. Check the TV volume and input.
- **Page asks for login:** connect a USB keyboard and mouse once and sign in; the session is kept.
- **"Can't reach this page":** check the LAN cable; the launcher waits up to 2 minutes for the network.
- **Get back to a terminal:** press `Ctrl+Alt+F2` and log in, or SSH in.
- **Logs:** `/home/kiosk/.kiosk-x.log`.

## Notes for the monitor page

- Keep the page light (no background videos or heavy animations) — the Orange Pi One is an older CPU.
- If the page speaks numbers with `speechSynthesis`, it uses `espeak-ng` on the board, which sounds robotic.
  Pre-recorded MP3 clips (chime, "Now serving", digits, "Counter 2") sound much better.

## Website change: chime for queued numbers

`site/index.html` is the Starline Queue page (`visit.starlinesecuritygroup.com`) with one addition:
the Monitor board plays a soft two-note "ding-ding" when a new number joins a queue
(or a ticket is put back to waiting). Called numbers keep the existing announcement;
if both happen at once only the announcement plays, and the chime waits for any
announcement that is still speaking. Upload it to the site in place of the current
`index.html` (keep `announcement.mp3` next to it).
