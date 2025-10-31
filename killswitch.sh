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

    # Flush existing OUTPUT chain
    iptables -F OUTPUT 2>/dev/null
    iptables -Z OUTPUT 2>/dev/null

    # Allow loopback traffic (local communication)
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

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

    # Remove IPv4 rules in reverse order (safely)
    iptables -D OUTPUT -j DROP 2>/dev/null
    iptables -D OUTPUT -o "$VPN_INTERFACE" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null

    # Flush any leftover rules in OUTPUT chain
    iptables -F OUTPUT 2>/dev/null

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