#!/usr/bin/env bash
# ==============================================================================
# Lenovo Legion 5 Pro (16ACH6H / 82JQ) - NVIDIA dGPU Hard Power-Off Installer
# Native ACPI Table Upgrade + udev PCI removal (D3cold state)
# Tested on: Lenovo Legion 5 Pro 16ACH6H (Type 82JQ)
# Supported Distros: Arch Linux / EndeavourOS, Fedora, Debian / Ubuntu
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_YES=false

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (e.g. sudo ./install.sh)"
        exit 1
    fi
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            -y|--yes|--force)
                FORCE_YES=true
                ;;
            -h|--help)
                echo "Usage: sudo ./install.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -y, --yes, --force    Skip hardware confirmation prompt"
                echo "  -h, --help            Show this help message"
                exit 0
                ;;
        esac
    done
}

check_hardware() {
    local product_name=""
    local product_version=""
    
    [[ -f /sys/class/dmi/id/product_name ]] && product_name="$(tr -d '\0' < /sys/class/dmi/id/product_name | xargs)"
    [[ -f /sys/class/dmi/id/product_version ]] && product_version="$(tr -d '\0' < /sys/class/dmi/id/product_version | xargs)"

    log_info "Detected hardware: ${product_name:-Unknown} (${product_version:-Unknown})"

    if [[ "$product_name" == *"82JQ"* ]] || [[ "$product_version" == *"16ACH6H"* ]]; then
        log_success "Target model confirmed: Lenovo Legion 5 Pro 16ACH6H (82JQ)"
    else
        log_warn "==================================================================="
        log_warn "COMPATIBILITY WARNING:"
        log_warn "This patch was specifically engineered and tested on:"
        log_warn "  Lenovo Legion 5 Pro 16ACH6H (Model 82JQ)"
        log_warn ""
        log_warn "Other Lenovo models or motherboard revisions may have a different"
        log_warn "ACPI device hierarchy (e.g. not \\_SB.PCI0.GPP0.PEGP) or power gating"
        log_warn "variables (OPCE). Applying this on unsupported hardware might cause"
        log_warn "boot delays or leave the dGPU powered on."
        log_warn "==================================================================="
        
        if [[ "$FORCE_YES" != true ]]; then
            read -r -p "Do you want to proceed anyway? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[yY]$ ]]; then
                log_info "Installation aborted by user."
                exit 0
            fi
        fi
    fi
}

detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot find /etc/os-release. Distribution unknown."
        exit 1
    fi

    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"

    log_info "Detected OS: ${PRETTY_NAME:-$DISTRO_ID}"

    if [[ "$DISTRO_ID" =~ (arch|endeavouros|manjaro|garuda) ]] || [[ "$DISTRO_LIKE" =~ arch ]]; then
        SYSTEM_TYPE="arch"
    elif [[ "$DISTRO_ID" =~ (fedora|rhel|nobara) ]] || [[ "$DISTRO_LIKE" =~ fedora ]]; then
        SYSTEM_TYPE="fedora"
    elif [[ "$DISTRO_ID" =~ (debian|ubuntu|pop|mint) ]] || [[ "$DISTRO_LIKE" =~ debian ]]; then
        SYSTEM_TYPE="debian"
    else
        log_error "Unsupported distribution family: $DISTRO_ID"
        exit 1
    fi
}

compile_acpi() {
    log_info "Compiling ACPI SSDT DSL table..."
    if ! command -v iasl &>/dev/null; then
        log_warn "iasl compiler not found. Installing dependencies..."
        case "$SYSTEM_TYPE" in
            arch) pacman -S --needed --noconfirm acpica ;;
            fedora) dnf install -y acpica-tools ;;
            debian) apt-get update && apt-get install -y acpica-tools ;;
        esac
    fi

    iasl -tc "$SCRIPT_DIR/common/gpu-off.dsl"
    log_success "Compiled ACPI binary: common/gpu-off.aml"
}

install_common_files() {
    log_info "Installing common configuration files..."
    
    # Modprobe blacklist
    install -Dm644 "$SCRIPT_DIR/common/blacklist-nvidia.conf" /etc/modprobe.d/blacklist-nvidia.conf
    log_success "Installed /etc/modprobe.d/blacklist-nvidia.conf"

    # Udev rule
    install -Dm644 "$SCRIPT_DIR/common/99-nvidia-remove.rules" /etc/udev/rules.d/99-nvidia-remove.rules
    log_success "Installed /etc/udev/rules.d/99-nvidia-remove.rules"
}

install_arch() {
    log_info "Configuring Arch Linux / EndeavourOS (Dracut)..."
    
    mkdir -p /etc/dracut.conf.d/acpi
    install -Dm644 "$SCRIPT_DIR/common/gpu-off.aml" /etc/dracut.conf.d/acpi/gpu-off.aml
    install -Dm644 "$SCRIPT_DIR/distros/arch-dracut/gpu-kill.conf" /etc/dracut.conf.d/gpu-kill.conf
    
    log_success "Installed ACPI override and Dracut configuration"

    # Kernel cmdline parameters
    CMDLINE_FILE="/etc/kernel/cmdline"
    BLACKLIST_CMD="rd.driver.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset modprobe.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset systemd.mask=nvidia-fallback.service"
    
    if [[ -f "$CMDLINE_FILE" ]]; then
        if ! grep -q "rd.driver.blacklist=" "$CMDLINE_FILE"; then
            log_info "Adding blacklist parameters to $CMDLINE_FILE..."
            sed -i "s/$/ $BLACKLIST_CMD/" "$CMDLINE_FILE"
        fi
    else
        log_warn "$CMDLINE_FILE not found. If using systemd-boot, GRUB, or rEFInd, ensure you append these arguments to your kernel cmdline:"
        log_warn "  $BLACKLIST_CMD"
    fi

    log_info "Rebuilding initramfs image..."
    if command -v dracut-rebuild &>/dev/null; then
        dracut-rebuild
    else
        dracut -f --regenerate-all
    fi

    if command -v reinstall-kernels &>/dev/null; then
        log_info "Refreshing bootloader kernel entries (reinstall-kernels)..."
        reinstall-kernels
    fi
}

install_fedora() {
    log_info "Configuring Fedora (Dracut + Grubby)..."
    
    mkdir -p /etc/dracut.conf.d/acpi
    install -Dm644 "$SCRIPT_DIR/common/gpu-off.aml" /etc/dracut.conf.d/acpi/gpu-off.aml
    install -Dm644 "$SCRIPT_DIR/distros/fedora-dracut/gpu-kill.conf" /etc/dracut.conf.d/gpu-kill.conf
    
    log_success "Installed ACPI override into /etc/dracut.conf.d/"

    BLACKLIST_CMD="rd.driver.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset modprobe.blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset systemd.mask=nvidia-fallback.service"
    if command -v grubby &>/dev/null; then
        log_info "Updating kernel command line parameters with grubby..."
        grubby --update-kernel=ALL --args="$BLACKLIST_CMD"
    fi

    log_info "Rebuilding initramfs (Dracut)..."
    dracut -f --regenerate-all
}

install_debian() {
    log_info "Configuring Debian / Ubuntu (initramfs-tools)..."
    
    if ! dpkg -l | grep -q acpi-override-initramfs; then
        log_info "Installing acpi-override-initramfs..."
        apt-get update && apt-get install -y acpi-override-initramfs
    fi

    mkdir -p /var/lib/acpi-override
    install -Dm644 "$SCRIPT_DIR/common/gpu-off.aml" /var/lib/acpi-override/gpu-off.aml
    
    install -Dm755 "$SCRIPT_DIR/distros/debian-initramfs/gpu-kill" /etc/initramfs-tools/hooks/gpu-kill
    log_success "Installed initramfs hook in /etc/initramfs-tools/hooks/gpu-kill"

    log_info "Rebuilding initramfs image..."
    update-initramfs -u -k all
    
    if command -v update-grub &>/dev/null; then
        log_info "Updating GRUB configuration..."
        update-grub
    fi
}

main() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  NVIDIA dGPU Hard Power-Off Installer — Lenovo Legion 5 Pro (82JQ)   ${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    
    parse_args "$@"
    check_root
    check_hardware
    detect_distro
    compile_acpi
    install_common_files

    case "$SYSTEM_TYPE" in
        arch) install_arch ;;
        fedora) install_fedora ;;
        debian) install_debian ;;
    esac

    echo ""
    log_success "Installation completed successfully!"
    log_info "Please reboot your laptop: sudo reboot"
    log_info "After rebooting, verify that the dGPU is gone with: lspci | grep -i nvidia"
}

main "$@"
