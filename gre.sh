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
    echo -e "${YELLOW}Applying deep Kernel optimizations...${NC}"
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
    echo -e "${GREEN}Kernel optimizations applied!${NC}"
}

# --- Function: Create Tunnel ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Tunnel Setup ---${NC}"
    read -p "Protocol (1:GRE, 2:SIT): " p
    MODE=$([[ "$p" == "2" ]] && echo "sit" || echo "gre")
    read -p "Tunnel Num (1-9): " NUM
    read -p "Local IP: " L_IP
    read -p "Remote IP: " R_IP
    read -p "Internal IP: " I_IP
    
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

# --- Function: Add Port Forward (HAProxy) ---
add_port_forward() {
    if ! command -v haproxy &> /dev/null; then
        echo -e "${YELLOW}Installing HAProxy...${NC}"
        apt-get update && apt-get install -y haproxy
        systemctl enable haproxy
    fi

    echo -e "\n${YELLOW}--- Port Forwarding (HAProxy) ---${NC}"
    read -p "Enter Remote Tunnel IP (The other server internal IP): " R_INT_IP
    read -p "Enter Ports to forward (e.g., 443,8080 or 2000-2010): " PORTS

    IFS=',' read -ra ADDR <<< "$PORTS"
    for PORT in "${ADDR[@]}"; do
        if [[ $PORT == *"-"* ]]; then
            START_P=$(echo $PORT | cut -d'-' -f1)
            END_P=$(echo $PORT | cut -d'-' -f2)
            for (( p=$START_P; p<=$END_P; p++ )); do
                write_cfg $p $R_INT_IP
            done
        else
            write_cfg $PORT $R_INT_IP
        fi
    done
    systemctl restart haproxy
    echo -e "${GREEN}Ports forwarded successfully!${NC}"
}

write_cfg() {
    local P=$1
    local D=$2
    if ! grep -q "listen port_$P" /etc/haproxy/haproxy.cfg; then
        cat <<EOF >> /etc/haproxy/haproxy.cfg
listen port_$P
    bind *:$P
    mode tcp
    server srv_$P $D:$P
EOF
    fi
}

# --- Function: Live Monitor ---
live_monitor() {
    echo -e "${YELLOW}Entering Live Monitor... (CTRL+C to exit)${NC}"
    sleep 2
    while true; do
        clear
        echo -e "${BLUE}============================================${NC}"
        echo -e "${BLUE}        Tunnel Pro Monitoring Dashboard      ${NC}"
        echo -e "${BLUE}============================================${NC}"
        echo -e "${YELLOW}Active Tunnels:${NC}"
        ip -brief addr show | grep -E 'gre|sit'
        echo -e "\n${YELLOW}Traffic Statistics:${NC}"
        cat /proc/net/dev | grep -E 'gre|sit' | awk '{print "IF: "$1" | RX: "$2" B | TX: "$10" B"}'
        echo -e "${BLUE}============================================${NC}"
        sleep 3
    done
}

# --- Main Menu ---
while true; do
    clear
    echo -e "${GREEN}############################################${NC}"
    echo -e "${GREEN}#      Sepehr Forwarder Pro V1.8 (Full)    #${NC}"
    echo -e "${GREEN}############################################${NC}"
    echo -e "1) Setup Tunnel (GRE/SIT)"
    echo -e "2) Apply Kernel Network Tweaks"
    echo -e "3) Add Port Forwarding (HAProxy)"
    echo -e "4) Live Monitoring Dashboard"
    echo -e "5) Uninstall & Clean All"
    echo -e "6) Exit"
    read -p "Select option: " choice

    case $choice in
        1) create_tunnel; read -p "Press Enter...";;
        2) optimize_kernel; read -p "Press Enter...";;
        3) add_port_forward; read -p "Press Enter...";;
        4) live_monitor ;;
        5) 
            systemctl stop tun-* haproxy 2>/dev/null
            rm /etc/systemd/system/tun-* 2>/dev/null
            truncate -s 0 /etc/haproxy/haproxy.cfg 2>/dev/null
            echo -e "${GREEN}System cleaned.${NC}"; sleep 2 ;;
        6) exit 0 ;;
    esac
done
