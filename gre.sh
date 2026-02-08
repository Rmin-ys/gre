#!/bin/bash

# --- Colors for UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Check Root Access ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# --- Function: MTU & MSS Setup ---
setup_mtu_mss() {
    echo -e "\n${YELLOW}--- MTU & MSS Configuration ---${NC}"
    echo -e "1) Automatic (Recommended: 1400)"
    echo -e "2) Manual (Custom value)"
    read -p "Select MTU mode [1-2]: " mtu_mode

    if [[ "$mtu_mode" == "2" ]]; then
        read -p "Enter custom MTU (1200-1450): " user_mtu
        TUN_MTU=$user_mtu
    else
        TUN_MTU=1400
    fi
    
    # Calculate MSS (MTU - 40)
    TUN_MSS=$((TUN_MTU - 40))
    echo -e "${GREEN}MTU set to $TUN_MTU and MSS set to $TUN_MSS${NC}"
}

# --- Function: BBR Activation (Speed Optimization) ---
enable_bbr() {
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${YELLOW}Enabling BBR for better speed...${NC}"
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}BBR Enabled.${NC}"
    fi
}

# --- Main Menu ---
clear
echo -e "${GREEN}############################################${NC}"
echo -e "${GREEN}#      Sepehr GRE Forwarder - Pro V1.1     #${NC}"
echo -e "${GREEN}############################################${NC}"
echo -e "1) IRAN SETUP (Local Server)"
echo -e "2) KHAREJ SETUP (Remote Server)"
echo -e "3) Services Management"
echo -e "4) Uninstall & Clean"
echo -e "5) Exit"
read -p "Select option: " main_choice

case $main_choice in
    1|2)
        # اجرای تنظیمات MTU قبل از شروع ستاپ
        setup_mtu_mss
        enable_bbr
        
        # در اینجا متغیرهای TUN_MTU و TUN_MSS آماده استفاده در بخش ساخت تونل هستند.
        # TODO: اضافه کردن منطق ساخت تونل GRE با استفاده از متغیرهای بالا
        echo -e "\n${GREEN}Ready to setup tunnel with MTU $TUN_MTU...${NC}"
        ;;
    5)
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        ;;
esac
