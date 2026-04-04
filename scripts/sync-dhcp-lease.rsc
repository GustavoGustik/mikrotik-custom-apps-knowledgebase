# RouterOS Script: Sync VETH MAC address with DHCP lease
# Purpose: When an app is recreated, the VETH MAC changes.
#          This script automatically updates the static DHCP lease.
# Usage:  /import sync-dhcp-lease.rsc
#         Runs on startup and can be scheduled hourly.
#
# Customize these variables:
#   vethName    - The VETH interface name (e.g., "veth-app-unifi")
#   desiredIP   - The static IP you want the app to have
#   leaseComment - Comment to identify the lease
#   dhcpServer  - Your DHCP server name (usually "dhcp1")

:local vethName "veth-app-unifi"
:local desiredIP "192.168.128.54"
:local leaseComment "app-unifi"
:local dhcpServer "dhcp1"

# Get current VETH MAC
:local currentMAC
:do {
  :set currentMAC [/interface/veth/get [find where name=$vethName] mac-address]
} on-error={
  :log warning ("sync-dhcp-lease: VETH $vethName not found")
  :error "VETH not found"
}

# Check if lease exists
:local leaseId [/ip/dhcp-server/lease/find where comment=$leaseComment]

:if ([:len $leaseId] = 0) do={
  # Create new lease
  /ip/dhcp-server/lease/add \
    address=$desiredIP \
    mac-address=$currentMAC \
    server=$dhcpServer \
    comment=$leaseComment
  :log info ("sync-dhcp-lease: Created lease for $leaseComment -> $desiredIP (MAC: $currentMAC)")
} else={
  # Check if MAC needs updating
  :local existingMAC [/ip/dhcp-server/lease/get $leaseId mac-address]
  :if ($existingMAC != $currentMAC) do={
    /ip/dhcp-server/lease/set $leaseId mac-address=$currentMAC
    :log info ("sync-dhcp-lease: Updated MAC for $leaseComment from $existingMAC to $currentMAC")
  } else={
    :log info ("sync-dhcp-lease: Lease for $leaseComment is up to date")
  }
}
