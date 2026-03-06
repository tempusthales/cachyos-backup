# CachyOS Reinstall & Restore Guide
> Author: Tempus Thales &nbsp;•&nbsp; `backup_tool.sh` v0.0.7

---

## Phase 1 — Before You Wipe

> Complete these steps **before** starting the CachyOS installer.

### 1.1 Confirm Backup Completed

1. **Verify backup exists on LLM-Storage**
   ```bash
   ls -lh /mnt/llm-storage/backups/
   ```

2. **Confirm the home folder is inside the backup**
   ```bash
   ls /mnt/llm-storage/backups/<timestamp>/home/
   ```

### 1.2 Save the Backup Script

The backup script lives on the LLM-Storage drive which survives the reinstall, but confirm it's there:

```bash
ls /mnt/llm-storage/backups/cachyos-backup.sh
```

> **Note:** If not there, copy it: `cp ~/cachyos-backup.sh /mnt/llm-storage/`

### 1.3 Note Your Disk Layout

Write down your partition UUIDs — you'll need them for fstab after reinstall:

```bash
lsblk -o NAME,UUID,LABEL,MOUNTPOINT
```

> `nvme0n1` = system (will be wiped) &nbsp;•&nbsp; `nvme1n1` = LLM-Storage (keep) &nbsp;•&nbsp; `nvme2n1` = SteamApps (keep)

---

## Phase 2 — Install CachyOS

### 2.1 Partitioning

1. **Select `nvme0n1` as the install target** — Do NOT touch `nvme1n1` or `nvme2n1`
2. **Enable LUKS encryption** — Use the same or a new passphrase
3. **Use btrfs with subvolumes** — Match your previous layout: `@`, `@home`, `@root`, `@srv`, `@cache`, `@tmp`, `@log`

### 2.2 User Setup

1. **Create user:** `gjp` — Use the same username so restore paths match automatically
2. **Set hostname:** `AUSTIN`

### 2.3 GPU & Driver Selection

1. **Select NVIDIA open drivers during install** — For RTX 5070 (GB205): select `nvidia-open` or `linux-cachyos-nvidia-open`
2. **Do NOT install both NVIDIA and AMD drivers** — The AMD iGPU driver loads automatically, no action needed

---

## Phase 3 — First Boot (Before Restore)

### 3.1 Verify Basic System

1. **Log in via TTY first** — Press `Ctrl+Alt+F2` if you land on a black screen
2. **Check internet connection**
   ```bash
   ping -c 3 archlinux.org
   ```
3. **Update the system before anything else**
   ```bash
   sudo pacman -Syu
   ```

### 3.2 Mount LLM-Storage

Confirm the LLM-Storage drive is mounted and your backup is accessible:

```bash
lsblk | grep nvme1
ls /mnt/llm-storage/backups/
```

> **Note:** If not mounted: `sudo mount /dev/nvme1n1p1 /mnt/llm-storage`

### 3.3 Install Hyprland & Core Packages First

Install your window manager before restoring configs, so the config targets exist:

```bash
sudo pacman -S hyprland uwsm sddm kitty
sudo systemctl enable sddm
```

---

## Phase 4 — Run the Restore ⬅️ The Right Moment

> System is installed, drivers are in, packages are ready. **Now** restore.

### 4.1 Copy and Run the Backup Script

```bash
cp /mnt/llm-storage/cachyos-backup.sh ~/
chmod +x ~/cachyos-backup.sh
bash ~/cachyos-backup.sh
```

### 4.2 Restore Order

In the restore menu, restore in this order for best results:

1. Select **[2] Restore from backup**
2. Choose your backup timestamp from the list
3. **Restore Hyprland config first (option 3)** — Gets monitors, keybinds and env vars back
4. **Restore full .config (option 2)** — Restores all app configs
5. **Restore SSH keys (option 4)** — Fixes permissions automatically
6. **Restore GPG keys (option 5)**
7. **Restore fstab (option 8)** — Restores LLM-Storage and SteamApps mount points

> ⚠️ Do NOT restore ALL at once (option 1) if you want to be careful — restore piece by piece.

---

## Phase 5 — Post-Restore Fixes

### 5.1 Fix SDDM for Wayland

SDDM defaults to X11. Force Wayland mode:

```bash
sudo mkdir -p /etc/sddm.conf.d
sudo nano /etc/sddm.conf.d/wayland.conf
```

```ini
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=weston --backend=drm-backend.so
```

### 5.2 Add User to Seat Group

Required for libseat to work correctly with Hyprland:

```bash
sudo usermod -aG seat gjp
```

### 5.3 Verify Environment Variables

Check that your Hyprland `env.conf` has the correct GPU settings:

```bash
cat ~/.config/hypr/conf/env.conf
```

Key variables to confirm:
```bash
AQ_DRM_DEVICES=/dev/dri/card1
__GLX_VENDOR_LIBRARY_NAME=nvidia
AQ_MGPU_NO_EXPLICIT=1
```

### 5.4 Reinstall AUR Packages

Install `yay` first, then restore AUR packages:

```bash
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si
cat /mnt/llm-storage/backups/<timestamp>/packages-aur.txt | awk '{print $1}' | xargs yay -S --needed
```

---

## Phase 6 — Final Checks

### 6.1 Reboot and Verify

1. **Reboot**
   ```bash
   sudo reboot
   ```
2. Log in via SDDM — select **Hyprland** session
3. **Verify both monitors detected**
   ```bash
   hyprctl monitors
   ```
4. **Verify GPU is NVIDIA**
   ```bash
   hyprctl version | grep -i gpu
   nvidia-smi
   ```

### 6.2 Restore SteamApps Mount

Verify Steam games drive is mounted correctly after fstab restore:

```bash
ls /mnt/SteamApps/
```

> **Note:** If missing: `sudo mount /dev/nvme2n1 /mnt/SteamApps`

---

## Quick Reference Checklist

- [ ] Backup confirmed on LLM-Storage before wipe
- [ ] CachyOS installed on `nvme0n1` only
- [ ] NVIDIA open drivers selected during install
- [ ] System updated before restore (`pacman -Syu`)
- [ ] Hyprland + SDDM installed before running restore
- [ ] `backup_tool.sh` restore run from LLM-Storage
- [ ] SDDM configured for Wayland
- [ ] `gjp` added to seat group
- [ ] Rebooted and both monitors working
- [ ] AUR packages reinstalled
