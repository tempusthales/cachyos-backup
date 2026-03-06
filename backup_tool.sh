#!/usr/bin/env bash
# ============================================================
#  Author: Tempus Thales
#  Description: Backup & Restore Script
#  Usage: ./backup_tool.sh
#  Version: 0.0.6
# ============================================================

set -euo pipefail

# ── Config (set dynamically at startup) ──────────────────────
VERSION="0.0.7"
BACKUP_ROOT=""
USER_HOME=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=""
LATEST_LINK=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR]${RESET}   $*"; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; echo -e "${BOLD}  $*${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }

confirm() {
    read -rp "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ── Detect user & backup path ─────────────────────────────────
detect_user() {
    local default_user
    default_user=$(whoami)
    echo ""
    read -rp "Enter username to backup [${default_user}]: " INPUT_USER
    INPUT_USER="${INPUT_USER:-$default_user}"

    if [[ ! -d "/home/$INPUT_USER" ]]; then
        error "Home directory /home/$INPUT_USER does not exist"
        exit 1
    fi

    USER_HOME="/home/$INPUT_USER"
    info "Using home directory: $USER_HOME"
    echo ""

    local default_backup="/mnt/llm-storage/backups"
    read -rp "Enter backup destination path [${default_backup}]: " INPUT_BACKUP
    BACKUP_ROOT="${INPUT_BACKUP:-$default_backup}"

    BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
    LATEST_LINK="$BACKUP_ROOT/latest"

    mkdir -p "$BACKUP_ROOT" || { error "Cannot create backup directory: $BACKUP_ROOT"; exit 1; }
    info "Using backup location: $BACKUP_ROOT"
    echo ""
}

# ── Backup ────────────────────────────────────────────────────
do_backup() {
    header "Starting Backup → $BACKUP_DIR"
    local total_start
    total_start=$(date +%s)

    mkdir -p "$BACKUP_DIR"

    # Full home directory via rsync
    local t_start t_end t_elapsed
    t_start=$(date +%s)
    info "Backing up entire home directory (~/)..."
    info "Excluded: .cache, Steam, Trash, node_modules, .git, containers"
    rsync -a --info=progress2 --no-inc-recursive \
        --exclude=".cache" \
        --exclude=".local/share/Trash" \
        --exclude=".local/share/Steam" \
        --exclude=".local/share/baloo" \
        --exclude=".local/share/akonadi" \
        --exclude=".local/share/containers" \
        --exclude="*/node_modules" \
        --exclude="*/.git" \
        "$USER_HOME/" "$BACKUP_DIR/home/"
    t_end=$(date +%s)
    t_elapsed=$(( t_end - t_start ))
    success "Home directory done in $(( t_elapsed / 60 ))m $(( t_elapsed % 60 ))s"

    # fstab
    t_start=$(date +%s)
    info "Backing up /etc/fstab..."
    sudo cp /etc/fstab "$BACKUP_DIR/fstab"
    t_end=$(date +%s)
    success "fstab done in $(( t_end - t_start ))s"

    # Package lists
    t_start=$(date +%s)
    info "Saving package lists..."
    pacman -Qe > "$BACKUP_DIR/packages-explicit.txt"
    pacman -Qm > "$BACKUP_DIR/packages-aur.txt"
    pacman -Q  > "$BACKUP_DIR/packages-all.txt"
    t_end=$(date +%s)
    success "Package lists saved in $(( t_end - t_start ))s"

    # Update latest symlink
    ln -sfn "$BACKUP_DIR" "$LATEST_LINK"

    # Summary
    local total_end total_elapsed
    total_end=$(date +%s)
    total_elapsed=$(( total_end - total_start ))

    echo ""
    success "Backup complete!"
    info "Location: $BACKUP_DIR"
    info "Size:     $(du -sh "$BACKUP_DIR" | cut -f1)"
    info "Duration: $(( total_elapsed / 60 ))m $(( total_elapsed % 60 ))s"
    echo ""
}

# ── Pick backup source ────────────────────────────────────────
pick_backup() {
    header "Select Backup Source"

    local default_restore="$BACKUP_ROOT"
    read -rp "Enter path to search for backups [${default_restore}]: " INPUT_RESTORE
    local RESTORE_ROOT="${INPUT_RESTORE:-$default_restore}"

    if [[ ! -d "$RESTORE_ROOT" ]]; then
        error "Path does not exist: $RESTORE_ROOT"
        exit 1
    fi

    mapfile -t BACKUPS < <(find "$RESTORE_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "latest" | sort -r)

    if [[ ${#BACKUPS[@]} -eq 0 ]]; then
        error "No backups found in $RESTORE_ROOT"
        exit 1
    fi

    echo ""
    for i in "${!BACKUPS[@]}"; do
        SIZE=$(du -sh "${BACKUPS[$i]}" 2>/dev/null | cut -f1)
        DATE=$(basename "${BACKUPS[$i]}" | sed 's/_/ /' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
        echo -e "  ${BOLD}[$((i+1))]${RESET} $DATE  ${CYAN}(${SIZE})${RESET}  — ${BACKUPS[$i]}"
    done
    echo ""

    read -rp "Select backup [1-${#BACKUPS[@]}]: " SEL
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BACKUPS[@]} )); then
        error "Invalid selection"
        exit 1
    fi

    SELECTED="${BACKUPS[$((SEL-1))]}"
    info "Selected: $SELECTED"
    echo ""
}

do_restore() {
    pick_backup

    header "Restore Menu"
    echo -e "  ${BOLD}[1]${RESET} Restore ALL (full restore)"
    echo -e "  ${BOLD}[2]${RESET} Restore .config only"
    echo -e "  ${BOLD}[3]${RESET} Restore Hyprland config only"
    echo -e "  ${BOLD}[4]${RESET} Restore SSH keys only"
    echo -e "  ${BOLD}[5]${RESET} Restore GPG keys only"
    echo -e "  ${BOLD}[6]${RESET} Restore AppImages only"
    echo -e "  ${BOLD}[7]${RESET} Restore package lists (print commands)"
    echo -e "  ${BOLD}[8]${RESET} Restore fstab"
    echo -e "  ${BOLD}[9]${RESET} Back to main menu"
    echo ""

    read -rp "Select restore option: " OPT

    case "$OPT" in
        1)
            confirm "Restore EVERYTHING from $SELECTED? This will overwrite existing files." || exit 0
            restore_item "Home directory" "$SELECTED/home" "$USER_HOME"
            restore_fstab "$SELECTED"
            success "Full restore complete! Please reboot."
            ;;
        2)
            confirm "Restore .config? This will overwrite ~/.config." || exit 0
            restore_item ".config" "$SELECTED/home/.config" "$USER_HOME/.config"
            ;;
        3)
            confirm "Restore Hyprland config?" || exit 0
            restore_item "Hyprland" "$SELECTED/home/.config/hypr" "$USER_HOME/.config/hypr"
            ;;
        4)
            confirm "Restore SSH keys?" || exit 0
            restore_item "SSH keys" "$SELECTED/home/.ssh" "$USER_HOME/.ssh"
            chmod 700 "$USER_HOME/.ssh"
            chmod 600 "$USER_HOME/.ssh/"* 2>/dev/null || true
            ;;
        5)
            confirm "Restore GPG keys?" || exit 0
            restore_item "GPG keys" "$SELECTED/home/.gnupg" "$USER_HOME/.gnupg"
            chmod 700 "$USER_HOME/.gnupg"
            ;;
        6)
            confirm "Restore AppImages?" || exit 0
            restore_item "AppImages" "$SELECTED/home/AppImages" "$USER_HOME/AppImages"
            ;;
        7)
            header "Package Restore Commands"
            echo ""
            info "To reinstall all explicit packages:"
            echo -e "  ${CYAN}sudo pacman -S --needed \$(cat $SELECTED/packages-explicit.txt | awk '{print \$1}' | tr '\n' ' ')${RESET}"
            echo ""
            info "AUR packages (install manually with yay):"
            cat "$SELECTED/packages-aur.txt" | awk '{print "  yay -S "$1}'
            ;;
        8)
            confirm "Restore /etc/fstab? (requires sudo)" || exit 0
            restore_fstab "$SELECTED"
            ;;
        9)
            main_menu
            ;;
        *)
            error "Invalid option"
            ;;
    esac
}

restore_item() {
    local NAME="$1"
    local SRC="$2"
    local DEST="$3"

    if [[ ! -e "$SRC" ]]; then
        warn "$NAME not found in backup, skipping"
        return
    fi

    info "Restoring $NAME..."
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"
    cp -r "$SRC" "$DEST"
    success "$NAME restored to $DEST"
}

restore_fstab() {
    local BACKUP="$1"
    if [[ -f "$BACKUP/fstab" ]]; then
        info "Restoring /etc/fstab..."
        sudo cp "$BACKUP/fstab" /etc/fstab && success "fstab restored"
    else
        warn "fstab not found in backup"
    fi
}

# ── List backups ──────────────────────────────────────────────
do_list() {
    header "Available Backups in $BACKUP_ROOT"
    mapfile -t BACKUPS < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "latest" | sort -r)

    if [[ ${#BACKUPS[@]} -eq 0 ]]; then
        warn "No backups found in $BACKUP_ROOT"
        return
    fi

    for B in "${BACKUPS[@]}"; do
        SIZE=$(du -sh "$B" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}$(basename "$B")${RESET}  (${SIZE})  — $B"
    done
    echo ""
}

# ── Delete old backups ────────────────────────────────────────
do_cleanup() {
    header "Cleanup Old Backups"
    mapfile -t BACKUPS < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "latest" | sort -r)

    if [[ ${#BACKUPS[@]} -le 1 ]]; then
        info "Only one backup exists, nothing to clean up"
        return
    fi

    echo "Keeping newest backup. The following will be deleted:"
    for B in "${BACKUPS[@]:1}"; do
        echo -e "  ${RED}$(basename "$B")${RESET}  — $B"
    done
    echo ""

    confirm "Delete these backups?" || return

    for B in "${BACKUPS[@]:1}"; do
        rm -rf "$B"
        success "Deleted $(basename "$B")"
    done
}

# ── Main menu ─────────────────────────────────────────────────
main_menu() {
    clear
    header "CachyOS Backup & Restore  v${VERSION}"
    echo -e "  User:            ${CYAN}$USER_HOME${RESET}"
    echo -e "  Backup location: ${CYAN}$BACKUP_ROOT${RESET}"
    echo ""
    echo -e "  ${BOLD}[1]${RESET} Create new backup"
    echo -e "  ${BOLD}[2]${RESET} Restore from backup"
    echo -e "  ${BOLD}[3]${RESET} List backups"
    echo -e "  ${BOLD}[4]${RESET} Clean up old backups"
    echo -e "  ${BOLD}[5]${RESET} Exit"
    echo ""
    read -rp "Select option: " OPT

    case "$OPT" in
        1) do_backup ;;
        2) do_restore ;;
        3) do_list ;;
        4) do_cleanup ;;
        5) exit 0 ;;
        *) error "Invalid option"; main_menu ;;
    esac
}

# ── Entry point ───────────────────────────────────────────────
echo ""
info "This script requires sudo for backing up /etc/fstab."
sudo -v || { error "sudo authentication failed"; exit 1; }

detect_user
main_menu
