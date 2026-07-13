#!/bin/bash
# gateway/configure-bind.sh
# Configures BIND9 as a caching forwarder DNS server.
# All DNS queries from internal/external networks are forwarded here,
# then sent upstream to the internet DNS.

set -euo pipefail

X="${1:-33}"
GATEWAY_EXT_IP="192.168.${X}.5"

echo "[BIND] Installing BIND9 and DNS utilities..."
apt update && apt install -y bind9 bind9utils dnsutils

echo "[BIND] Configuring named.conf.options as caching forwarder..."
cat > /etc/bind/named.conf.options <<BINDEOF
acl "trusted" {
    127.0.0.0/8;
    192.168.${X}.0/25;   # external network
    192.168.${X}.128/25; # internal network
};

options {
    directory "/var/cache/bind";

    # Listen on the external interface and localhost
    listen-on { 127.0.0.1; ${GATEWAY_EXT_IP}; };
    listen-on-v6 { none; };

    # Forward all queries upstream
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    forward only;

    # Recursion for trusted clients only
    recursion yes;
    allow-query { trusted; };
    allow-recursion { trusted; };

    # Do not allow zone transfers
    allow-transfer { none; };

    # Version information hiding (CIS 2.4)
    version "Not available";

    dnssec-validation auto;

    // CIS 2.5 - Disable zone-statistics (if not needed)
    zone-statistics no;

    // CIS 2.7 - Minimal responses
    minimal-responses yes;

    // CIS 2.8 - Disable query logging unless needed for troubleshooting
    // querylog no;
};

logging {
    channel default_log {
        file "/var/log/bind/named.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-severity yes;
        print-category yes;
    };
    category default { default_log; };
    category queries { default_log; };
};
BINDEOF

# Create log directory with proper permissions
mkdir -p /var/log/bind
chown bind:bind /var/log/bind
chmod 750 /var/log/bind

# Check config and restart
echo "[BIND] Checking named configuration..."
named-checkconf /etc/bind/named.conf

echo "[BIND] Restarting BIND9..."
systemctl enable named
systemctl restart named

echo "[BIND] BIND9 caching forwarder configured and running."
echo "  Listening on: ${GATEWAY_EXT_IP}:53 and 127.0.0.1:53"
echo "  Forwarders: 8.8.8.8, 8.8.4.4"
