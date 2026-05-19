# NAT and Routing Configuration

> Documentation of Network Address Translation rules, static routes, and policy-based routing in the pfSense Firewall Engineering Lab.

---

## NAT Overview

pfSense handles two NAT types in this lab:

| NAT Type | Direction | Purpose |
|----------|-----------|---------|
| **Outbound NAT (Masquerade)** | Internal → WAN | Translates internal RFC1918 addresses to WAN IP for internet egress |
| **Port Forward (DNAT)** | WAN → DMZ | Exposes specific DMZ services to the internet |

---

## Outbound NAT Rules

**Mode:** Hybrid (automatic rules + manual overrides)

| Interface | Source | Translation | Description |
|-----------|--------|-------------|-------------|
| WAN | 192.168.10.0/24 (LAN) | Interface address | Trusted LAN internet egress |
| WAN | 192.168.20.0/24 (IoT) | Interface address | IoT internet egress (HTTP/HTTPS only — controlled by firewall rules) |
| WAN | 10.0.30.0/24 (DMZ) | Interface address | DMZ egress for updates and API calls |
| WAN | 10.0.40.0/24 (SecLab) | Interface address | Security Lab egress (threat intel, Wazuh updates) |
| WAN | 10.8.0.0/24 (VPN) | Interface address | VPN client internet egress (split-tunnel OFF for lab validation only) |

**Note:** Management VLAN (10.0.99.0/24) has **no outbound NAT rule** — no internet access by design. Any management traffic that reaches WAN is blocked at the firewall rule level before NAT.

---

## Port Forwarding (Inbound DNAT)

| Rule | WAN Port | Protocol | Redirect Target | Target Port | Description |
|------|----------|----------|-----------------|-------------|-------------|
| NAT-PF-010 | 443 | TCP | 10.0.30.10 | 443 | HTTPS to DMZ web server |
| NAT-PF-020 | 1194 | UDP | 127.0.0.1 | 1194 | OpenVPN server (loopback — pfSense handles) |

**Security Notes:**
- Port 80 is NOT forwarded — no plain HTTP exposure
- SSH (22) is NOT forwarded — management only via VPN
- All port-forward targets are in the DMZ zone (10.0.30.0/24) — not directly into LAN
- Associated firewall rules (WAN-IN-030, WAN-IN-040) permit only these specific forwarded ports

---

## Static Routes

| Network | Gateway | Interface | Description |
|---------|---------|-----------|-------------|
| 10.1.0.0/24 | [IPSec tunnel GW] | IPSec | Remote site network (site-to-site VPN) |

**Default Route:** WAN gateway (ISP-assigned) — applied automatically by pfSense DHCP client on WAN.

---

## DNS Configuration

**Resolver:** pfSense Unbound (recursive, not forwarding)

```
Mode:               Recursive (root hints — not forwarding to upstream)
DNSSEC:             Enabled
DNS Rebinding:      Enabled (blocks private IP responses from public DNS)
DNSBL:              pfBlockerNG (malware, ad/tracker, phishing domains)

Interface Binding:  LAN, IoT, DMZ, SecLab, MGMT, OpenVPN (NOT WAN)
Custom Host Overrides:
  wazuh.lab.internal    → 10.0.40.50
  pihole.lab.internal   → 10.0.40.10
  pfsense.lab.internal  → 10.0.99.1
```

**Why recursive (not forwarding)?**
Forwarding to upstream DNS (8.8.8.8, 1.1.1.1) means a third party sees all DNS queries. Recursive resolution goes directly to authoritative nameservers — no intermediary. Slower first-query latency (~100ms vs ~20ms) but significantly better privacy and eliminates upstream DNS as a single point of failure.

---

## DHCP Server Configuration

| VLAN | Scope | Lease Time | DNS | Gateway |
|------|-------|-----------|-----|---------|
| LAN (10) | 192.168.10.100–.200 | 24h | 192.168.10.1 (pfSense) | 192.168.10.1 |
| IoT (20) | 192.168.20.100–.200 | 8h | 192.168.20.1 (pfSense) | 192.168.20.1 |
| DMZ (30) | 10.0.30.100–.150 | 24h | 10.0.30.1 (pfSense) | 10.0.30.1 |
| SecLab (40) | 10.0.40.100–.150 | 24h | 10.0.40.1 (pfSense) | 10.0.40.1 |
| MGMT (99) | 10.0.99.10–.20 | 12h | 10.0.99.1 (pfSense) | 10.0.99.1 |

**Static DHCP Leases (reserved by MAC):**

| Host | MAC | IP | VLAN |
|------|-----|----|------|
| Raspberry Pi 5 (NIDS) | [PI_MAC] | 10.0.40.10 | SecLab |
| Analyst Laptop (Wazuh) | [LAPTOP_MAC] | 10.0.40.50 | SecLab |
| DMZ Web Server | [SERVER_MAC] | 10.0.30.10 | DMZ |

---

## Routing Troubleshooting Reference

**Symptom: Inter-VLAN traffic blocked despite permit rule**
```bash
# Check pfSense states table for the connection
# Diagnostics > States > Filter by source IP

# If no state: packet is being dropped before state creation
# → Check firewall rules in correct order
# → Check floating rules for unintended blocks

# If state exists but traffic drops:
# → Likely asymmetric routing issue — check return path
# → Verify both directions have permit rules
```

**Symptom: NAT not translating (traffic leaving with RFC1918 source)**
```bash
# Diagnostics > Packet Capture on WAN interface
# Filter: host [test destination]
# Check source IP in capture — should be WAN IP, not internal RFC1918

# If RFC1918 seen on WAN: outbound NAT rule missing or wrong interface binding
```

**Symptom: Port forward not reaching DMZ host**
```bash
# Step 1: Verify port forward rule exists (Firewall > NAT > Port Forward)
# Step 2: Verify associated firewall rule was auto-created (Firewall > Rules > WAN)
# Step 3: Check DMZ host is listening on the target port:
#   From pfSense console: nc -zv 10.0.30.10 443
# Step 4: Check DMZ host firewall (if OS-level firewall enabled on server)
```
