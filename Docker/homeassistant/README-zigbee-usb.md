USB Zigbee Dongle (Home Assistant) — Minimal Runbook

Use this when `/dev/ttyUSB-zigbee` is missing.

---

Prevent recurrence (do once)
1) Keep kernel updates managed:
  - `sudo apt-get update && sudo apt-get install -y linux-generic`

2) Ensure drivers auto-load at boot:
  - `printf "%s\n" cp210x usbserial | sudo tee /etc/modules-load.d/zigbee.conf`

3) Ensure stable udev alias exists:
  - `printf '%s\n' 'KERNEL=="ttyUSB[0-9]*", SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="ttyUSB-zigbee", GROUP="dialout", MODE="0660"' | sudo tee /etc/udev/rules.d/99-zigbee.rules`
  - `sudo udevadm control --reload && sudo udevadm trigger`

4) Reboot soon after kernel updates.

---

If broken (run in order)

Symptom
- `docker compose up -d` fails with:
  - `error gathering device information while adding custom device "/dev/ttyUSB-zigbee": no such file or directory`

Run in this order:

1) Confirm USB device is visible:
  - `lsusb | grep -i "cp210\|silicon\|sonoff\|itead"`
  - If nothing appears, fix VM/hypervisor USB passthrough or replug dongle.

2) Ensure extra modules for running kernel:
  - `uname -r`
  - `dpkg -l | grep "linux-modules-extra-$(uname -r)" || true`
  - If missing: `sudo apt-get update && sudo apt-get install -y "linux-modules-extra-$(uname -r)"`

3) Load drivers now:
  - `sudo modprobe cp210x usbserial`
  - `lsmod | egrep "cp210x|usbserial"`

4) Refresh udev and verify nodes:
  - `sudo udevadm control --reload && sudo udevadm trigger`
  - `ls -l /dev/ttyUSB-zigbee /dev/ttyUSB* /dev/serial/by-id 2>/dev/null || true`
  - Expected: `/dev/ttyUSB0`, by-id symlink, and `/dev/ttyUSB-zigbee -> ttyUSB0`

5) Start Home Assistant:
  - `docker compose up -d`
  - `docker compose ps --all`
  - `docker compose logs --no-log-prefix --tail=200 homeassistant`

After recovery
- If you had to install `linux-modules-extra-$(uname -r)`, reboot when possible so boot-time module loading is clean and persistent.

---

AI handoff prompt (copy/paste)
"Home Assistant fails because `/dev/ttyUSB-zigbee` is missing. Run this runbook in order: check `lsusb`, ensure `linux-modules-extra-$(uname -r)` is installed, run `modprobe cp210x usbserial`, reload udev, verify `/dev/ttyUSB0` + `/dev/ttyUSB-zigbee`, then `docker compose up -d` and validate with `docker compose ps --all` and logs. If `lsusb` is empty, troubleshoot USB passthrough/replug first."

