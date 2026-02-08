#!/bin/bash

# --- Colors for UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Check Root Access ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# --- Function: MTU & MSS Setup ---
setup_mtu_mss() {
    echo -e "\n${YELLOW}--- Network Optimization ---${NC}"
    echo -e "1) Automatic MTU (1400)"
    echo -e "2) Custom MTU"
    read -p "Select option: " mtu_mode
    TUN_MTU=$([[ "$mtu_mode" == "2" ]] && read -p "Value: " v && echo $v || echo 1400)
    TUN_MSS=$((TUN_MTU - 40))
}

# --- Function: Create Tunnel (SIT/GRE) ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Protocol ---${NC} 1) GRE 2) SIT"
    read -p "Choice: " p
    MODE=$([[ "$p" == "2" ]] && echo "sit" || echo "gre")
    read -p "Tunnel Num (1-9): " NUM
    read -p "Local IP: " L_IP
    read -p "Remote IP: " R_IP
    read -p "Internal IP (e.g. 10.0.0.1): " I_IP
    
    NAME="${MODE}${NUM}"
    ip tunnel add $NAME mode $MODE remote $R_IP local $L_IP ttl 255
    ip addr add $I_IP/30 dev $NAME
    ip link set $NAME mtu $TUN_MTU up
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS

    # Systemd Service
    cat <<EOF > /etc/systemd/system/tun-$NAME.service
[Unit]
Description=$MODE Tunnel $NAME
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip tunnel add $NAME mode $MODE remote $R_IP local $L_IP ttl 255
ExecStart=/sbin/ip addr add $I_IP/30 dev $NAME
ExecStart=/sbin/ip link set $NAME mtu $TUN_MTU up
ExecStart=/sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS
ExecStop=/sbin/ip link set $NAME down
ExecStop=/sbin/ip tunnel del $NAME
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable tun-$NAME.service
    echo -e "${GREEN}Tunnel $NAME established!${NC}"
}

# --- Function: Live Monitoring ---
live_monitor() {
    echo -e "${YELLOW}Entering Live Monitor... (Press CTRL+C to exit)${NC}"
    sleep 2
    while true; do
        clear
        echo -e "${BLUE}============================================${NC}"
        echo -e "${BLUE}        Tunnel Live Monitoring Dashboard     ${NC}"
        echo -e "${BLUE}============================================${NC}"
        
        # Check Interfaces
        echo -e "${YELLOW}Active Interfaces:${NC}"
        ip -brief addr show | grep -E 'gre|sit' || echo "No active tunnels found."
        
        echo -e "\n${YELLOW}Internal Connectivity (Ping):${NC}"
        # سعی می‌کند اولین IP داخلی پیدا شده را پینگ کند
        INT_IP=$(ip addr show | grep -oP '(?<=inet )10\.\d+\.\d+\.\d+' | head -n 1)
        if [ ! -z "$INT_IP" ]; then
            ping -c 1 -W 1 $INT_IP > /dev/null
            if [ $? -eq 0 ]; then
                echo -e "Internal IP ($INT_IP): ${GREEN}CONNECTED${NC}"
            else
                echo -e "Internal IP ($INT_IP): ${RED}DISCONNECTED${NC}"
            fi
        else
            echo "No internal IP detected."
        fi

        echo -e "\n${YELLOW}Traffic Statistics:${NC}"
        if command -v ifstat &> /dev/null; then
            ifstat 1 1 | tail -n 1
        else
            cat /proc/net/dev | grep -E 'gre|sit' | awk '{print "Interface: "$1" | RX: "$2" bytes | TX: "$10" bytes"}'
        fi
        
        echo -e "\n${BLUE}============================================${NC}"
        sleep 3
    done
}

# --- Main Menu ---
while true; do
    clear
    echo -e "${GREEN}############################################${NC}"
    echo -e "${GREEN}#      Sepehr Forwarder Pro V1.6 (Monitor) #${NC}"
    echo -e "${GREEN}############################################${NC}"
    echo -e "1) Setup Tunnel (GRE/SIT)"
    echo -e "2) Live Monitoring Dashboard"
    echo -e "3) Uninstall & Clean All"
    echo -e "4) Exit"
    read -p "Select option: " choice

    case $choice in
        1) setup_mtu_mss; create_tunnel; read -p "Press Enter...";;
        2) live_monitor ;;
        3) 
            systemctl stop tun-* 2>/dev/null
            rm /etc/systemd/system/tun-* 2>/dev/null
            echo -e "${GREEN}System cleaned.${NC}"; sleep 2 ;;
        4) exit 0 ;;
    esac
done
