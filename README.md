# VPN Kill Switch Script (Linux)

## Features
- Blocks all outgoing IPv4 traffic except through the VPN interface tun0 created by OpenVPN.
- Allows traffic to whitelisted IPs.
- Disables IPv6 system-wide to prevent leaks.
- Cleans up iptables and ipset rules when disabled.

  ## Requirements
- Linux system with `iptables` and `ipset` installed.
- Root privileges (`sudo`) to modify network rules.

  ## Setup
  1. Save the script killswitch.sh
  2. Make it executable:
     ```bash
     chmod +x killswitch.sh
     ```
  3. Create a whitelist file in the same directory `whitelisted_ips.txt`
 
  ## Usage

  Enable the kill switch using:

  ```bash
  sudo ./killswitch.sh enable
  ```
  Disable the kill switch:
  ```bash
  sudo ./killswitch.sh disable
  ```


     
