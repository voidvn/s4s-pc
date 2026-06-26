#!/bin/sh
# Resolve the wired NIC (default-route first, else first physical non-wifi/virtual)
# and arm magic-packet Wake-on-LAN. Run at every boot (WoL doesn't survive a reboot)
# AND at shutdown (some Realtek r8169 NICs clear the bit on link-down).
# In a script file $5/$IFACE work normally — unlike inside a systemd ExecStart, where
# a single $ is eaten by systemd's own variable expansion.
IFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
[ -n "$IFACE" ] || IFACE="$(ls /sys/class/net | grep -vE '^(lo|wl|docker|veth|br-|virbr|tap|tun|bond)' | head -n1)"
[ -n "$IFACE" ] || { echo "wol: no wired NIC found"; exit 0; }
if ethtool "$IFACE" 2>/dev/null | grep -qi 'Supports Wake-on:.*g'; then
  ethtool -s "$IFACE" wol g
  ethtool "$IFACE" 2>/dev/null | grep -i 'Wake-on:'
else
  echo "wol: $IFACE does not advertise magic-packet wake (check BIOS/UEFI)"
fi
exit 0
