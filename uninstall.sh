#!/usr/bin/env bash
# ==============================================================================
# Lenovo Legion 5 Pro (16ACH6H / 82JQ) - NVIDIA dGPU Power-Off Uninstaller
# Restores original system power management & enables NVIDIA GPU
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo ./uninstall.sh)"
    exit 1
fi

log_info "Restoring default dGPU hardware configuration..."

# Remove configuration files
rm -f /etc/modprobe.d/blacklist-nvidia.conf
rm -f /etc/udev/rules.d/99-nvidia-remove.rules
rm -f /etc/dracut.conf.d/gpu-kill.conf
rm -f /etc/dracut.conf.d/acpi/gpu-off.aml
rmdir --ignore-fail-on-non-empty /etc/dracut.conf.d/acpi 2>/dev/null || true
rm -f /var/lib/acpi-override/gpu-off.aml
rm -f /etc/initramfs-tools/hooks/gpu-kill

log_success "Removed installed configuration files."

# Clean kernel command line parameters on Arch / EndeavourOS
CMDLINE_FILE="/etc/kernel/cmdline"
if [[ -f "$CMDLINE_FILE" ]]; then
    sed -i 's/rd\.driver\.blacklist=[^ ]*//g' "$CMDLINE_FILE"
    sed -i 's/modprobe\.blacklist=[^ ]*//g' "$CMDLINE_FILE"
    sed -i 's/systemd\.mask=nvidia-fallback\.service//g' "$CMDLINE_FILE"
    sed -i 's/  */ /g; s/^ *//; s/ *$//' "$CMDLINE_FILE"
    log_success "Cleaned dGPU blacklist parameters from $CMDLINE_FILE."
fi

# Clean kernel command line parameters on Fedora (grubby)
if command -v grubby &>/dev/null; then
    grubby --update-kernel=ALL --remove-args="rd.driver.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset modprobe.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset systemd.mask=nvidia-fallback.service" 2>/dev/null || true
    log_success "Cleaned kernel arguments via grubby."
fi

# Clean kernel command line parameters on Debian / Ubuntu (/etc/default/grub)
GRUB_DEFAULTS="/etc/default/grub"
if [[ -f "$GRUB_DEFAULTS" ]] && grep -q "rd.driver.blacklist=" "$GRUB_DEFAULTS"; then
    sed -i 's/rd\.driver\.blacklist=[^ "]*//g' "$GRUB_DEFAULTS"
    sed -i 's/modprobe\.blacklist=[^ "]*//g' "$GRUB_DEFAULTS"
    sed -i 's/systemd\.mask=nvidia-fallback\.service//g' "$GRUB_DEFAULTS"
    sed -i 's/  */ /g; s/" /"/g; s/ "/"/g' "$GRUB_DEFAULTS"
    log_success "Cleaned dGPU blacklist parameters from $GRUB_DEFAULTS."
fi

log_info "Rebuilding initramfs image..."
if command -v dracut-rebuild &>/dev/null; then
    dracut-rebuild
elif command -v dracut &>/dev/null; then
    dracut -f --regenerate-all
elif command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k all
fi

if command -v update-grub &>/dev/null; then
    log_info "Updating GRUB bootloader..."
    update-grub
fi

if command -v reinstall-kernels &>/dev/null; then
    log_info "Refreshing kernel entries..."
    reinstall-kernels
fi

log_success "Uninstallation complete. Reboot your computer to restore NVIDIA dGPU functionality."
