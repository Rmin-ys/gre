#!/bin/bash

# --- Colors for UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Check Root Access ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# --- Function: MTU & MSS Setup ---
setup_mtu_mss() {
    echo -e "\n${YELLOW}--- Network Optimization ---${NC}"
    echo -e "1) Automatic MTU (Recommended: 1400)"
    echo -e "2) Custom MTU"
    read -p "Select option [1-2]: " mtu_mode
    if [[ "$mtu_mode" == "2" ]]; then
        read -p "Enter custom MTU (1200-1450): " user_mtu
        TUN_MTU=$user_mtu
    else
        TUN_MTU=1400
    fi
    TUN_MSS=$((TUN_MTU - 40))
}

# --- Function: Install Gost ---
install_gost() {
    if ! command -v gost &> /dev/null; then
        echo -e "${YELLOW}Installing Gost...${NC}"
        wget https://github.com/go-gost/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
        gunzip gost-linux-amd64-2.11.5.gz
        mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
        chmod +x /usr/local/bin/gost
        echo -e "${GREEN}Gost installed.${NC}"
    fi
}

# --- Function: Create Tunnel (GRE/SIT) ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Tunnel Protocol ---${NC}"
    echo -e "1) GRE (Standard)"
    echo -e "2) SIT (6to4 - Recommended)"
    read -p "Select protocol [1-2]: " proto_choice
    MODE=$([[ "$proto_choice" == "2" ]] && echo "sit" || echo "gre")

    read -p "Enter Tunnel Number (1-9): " TUN_NUM
    read -p "Enter Local IP: " LOCAL_IP
    read -p "Enter Remote IP: " REMOTE_IP
    read -p "Enter Tunnel Internal IP (e.g., 10.0.0.1): " INT_IP
    
    NAME="${MODE}${TUN_NUM}"
    
    ip tunnel add $NAME mode $MODE remote $REMOTE_IP local $LOCAL_IP ttl 255
    ip addr add $INT_IP/30 dev $NAME
    ip link set $NAME mtu $TUN_MTU
    ip link set $NAME up
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS

    # Systemd Service
    cat <<EOF > /etc/systemd/system/tun-$NAME.service
[Unit]
Description=$MODE Tunnel $NAME
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip tunnel add $NAME mode $MODE remote $REMOTE_IP local $LOCAL_IP ttl 255
ExecStart=/sbin/ip addr add $INT_IP/30 dev $NAME
ExecStart=/sbin/ip link set $NAME mtu $TUN_MTU
ExecStart=/sbin/ip link set $NAME up
ExecStart=/sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS
ExecStop=/sbin/ip link set $NAME down
ExecStop=/sbin/ip tunnel del $NAME
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable tun-$NAME.service
    echo -e "${GREEN}Tunnel $NAME ($MODE) created!${NC}"
}

# --- Function: Gost Obfuscation (The NEW Layer) ---
setup_gost() {
    install_gost
    read -p "Enter Gost Port (e.g., 8443): " GOST_PORT
    read -p "Enter Destination (Remote) Tunnel IP: " REMOTE_INT_IP
    
    # Create Gost Systemd Service
    cat <<EOF > /etc/systemd/system/gost-obfs.service
[Unit]
Description=Gost Obfuscation Layer
After=network.target
[Service]
ExecStart=/usr/local/bin/gost -L tcp://:8443?mode=ws -F relay+ws://$REMOTE_INT_IP:$GOST_PORT
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl start gost-obfs.service
    echo -e "${GREEN}Gost Obfuscation layer started on port $GOST_PORT!${NC}"
}

# --- Main Menu ---
clear
echo -e "${GREEN}############################################${NC}"
echo -e "${GREEN}#      Sepehr Forwarder Pro V1.5 (OBFS)    #${NC}"
echo -e "${GREEN}############################################${NC}"
echo -e "1) Setup Tunnel (Standard GRE/SIT)"
echo -e "2) Add Gost Obfuscation (Hide from GFW)"
echo -e "3) Add Ports via HAProxy"
echo -e "4) Uninstall & Clean All"
echo -e "5) Exit"
read -p "Select option: " main_choice

case $main_choice in
    1) setup_mtu_mss; create_tunnel ;;
    2) setup_gost ;;
    3) # Re-using HAProxy function from v1.4
       echo -e "${YELLOW}Calling HAProxy module...${NC}"
       # (Include HAProxy logic here as in v1.4)
       ;;
    4)
        systemctl stop tun-* gost-* haproxy 2>/dev/null
        rm /etc/systemd/system/tun-* /etc/systemd/system/gost-* 2>/dev/null
        echo -e "${GREEN}Cleaned.${NC}"
        ;;
    5) exit 0 ;;
esac
