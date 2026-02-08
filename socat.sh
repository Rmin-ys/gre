#!/bin/bash

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Function: Socat Service Creation ---
add_socat_forward() {
    if ! command -v socat &> /dev/null; then
        apt-get update && apt-get install -y socat
    fi

    read -p "Enter Local Port to listen: " LPORT
    read -p "Enter Remote Tunnel IP: " RIP
    read -p "Enter Remote Port: " RPORT
    read -p "Protocol (tcp/udp): " PROTO

    SERVICE_NAME="forward-$LPORT-$PROTO"

    cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Socat Forward Port $LPORT $PROTO
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat ${PROTO^^}-LISTEN:$LPORT,fork,reuseaddr ${PROTO^^}:$RIP:$RPORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable --now $SERVICE_NAME
    echo -e "${GREEN}Port $LPORT ($PROTO) forwarded to $RIP:$RPORT${NC}"
}

# --- بقیه توابع مشابه gre.sh خواهد بود ---
