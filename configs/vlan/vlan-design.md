# VLAN Design — pfSense Firewall Engineering Lab

## 802.1Q VLAN Assignments

| VLAN ID | Name | Subnet | pfSense Interface | Purpose |
|---------|------|--------|------------------|---------|
| 10 | TRUSTED_LAN | 192.168.10.0/24 | em1.10 (LAN) | Workstations, trusted hosts |
| 20 | IOT | 192.168.20.0/24 | em1.20 (OPT1) | Smart devices, untrusted endpoints |
| 30 | DMZ | 10.0.30.0/24 | em1.30 (OPT2) | Public-facing servers |
| 40 | SECURITY_LAB | 10.0.40.0/24 | em1.40 (OPT3) | Raspberry Pi NIDS, Wazuh, analyst laptop |
| 99 | MANAGEMENT | 10.0.99.0/24 | em1.99 (OPT4) | pfSense GUI access only |

## pfSense Interface Assignments

```
WAN  → em0  (direct ISP connection — no VLAN tag)
LAN  → em1.10 (802.1Q tag 10)
OPT1 → em1.20 (802.1Q tag 20)
OPT2 → em1.30 (802.1Q tag 30)
OPT3 → em1.40 (802.1Q tag 40)
OPT4 → em1.99 (802.1Q tag 99)

Physical trunk port: em1 → NETGEAR GS308E port 1 (tagged all VLANs)
```

## NETGEAR GS308E Switch Configuration

### Port VLAN Membership

| Port | Role | PVID (Untagged) | Tagged VLANs |
|------|------|----------------|--------------|
| 1 | pfSense trunk | — | 10, 20, 30, 40, 99 |
| 2 | Trusted LAN device | 10 | — |
| 3 | Trusted LAN device | 10 | — |
| 4 | IoT device | 20 | — |
| 5 | DMZ server | 30 | — |
| 6 | Raspberry Pi 5 (NIDS) | 40 | — |
| 7 | Analyst laptop (Wazuh) | 40 | — |
| 8 | SPAN/Mirror port | — | Mirror of port 1 |

### Port Mirroring (SPAN)

```
Source port:      Port 1 (pfSense trunk — all inter-VLAN traffic)
Destination port: Port 8 (Raspberry Pi 5 second NIC — passive capture)
Direction:        Both (ingress + egress)
Purpose:          Passive NIDS capture for Suricata — non-intrusive, no impact on production traffic
```

Port 8 connects to the Raspberry Pi's second NIC (eth1) which is set to promiscuous mode.
The Pi's primary NIC (eth0) is on VLAN 40 for management and Wazuh agent communication.

## pfSense VLAN Interface Configuration (config.xml excerpt)

```xml
<vlans>
  <vlan>
    <if>em1</if>
    <tag>10</tag>
    <pcp></pcp>
    <descr>TRUSTED_LAN</descr>
  </vlan>
  <vlan>
    <if>em1</if>
    <tag>20</tag>
    <pcp></pcp>
    <descr>IOT</descr>
  </vlan>
  <vlan>
    <if>em1</if>
    <tag>30</tag>
    <pcp></pcp>
    <descr>DMZ</descr>
  </vlan>
  <vlan>
    <if>em1</if>
    <tag>40</tag>
    <pcp></pcp>
    <descr>SECURITY_LAB</descr>
  </vlan>
  <vlan>
    <if>em1</if>
    <tag>99</tag>
    <pcp></pcp>
    <descr>MANAGEMENT</descr>
  </vlan>
</vlans>
```

## Inter-VLAN Routing

pfSense acts as the Layer 3 gateway for all VLANs. Inter-VLAN routing is controlled
entirely by firewall rules — no traffic crosses zone boundaries unless explicitly permitted.

Routing table on pfSense:
```
Network           Gateway         Interface
192.168.10.0/24   link#2          em1.10 (LAN)
192.168.20.0/24   link#3          em1.20 (OPT1/IoT)
10.0.30.0/24      link#4          em1.30 (OPT2/DMZ)
10.0.40.0/24      link#5          em1.40 (OPT3/SecLab)
10.0.99.0/24      link#6          em1.99 (OPT4/MGMT)
10.8.0.0/24       link#7          ovpns1 (OpenVPN)
0.0.0.0/0         [ISP GW]        em0 (WAN)
```

## Troubleshooting VLAN Issues

**Symptom: Host on VLAN 20 (IoT) getting VLAN 10 (LAN) address**
- Check switch port PVID — should be 20, not 10
- Verify pfSense DHCP server is enabled on OPT1 interface

**Symptom: Inter-VLAN traffic not reaching pfSense**
- Confirm em1 trunk port on switch has all VLAN IDs tagged
- Confirm pfSense VLAN interfaces are assigned and have IPs configured
- Run `ifconfig em1.20` on pfSense console to verify interface is up

**Symptom: SPAN capture missing traffic**
- Verify GS308E port mirroring is set to "Both" directions
- Confirm Pi eth1 is in promiscuous mode: `ip link set eth1 promisc on`
- Verify Suricata is listening on eth1, not eth0
