# Firewall Policy Documentation

> Full rule documentation for all pfSense interfaces. Every rule includes a business justification, owner, and review date. Follows NIST SP 800-41 Rev. 1 Section 3.1 documentation requirements.

---

## Rule Numbering Convention

```
[INTERFACE]-[DIRECTION]-[SEQ] | Action | Protocol | Source | Destination | Port | Description
```

- **INTERFACE:** WAN, LAN, IOT, DMZ, SEC, FLOAT
- **DIRECTION:** IN (inbound to interface), OUT (outbound)
- **SEQ:** 3-digit sequence number (execution order)

---

## WAN Interface Rules (Internet-Facing)

> Default policy: **BLOCK ALL INBOUND** (pfSense implicit deny)

| Rule ID | Action | Protocol | Source | Destination | Port | Justification | Logged |
|---------|--------|----------|--------|-------------|------|---------------|--------|
| WAN-IN-010 | BLOCK+LOG | Any | RFC1918 (spoofed) | Any | Any | Block spoofed private-IP packets at WAN — RFC 3704 ingress filtering | Yes |
| WAN-IN-020 | BLOCK+LOG | Any | Bogon networks | Any | Any | Block unallocated/reserved IP ranges per pfBlockerNG bogon list | Yes |
| WAN-IN-030 | PASS | TCP | Any | WAN IP | 443 | NAT port-forward — HTTPS to DMZ web server (10.0.30.10) | Yes |
| WAN-IN-040 | PASS | UDP | Any | WAN IP | 1194 | OpenVPN road-warrior inbound | Yes |
| WAN-IN-999 | BLOCK+LOG | Any | Any | Any | Any | Explicit default deny — all other inbound WAN traffic | Yes |

**Notes:**
- Rules WAN-IN-030 and WAN-IN-040 rely on pfSense NAT to redirect to internal destinations
- All WAN blocks are logged; log volume reviewed weekly for threat intelligence
- pfBlockerNG GeoIP blocking applied before rule WAN-IN-010 (not shown — managed by pfBlockerNG)

---

## LAN (VLAN 10 — Trusted) Interface Rules

> Default policy: Permit outbound to internet; block to IoT and Management VLANs

| Rule ID | Action | Protocol | Source | Destination | Port | Justification |
|---------|--------|----------|--------|-------------|------|---------------|
| LAN-IN-010 | PASS | Any | LAN net | This firewall | 53 | DNS queries to pfSense Unbound resolver |
| LAN-IN-020 | PASS | UDP | LAN net | This firewall | 123 | NTP time synchronization |
| LAN-IN-030 | PASS | TCP | LAN net | 10.0.30.0/24 (DMZ) | 80,443 | Access to self-hosted services in DMZ |
| LAN-IN-040 | BLOCK+LOG | Any | LAN net | 192.168.20.0/24 (IoT) | Any | Prevent LAN from managing IoT devices (unidirectional isolation) |
| LAN-IN-050 | BLOCK+LOG | Any | LAN net | 10.0.99.0/24 (MGMT) | Any | LAN has no management plane access |
| LAN-IN-060 | PASS | Any | LAN net | !RFC1918 | Any | General internet egress |
| LAN-IN-999 | BLOCK+LOG | Any | LAN net | Any | Any | Catch-all deny with logging |

---

## IoT (VLAN 20) Interface Rules

> Default policy: Internet access only — no internal zone access permitted

| Rule ID | Action | Protocol | Source | Destination | Port | Justification |
|---------|--------|----------|--------|-------------|------|---------------|
| IOT-IN-010 | PASS | Any | IoT net | This firewall | 53 | DNS queries to pfSense resolver (controlled resolution) |
| IOT-IN-020 | PASS | UDP | IoT net | This firewall | 123 | NTP sync |
| IOT-IN-030 | BLOCK+LOG | Any | IoT net | RFC1918 | Any | **Critical:** Prevent IoT lateral movement to all internal networks |
| IOT-IN-040 | PASS | TCP | IoT net | !RFC1918 | 80,443 | HTTP/HTTPS internet access for device updates and cloud services |
| IOT-IN-050 | BLOCK+LOG | Any | IoT net | Any | Any | Deny all other traffic including non-standard ports |

**Design Note:** IoT devices are treated as untrusted by default. A compromised IoT device can only reach the internet on standard ports — it cannot reach internal hosts, the firewall management interface, or other VLANs. This limits the blast radius of a supply-chain or firmware compromise.

---

## DMZ (VLAN 30) Interface Rules

> Default policy: Accept established outbound; block all inbound from internal zones

| Rule ID | Action | Protocol | Source | Destination | Port | Justification |
|---------|--------|----------|--------|-------------|------|---------------|
| DMZ-IN-010 | PASS | Any | DMZ net | This firewall | 53 | DNS |
| DMZ-IN-020 | PASS | UDP | DMZ net | This firewall | 123 | NTP |
| DMZ-IN-030 | PASS | TCP | DMZ net | !RFC1918 | 80,443 | Outbound web (package updates, API calls) |
| DMZ-IN-040 | BLOCK+LOG | Any | DMZ net | RFC1918 | Any | DMZ cannot initiate connections to internal zones — contains breach |
| DMZ-IN-999 | BLOCK+LOG | Any | DMZ net | Any | Any | Default deny |

**PCI-DSS Relevance:** The DMZ-IN-040 rule enforces the requirement that systems in a CDE-adjacent zone cannot communicate directly with internal systems (PCI DSS Requirement 1.3.2). All inbound traffic to DMZ originates from pfSense NAT, not from internal hosts.

---

## Security Lab (VLAN 40) Interface Rules

> Default policy: Broad internal access for monitoring; standard internet egress

| Rule ID | Action | Protocol | Source | Destination | Port | Justification |
|---------|--------|----------|--------|-------------|------|---------------|
| SEC-IN-010 | PASS | Any | SecLab net | This firewall | 53,123,443 | Infrastructure services + pfSense GUI (admin access) |
| SEC-IN-020 | PASS | TCP | SecLab net | RFC1918 | 22 | SSH for device management and log collection |
| SEC-IN-030 | PASS | TCP | SecLab net | RFC1918 | 514 | Syslog collection from all zones |
| SEC-IN-040 | PASS | TCP | SecLab net | RFC1918 | 443,8080,5636 | Wazuh dashboard, Pi-hole admin, EveBox (monitoring UIs) |
| SEC-IN-050 | PASS | ICMP | SecLab net | RFC1918 | — | ICMP for connectivity testing and network mapping |
| SEC-IN-060 | PASS | Any | SecLab net | !RFC1918 | Any | Internet egress for threat intel, updates |
| SEC-IN-999 | BLOCK+LOG | Any | SecLab net | Any | Any | Catch-all |

---

## Floating Rules (Applied Globally)

> Floating rules process before interface rules and apply across all interfaces.

| Rule ID | Action | Interface | Protocol | Source | Destination | Description |
|---------|--------|-----------|----------|--------|-------------|-------------|
| FLOAT-010 | BLOCK+LOG | All | Any | pfBlockerNG IP tables | Any | pfBlockerNG IP reputation blocking (inbound+outbound) |
| FLOAT-020 | BLOCK+LOG | All | Any | Any | pfBlockerNG IP tables | Block outbound to known-malicious IPs |
| FLOAT-030 | PASS | All | TCP | Any | Any | Allow established/related (state tracking assist) |

---

## Rule Review Log

| Date | Reviewer | Rules Modified | Change Summary |
|------|----------|----------------|----------------|
| 2025-10-01 | Ari Said | IOT-IN-040 | Changed from BLOCK to BLOCK+LOG to capture IoT egress attempts |
| 2025-11-15 | Ari Said | WAN-IN-030 | Added HTTPS port-forward for DMZ web service |
| 2026-01-20 | Ari Said | FLOAT-010/020 | Updated pfBlockerNG lists after false positive review |
| 2026-03-01 | Ari Said | SEC-IN-040 | Added EveBox port 5636 for Security Lab access |

**Review Schedule:** Full rule base review every 90 days. Ad-hoc review triggered by: new service deployment, security incident, or failed audit finding.

---

## Change Request Process

All firewall rule changes follow this workflow:

1. Complete [`templates/change-request.md`](../templates/change-request.md)
2. Document business justification and risk assessment
3. Test in GNS3 virtualized environment (if applicable)
4. Apply during maintenance window
5. Validate with connectivity matrix test
6. Update this document and the rule review log
7. Archive change request in `docs/change-history/`
