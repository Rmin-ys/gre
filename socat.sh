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

# --- Function: Kernel Optimization ---
optimize_kernel() {
    echo -e "${YELLOW}Applying Kernel optimizations...${NC}"
    cat <<EOF > /etc/sysctl.d/99-tunnel-optimize.conf
fs.file-max = 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
EOF
    sysctl --system > /dev/null
    echo -e "${GREEN}Kernel Optimized.${NC}"
}

# --- Function: Create Tunnel (GRE/SIT) ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Tunnel Setup ---${NC}"
    read -p "Protocol (1:GRE, 2:SIT): " p
    MODE=$([[ "$p" == "2" ]] && echo "sit" || echo "gre")
    read -p "Tunnel Number (1-9): " NUM
    read -p "Local IP: " L_IP
    read -p "Remote IP: " R_IP
    read -p "Internal IP: " I_IP
    
    # MTU Fixed at 1400 for reliability
    TUN_MTU=1400
    TUN_MSS=1360
    NAME="${MODE}${NUM}"

    ip tunnel add $NAME mode $MODE remote $R_IP local $L_IP ttl 255
    ip addr add $I_IP/30 dev $NAME
    ip link set $NAME mtu $TUN_MTU up
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o $NAME -j TCPMSS --set-mss $TUN_MSS

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

# --- Function: Add Port Forward (Socat - Supports UDP/TCP) ---
add_socat_forward() {
    if ! command -v socat &> /dev/null; then
        apt-get update && apt-get install -y socat
    fi

    echo -e "\n${YELLOW}--- Socat Forwarding ---${NC}"
    read -p "Local Port to open: " LPORT
    read -p "Remote Tunnel IP: " RIP
    read -p "Remote Destination Port: " RPORT
    read -p "Protocol (tcp/udp): " PROTO

    SERVICE_NAME="fw-${LPORT}-${PROTO}"

    cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Socat Forward $LPORT $PROTO
After=network.target tun-gre1.service tun-sit1.service

[Service]
Type=simple
ExecStart=/usr/bin/socat ${PROTO^^}-LISTEN:$LPORT,fork,reuseaddr ${PROTO^^}:$RIP:$RPORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable --now $SERVICE_NAME
    echo -e "${GREEN}Success: Port $LPORT ($PROTO) forwarded to $RIP:$RPORT${NC}"
}

# --- Main Menu ---
while true; do
    clear
    echo -e "${GREEN}############################################${NC}"
    echo -e "${GREEN}#    Sepehr Socat Forwarder (UDP/TCP)      #${NC}"
    echo -e "${GREEN}############################################${NC}"
    echo -e "1) Setup Tunnel (GRE/SIT)"
    echo -e "2) Apply Kernel Network Tweaks"
    echo -e "3) Add Port Forward (Socat)"
    echo -e "4) Uninstall & Clean All"
    echo -e "5) Exit"
    read -p "Select option: " choice

    case $choice in
        1) create_tunnel; read -p "Press Enter...";;
        2) optimize_kernel; read -p "Press Enter...";;
        3) add_socat_forward; read -p "Press Enter...";;
        4) 
            systemctl stop tun-* fw-* 2>/dev/null
            rm /etc/systemd/system/tun-* /etc/systemd/system/fw-* 2>/dev/null
            echo -e "${GREEN}Cleaned.${NC}"; sleep 2 ;;
        5) exit 0 ;;
    esac
done
