#!/bin/sh
# Resolve the primary wired NIC at boot and write it into Zeek's node.cfg.
# (Interface name is unknown at build time; a single $ inside a systemd ExecStart
# would be eaten by systemd, so this lives in a script file.)
IFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
[ -n "$IFACE" ] || IFACE="$(ls /sys/class/net | grep -vE '^(lo|docker|veth|br-|virbr|tap|tun|bond)' | head -n1)"
[ -n "$IFACE" ] || IFACE=lo
sed -i "s/^interface=.*/interface=af_packet::$IFACE/" /opt/zeek/etc/node.cfg
