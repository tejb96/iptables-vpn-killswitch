#!/bin/bash
# This script acts as a VPN kill switch using iptables and disables IPv6 via sysctl.
# It assumes your VPN interface is 'tun0' (change if needed, e.g., 'wg0' for WireGuard).
# Run with sudo: sudo ./killswitch.sh enable or sudo ./killswitch.sh disable

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Define the VPN interface
VPN_INTERFACE="tun0"
# Define the path to the whitelisted IPs file
WHITELISTED_IPS="/whitelisted_ips.txt"

# Create an ipset for whitelisted IPs
ipset create vpn_whitelist hash:ip 2>/dev/null

# Function to read whitelisted IPs from file and add to ipset
add_whitelisted_ips() {
    if [ -f "$WHITELISTED_IPS" ]; then
        echo "Adding whitelisted IPs from $WHITELISTED_IPS to ipset..."
       while IFS= read -r ip || [ -n "$ip" ]; do
            # strip comments and whitespace
            ip="${ip%%#*}"
            ip="${ip#"${ip%%[![:space:]]*}"}"   # ltrim
            ip="${ip%"${ip##*[![:space:]]}"}"   # rtrim
            [ -z "$ip" ] && continue

           
            ipset add vpn_whitelist "$ip" -exist 2>/dev/null
        done < "$WHITELISTED_IPS"
    else
        echo "No whitelisted IPs file found at $WHITELISTED_IPS."
    fi
}

# Function to disable IPv6 system-wide
disable_ipv6() {
    echo "Disabling IPv6 system-wide via sysctl..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
    sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null
}

# Function to enable IPv6 system-wide
enable_ipv6() {
    echo "Re-enabling IPv6 system-wide via sysctl..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null
}

# Function to enable the kill switch
enable_killswitch() {
    # Disable IPv6 completely
    disable_ipv6

    add_whitelisted_ips 
    
    # Flush existing OUTPUT chain
    iptables -F OUTPUT 2>/dev/null
    iptables -Z OUTPUT 2>/dev/null

    # Allow loopback traffic (local communication)
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow traffic to whitelisted IPs
    iptables -A OUTPUT -m set --match-set vpn_whitelist dst -j ACCEPT

    # Allow traffic through the VPN interface
    iptables -A OUTPUT -o "$VPN_INTERFACE" -j ACCEPT

    # Drop all other outgoing IPv4 traffic
    iptables -A OUTPUT -j DROP

    echo "Kill switch enabled."
    echo "  - IPv6 is DISABLED system-wide."
    echo "  - Internet access blocked except via $VPN_INTERFACE (IPv4 only)."
}

# Function to disable the kill switch
disable_killswitch() {
    # Re-enable IPv6
    enable_ipv6

    # Remove IPv4 rules in reverse order
    iptables -D OUTPUT -j DROP 2>/dev/null
    iptables -D OUTPUT -o "$VPN_INTERFACE" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -m set --match-set vpn_whitelist dst -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null

    # Flush any leftover rules in OUTPUT chain
    iptables -F OUTPUT 2>/dev/null
    iptables -Z OUTPUT 2>/dev/null

    # clean up ipset
    if ipset list vpn_whitelist >/dev/null 2>&1; then
        echo "Destroying ipset 'vpn_whitelist'..."
        ipset destroy vpn_whitelist 2>/dev/null || true
    fi

    echo "Kill switch disabled. Normal internet access restored (IPv4 + IPv6)."
}

# Check command-line argument
case "$1" in
    enable)
        enable_killswitch
        ;;
    disable)
        disable_killswitch
        ;;
    *)
        echo "Usage: sudo $0 {enable|disable}"
        exit 1
        ;;
esac
