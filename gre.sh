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
    TUN_MSS=$((TUN_MTU - 40))
}

# --- Function: BBR Activation ---
enable_bbr() {
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null
    fi
}

# --- Function: Install HAProxy ---
install_haproxy() {
    if ! command -v haproxy &> /dev/null; then
        echo -e "${YELLOW}Installing HAProxy...${NC}"
        apt-get update && apt-get install -y haproxy
        systemctl enable haproxy
    fi
}

# --- Function: Create Tunnel ---
create_tunnel() {
    read -p "Enter GRE Number (1-9): " GRE_NUM
    read -p "Enter Local IP (This Server): " LOCAL_IP
    read -p "Enter Remote IP (Other Server): " REMOTE_IP
    read -p "Enter Tunnel Internal IP (e.g., 10.0.0.1): " INT_IP
    
    TUN_NAME="gre$GRE_NUM"
    
    ip tunnel add $TUN_NAME mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
    ip addr add $INT_IP/30 dev $TUN_NAME
    ip link set $TUN_NAME mtu $TUN_MTU
    ip link set $TUN_NAME up
    
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $TUN_NAME -j TCPMSS --set-mss $TUN_MSS
    
    # Persistence
    cat <<EOF > /etc/systemd/system/tun-$TUN_NAME.service
[Unit]
Description=GRE Tunnel $TUN_NAME
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip tunnel add $TUN_NAME mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
ExecStart=/sbin/ip addr add $INT_IP/30 dev $TUN_NAME
ExecStart=/sbin/ip link set $TUN_NAME mtu $TUN_MTU
ExecStart=/sbin/ip link set $TUN_NAME up
ExecStart=/sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $TUN_NAME -j TCPMSS --set-mss $TUN_MSS
ExecStop=/sbin/ip link set $TUN_NAME down
ExecStop=/sbin/ip tunnel del $TUN_NAME

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable tun-$TUN_NAME.service
    echo -e "${GREEN}Tunnel $TUN_NAME created successfully!${NC}"
}

# --- Function: Add Port Forward (HAProxy) ---
add_port_forward() {
    install_haproxy
    read -p "Enter Destination (Kharej) Tunnel IP: " REMOTE_INT_IP
    read -p "Enter Ports (e.g., 80,443 or 2050-2060): " PORTS
    
    IFS=',' read -ra ADDR <<< "$PORTS"
    for PORT in "${ADDR[@]}"; do
        if [[ $PORT == *"-"* ]]; then
            START_P=$(echo $PORT | cut -d'-' -f1)
            END_P=$(echo $PORT | cut -d'-' -f2)
            for (( p=$START_P; p<=$END_P; p++ )); do
                write_haproxy_cfg $p $REMOTE_INT_IP
            done
        else
            write_haproxy_cfg $PORT $REMOTE_INT_IP
        fi
    done
    systemctl restart haproxy
    echo -e "${GREEN}Ports forwarded successfully!${NC}"
}

write_haproxy_cfg() {
    local PORT=$1
    local DEST=$2
    if ! grep -q "listen port_$PORT" /etc/haproxy/haproxy.cfg; then
        cat <<EOF >> /etc/haproxy/haproxy.cfg

listen port_$PORT
    bind *:$PORT
    mode tcp
    server srv_$PORT $DEST:$PORT
EOF
    fi
}

# --- Main Menu ---
clear
echo -e "${GREEN}############################################${NC}"
echo -e "${GREEN}#      Sepehr GRE Forwarder - Pro V1.3     #${NC}"
echo -e "${GREEN}############################################${NC}"
echo -e "1) IRAN SETUP (Tunnel + Port Forward)"
echo -e "2) KHAREJ SETUP (Tunnel Only)"
echo -e "3) Add New Ports to IRAN"
echo -e "4) Uninstall & Clean All"
echo -e "5) Exit"
read -p "Select option: " main_choice

case $main_choice in
    1)
        setup_mtu_mss
        enable_bbr
        create_tunnel
        add_port_forward
        ;;
    2)
        setup_mtu_mss
        enable_bbr
        create_tunnel
        ;;
    3)
        add_port_forward
        ;;
    4)
        echo -e "${RED}Cleaning all...${NC}"
        systemctl stop tun-gre* haproxy 2>/dev/null
        systemctl disable tun-gre* 2>/dev/null
        rm /etc/systemd/system/tun-gre* 2>/dev/null
        truncate -s 0 /etc/haproxy/haproxy.cfg # Reset HAProxy config
        echo -e "${GREEN}Done.${NC}"
        ;;
    5) exit 0 ;;
esac
