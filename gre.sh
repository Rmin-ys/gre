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

# --- Function: Create Tunnel (GRE or SIT) ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Tunnel Protocol ---${NC}"
    echo -e "1) GRE (Standard)"
    echo -e "2) SIT (6to4 - More stable against GFW)"
    read -p "Select protocol [1-2]: " proto_choice
    
    if [[ "$proto_choice" == "2" ]]; then
        MODE="sit"
    else
        MODE="gre"
    fi

    read -p "Enter Tunnel Number (1-9): " TUN_NUM
    read -p "Enter Local IP (This Server): " LOCAL_IP
    read -p "Enter Remote IP (Other Server): " REMOTE_IP
    read -p "Enter Tunnel Internal IP (e.g., 10.0.0.1): " INT_IP
    
    NAME="${MODE}${TUN_NUM}"
    
    # اجرای دستورات ساخت تونل
    ip tunnel add $NAME mode $MODE remote $REMOTE_IP local $LOCAL_IP ttl 255
    ip addr add $INT_IP/30 dev $NAME
    ip link set $NAME mtu $TUN_MTU
    ip link set $NAME up
    
    # اعمال MSS Clamping
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS
    
    # سیستم پایداری (Systemd)
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
    systemctl daemon-reload
    systemctl enable tun-$NAME.service
    echo -e "${GREEN}Tunnel $NAME ($MODE) created successfully!${NC}"
}

# --- Function: Add Port Forward (HAProxy) ---
add_port_forward() {
    install_haproxy
    read -p "Enter Destination (Remote) Tunnel IP: " REMOTE_INT_IP
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
    echo -e "${GREEN}Ports forwarded via HAProxy!${NC}"
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
echo -e "${GREEN}#      Sepehr Forwarder Pro V1.4 (SIT)     #${NC}"
echo -e "${GREEN}############################################${NC}"
echo -e "1) Setup Tunnel & Forwarding (IRAN)"
echo -e "2) Setup Tunnel Only (KHAREJ)"
echo -e "3) Add Ports to existing Setup"
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
        echo -e "${RED}Cleaning all tunnels and configs...${NC}"
        systemctl stop tun-* haproxy 2>/dev/null
        systemctl disable tun-* 2>/dev/null
        rm /etc/systemd/system/tun-* 2>/dev/null
        truncate -s 0 /etc/haproxy/haproxy.cfg
        echo -e "${GREEN}All cleaned up.${NC}"
        ;;
    5) exit 0 ;;
esac
