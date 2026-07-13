#!/bin/bash
# unode/configure-bind-primary.sh
# Configures BIND9 as the primary (authoritative) DNS server for the domain.
# Forward zone: Xnetwork.net
# Reverse zone: X.168.192.in-addr.arpa
# Forwards unknown queries to the caching server on gateway (192.168.X.5)

set -euo pipefail

X="${1:-33}"
DOMAIN="${2:-${X}network.net}"
NODE1_EXT_IP="192.168.${X}.6"
NODE2_INT_IP="192.168.${X}.133"
GATEWAY_EXT_IP="192.168.${X}.5"

echo "[BIND] Installing BIND9 and DNS utilities..."
apt update && apt install -y bind9 bind9utils dnsutils

echo "[BIND] Configuring named.conf.options..."
cat > /etc/bind/named.conf.options <<BINDEOF
acl "trusted" {
    127.0.0.0/8;
    192.168.${X}.0/25;
    192.168.${X}.128/25;
};

options {
    directory "/var/cache/bind";

    listen-on { 127.0.0.1; ${NODE2_INT_IP}; };
    listen-on-v6 { none; };

    # Forward all non-authoritative queries to gateway caching forwarder
    forwarders {
        ${GATEWAY_EXT_IP};
    };
    forward only;

    recursion yes;
    allow-query { trusted; };
    allow-recursion { trusted; };

    # Allow zone transfer only to secondary (node1)
    allow-transfer { ${NODE1_EXT_IP}; };

    # CIS 2.4
    version "Not available";

    dnssec-validation auto;

    # CIS 2.5
    zone-statistics no;

    # CIS 2.7
    minimal-responses yes;

    // CIS 2.8 - query logging configured below
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

echo "[BIND] Configuring named.conf.local with forward and reverse zones..."
cat > /etc/bind/named.conf.local <<LOCALEOF
zone "${DOMAIN}" {
    type primary;
    file "/etc/bind/db.${DOMAIN}";
    allow-transfer { ${NODE1_EXT_IP}; };
    notify yes;
    also-notify { ${NODE1_EXT_IP}; };
};

zone "${X}.168.192.in-addr.arpa" {
    type primary;
    file "/etc/bind/db.${X}";
    allow-transfer { ${NODE1_EXT_IP}; };
    notify yes;
    also-notify { ${NODE1_EXT_IP}; };
};
LOCALEOF

echo "[BIND] Creating forward zone file..."
cat > "/etc/bind/db.${DOMAIN}" <<ZONEEOF
\$TTL    604800
@       IN      SOA     node2.${DOMAIN}. admin.${DOMAIN}. (
                    $(date +%Y%m%d%H) ; Serial
                    604800        ; Refresh
                    86400         ; Retry
                    2419200       ; Expire
                    604800        ; Negative Cache TTL
)

; Name servers
@       IN      NS      node2.${DOMAIN}.
@       IN      NS      node1.${DOMAIN}.

; A records
gateway IN      A       ${GATEWAY_EXT_IP}
node1   IN      A       ${NODE1_EXT_IP}
node2   IN      A       ${NODE2_INT_IP}

; Canonical names (CNAME)
www     IN      CNAME   gateway
ZONEEOF

echo "[BIND] Creating reverse zone file..."
cat > "/etc/bind/db.${X}" <<REVEOF
\$TTL    604800
@       IN      SOA     node2.${DOMAIN}. admin.${DOMAIN}. (
                    $(date +%Y%m%d%H) ; Serial
                    604800        ; Refresh
                    86400         ; Retry
                    2419200       ; Expire
                    604800        ; Negative Cache TTL
)

; Name servers
@       IN      NS      node2.${DOMAIN}.
@       IN      NS      node1.${DOMAIN}.

; PTR records (last octet -> FQDN)
5       IN      PTR     gateway.${DOMAIN}.
6       IN      PTR     node1.${DOMAIN}.
133     IN      PTR     node2.${DOMAIN}.
REVEOF

# Create log directory
mkdir -p /var/log/bind
chown bind:bind /var/log/bind
chmod 750 /var/log/bind

echo "[BIND] Checking named configuration..."
named-checkconf /etc/bind/named.conf
named-checkzone "${DOMAIN}" "/etc/bind/db.${DOMAIN}"
named-checkzone "${X}.168.192.in-addr.arpa" "/etc/bind/db.${X}"

echo "[BIND] Restarting BIND9..."
systemctl enable named
systemctl restart named

echo "[BIND] Primary DNS server configured successfully."
echo "  Domain: ${DOMAIN}"
echo "  Forward zone: /etc/bind/db.${DOMAIN}"
echo "  Reverse zone: /etc/bind/db.${X}"
echo "  Secondary (node1): ${NODE1_EXT_IP}"
echo "  Forwarder: ${GATEWAY_EXT_IP}"
