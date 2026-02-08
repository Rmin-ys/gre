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

# --- Function: Kernel Optimization (The Final Piece) ---
optimize_kernel() {
    echo -e "${YELLOW}Applying deep Kernel optimizations...${NC}"
    
    # Backup sysctl
    cp /etc/sysctl.conf /etc/sysctl.conf.bak

    cat <<EOF > /etc/sysctl.d/99-tunnel-optimize.conf
# افزایش حداکثر تعداد فایل‌های باز
fs.file-max = 67108864

# بهینه‌سازی بافرهای TCP برای سرعت‌های بالا و پکت‌لاست
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# فعال‌سازی Fast Open برای کاهش تاخیر دست‌خالی (Handshake)
net.ipv4.tcp_fastopen = 3

# تنظیمات Keepalive برای زنده نگه داشتن تونل در زمان سکوت
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# بهینه‌سازی الگوریتم ازدحام (BBR)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# جلوگیری از حملات ساده و بهبود امنیت لایه شبکه
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
EOF

    sysctl --system > /dev/null
    echo -e "${GREEN}Kernel optimizations applied successfully!${NC}"
}

# --- Function: MTU & MSS Setup ---
setup_mtu_mss() {
    echo -e "\n${YELLOW}--- Network Optimization ---${NC}"
    echo -e "1) Automatic MTU (1400)"
    echo -e "2) Custom MTU"
    read -p "Select option: " mtu_mode
    if [[ "$mtu_mode" == "2" ]]; then
        read -p "Value: " v
        TUN_MTU=$v
    else
        TUN_MTU=1400
    fi
    TUN_MSS=$((TUN_MTU - 40))
}

# --- Function: Create Tunnel ---
create_tunnel() {
    echo -e "\n${YELLOW}--- Protocol ---${NC} 1) GRE 2) SIT"
    read -p "Choice: " p
    MODE=$([[ "$p" == "2" ]] && echo "sit" || echo "gre")
    read -p "Tunnel Num (1-9): " NUM
    read -p "Local IP: " L_IP
    read -p "Remote IP: " R_IP
    read -p "Internal IP: " I_IP
    
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

# --- Function: Dashboard ---
live_monitor() {
    echo -e "${YELLOW}Entering Live Monitor... (CTRL+C to exit)${NC}"
    sleep 2
    while true; do
        clear
        echo -e "${BLUE}============================================${NC}"
        echo -e "${BLUE}        Tunnel Pro Monitoring Dashboard      ${NC}"
        echo -e "${BLUE}============================================${NC}"
        echo -e "${YELLOW}Interfaces:${NC}"
        ip -brief addr show | grep -E 'gre|sit'
        echo -e "\n${YELLOW}Kernel Optimization Status:${NC}"
        sysctl net.ipv4.tcp_congestion_control
        echo -e "\n${YELLOW}Traffic (Last 3 sec):${NC}"
        cat /proc/net/dev | grep -E 'gre|sit' | awk '{print "IF: "$1" | RX: "$2" B | TX: "$10" B"}'
        echo -e "${BLUE}============================================${NC}"
        sleep 3
    done
}

# --- Main Menu ---
while true; do
    clear
    echo -e "${GREEN}############################################${NC}"
    echo -e "${GREEN}#      Sepehr Forwarder Pro V1.7 (Full)    #${NC}"
    echo -e "${GREEN}############################################${NC}"
    echo -e "1) Setup Tunnel (GRE/SIT) + MTU Optimization"
    echo -e "2) Apply Kernel Network Tweaks (Optimize Speed)"
    echo -e "3) Live Monitoring Dashboard"
    echo -e "4) Uninstall & Clean All"
    echo -e "5) Exit"
    read -p "Select option: " choice

    case $choice in
        1) setup_mtu_mss; create_tunnel; read -p "Press Enter...";;
        2) optimize_kernel; read -p "Press Enter...";;
        3) live_monitor ;;
        4) 
            systemctl stop tun-* 2>/dev/null
            rm /etc/systemd/system/tun-* /etc/sysctl.d/99-tunnel-optimize.conf 2>/dev/null
            sysctl --system > /dev/null
            echo -e "${GREEN}System cleaned.${NC}"; sleep 2 ;;
        5) exit 0 ;;
    esac
done
