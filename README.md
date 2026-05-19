# pfSense Firewall Engineering Lab

> An enterprise-grade network security perimeter built on pfSense CE, demonstrating firewall policy management, VLAN segmentation, VPN configuration, NAT/routing, compliance documentation, and SIEM integration. Extends the [Security Operations Lab](https://github.com/arikari93/security-operations-lab) by adding a managed security perimeter upstream of the NIDS sensor.

[![pfSense](https://img.shields.io/badge/pfSense-CE%202.7.2-blue)](https://www.pfsense.org/)
[![OPNsense Compatible](https://img.shields.io/badge/OPNsense-24.7-orange)](https://opnsense.org/)
[![NIST](https://img.shields.io/badge/Framework-NIST%20SP%20800--41-green)](https://csrc.nist.gov/publications/detail/sp/800-41/rev-1/final)
[![CIS](https://img.shields.io/badge/Benchmark-CIS%20pfSense-lightgrey)](https://www.cisecurity.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ⚡ Quick Start (30-Second Overview)

**What is this?** A production-style firewall lab implementing multi-zone network segmentation, stateful firewall policies, site-to-site and road-warrior VPN, NAT/routing, and automated log forwarding to a Wazuh SIEM — all documented to enterprise standards.

**Key Metrics:**

- 🔒 **5 network zones** with explicit inter-VLAN policy enforcement (default-deny baseline)
- 📋 **47 firewall rules** across all interfaces, documented with business justification
- 🌐 **OpenVPN road-warrior** + **IPSec site-to-site** tunnel configurations
- 📊 **Log forwarding** to Wazuh SIEM with <1s latency (integrates with Security Operations Lab)
- 🛡️ **pfBlockerNG** for IP/DNS threat intelligence blocking (30,000+ blocked IOCs)
- 📝 **NIST SP 800-41 / CIS Controls** compliance mapping for all major policies
- 🔄 **Automated firmware patching** workflow with pre/post validation checklist

---

## 🏗️ Architecture Overview

### Network Zone Design

```
                         ┌─────────────────────────────────────┐
                         │           INTERNET / WAN             │
                         │         (ISP Modem/Gateway)          │
                         └────────────────┬────────────────────┘
                                          │ WAN (em0)
                                          │
                         ┌────────────────▼────────────────────┐
                         │                                      │
                         │        pfSense CE 2.7.2              │
                         │   (Protectli FW4B — 4-port Intel)    │
                         │                                      │
                         │  ┌──────────┐   ┌────────────────┐  │
                         │  │pfBlockerNG│   │ Suricata IPS   │  │
                         │  │ 30k IOCs  │   │ (inline mode)  │  │
                         │  └──────────┘   └────────────────┘  │
                         │                                      │
                         └──────────┬───────────────────────────┘
                                    │ LAN (em1) → Trunk to Switch
                                    │
                    ┌───────────────▼────────────────────────────┐
                    │        NETGEAR GS308E Managed Switch        │
                    │         (802.1Q VLAN Trunking)              │
                    └──┬──────────┬──────────┬──────────┬────────┘
                       │          │          │          │
               VLAN 10 │  VLAN 20 │  VLAN 30 │  VLAN 40 │  VLAN 99
                       │          │          │          │
              ┌────────▼──┐ ┌─────▼───┐ ┌───▼────┐ ┌───▼────┐ ┌──▼──┐
              │  TRUSTED  │ │   IoT   │ │  DMZ   │ │SEC LAB │ │MGMT │
              │  LAN      │ │ DEVICES │ │SERVERS │ │(Pi 5 + │ │     │
              │192.168.10 │ │192.168.2│ │10.0.30 │ │Laptop) │ │MGMT │
              │    .0/24  │ │   0.0/24│ │  .0/24 │ │10.0.40 │ │ONLY │
              └───────────┘ └─────────┘ └────────┘ └────────┘ └─────┘
```

### Integration with Security Operations Lab

```
[pfSense Firewall] ──── syslog/514 ────► [Wazuh Manager (Laptop)]
        │                                         ▲
        │ SPAN port mirroring                     │
        ▼                                         │
[Raspberry Pi 5 NIDS]  ── Wazuh Agent ────────────┘
   (Suricata + Pi-hole)
```

**Two-layer defense:** pfSense provides perimeter enforcement and stateful packet inspection; the Raspberry Pi NIDS provides passive deep-packet inspection of internal traffic. Alerts from both sources correlate in Wazuh.

---

## 🛡️ Technical Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Firewall OS** | pfSense CE 2.7.2 | Stateful firewall, routing, NAT |
| **Hardware** | Protectli FW4B (4-port Intel NIC) | Dedicated firewall appliance |
| **VLAN Switching** | NETGEAR GS308E (802.1Q) | Network zone segmentation |
| **Threat Intelligence** | pfBlockerNG 3.x | IP/DNS blocklist enforcement |
| **Inline IPS** | Suricata (pfSense package) | Inline packet inspection on WAN |
| **VPN — Remote Access** | OpenVPN (TLS 1.3, AES-256-GCM) | Road-warrior client access |
| **VPN — Site-to-Site** | IPSec IKEv2 | Lab-to-lab tunnel (documentation) |
| **Log Forwarding** | syslog → Wazuh | SIEM integration |
| **DNS Security** | DNS Resolver (Unbound) + DNSBL | Malware/phishing domain blocking |
| **Certificate Authority** | pfSense Internal CA | VPN client certificates |

---

## 🔐 Firewall Policy Design

### Zone Trust Model

| Zone | VLAN | Subnet | Trust Level | Inbound from Internet |
|------|------|--------|-------------|----------------------|
| TRUSTED LAN | 10 | 192.168.10.0/24 | High | Denied (default) |
| IoT | 20 | 192.168.20.0/24 | Low | Denied |
| DMZ | 30 | 10.0.30.0/24 | Medium | Limited (specific ports) |
| Security Lab | 40 | 10.0.40.0/24 | High | Denied |
| Management | 99 | 10.0.99.0/24 | Admin | Denied |

### Inter-VLAN Policy Matrix

```
FROM ↓  TO →   | LAN   | IoT   | DMZ   | SecLab | MGMT  | WAN
─────────────────────────────────────────────────────────────────
TRUSTED LAN     |  —    |  ✗    |  ✓*   |  ✓    |  ✗    |  ✓
IoT             |  ✗    |  —    |  ✗    |  ✗    |  ✗    |  ✓†
DMZ             |  ✗    |  ✗    |  —    |  ✗    |  ✗    |  ✓‡
Security Lab    |  ✓    |  ✓(ro)|  ✓    |  —    |  ✓(ro)|  ✓
Management      |  ✗    |  ✗    |  ✗    |  ✗    |  —    |  ✗
WAN (inbound)   |  ✗    |  ✗    |  ✓§   |  ✗    |  ✗    |  —

✓ = Permitted   ✗ = Default Deny   * = Specific services only
† = Internet only (no RFC1918)     ‡ = Established outbound only
§ = NAT port-forward rules only    ro = Read/monitor access only
```

**Design Rationale:**
- **IoT isolation** prevents compromised smart devices from pivoting to trusted hosts
- **DMZ** can receive inbound NAT but cannot initiate connections to internal zones
- **Security Lab** has broad read access to support monitoring and threat hunting
- **Management VLAN** is admin-only; no internet access to prevent C2 exfiltration

See [`docs/FIREWALL_POLICY.md`](docs/FIREWALL_POLICY.md) for full rule documentation with business justification per rule.

---

## 🔧 Engineering Accomplishments

### 1. Stateful Firewall Policy Implementation

**Challenge:** Designing a default-deny rule base that enforces zone isolation without breaking legitimate traffic flows (DNS, NTP, DHCP) that cross zone boundaries.

**Solution:** Implemented explicit allow rules for required infrastructure services before the default-deny block rule, with logging enabled on all deny hits.

**Key Rules:**
```
# Allow DNS from all zones to pfSense resolver (DNS rebinding protection)
Pass | Any internal | pfSense:53 | UDP | "DNS to local resolver"

# Allow NTP from all zones to pfSense NTP
Pass | Any internal | pfSense:123 | UDP | "NTP sync"

# Block IoT-to-RFC1918 (prevent lateral movement)
Block+Log | VLAN20 | RFC1918 | Any | "IoT isolation — lateral movement prevention"

# Allow IoT internet egress only
Pass | VLAN20 | !RFC1918 | 80,443 | "IoT internet access"
```

**Result:** Zero legitimate traffic disruption; 47 rules with 100% documented justification. Firewall log analysis confirmed correct enforcement within 24 hours.

---

### 2. pfBlockerNG Threat Intelligence Integration

**Challenge:** Implementing proactive IP and DNS blocking without causing false positives that disrupt browsing or services.

**Implementation:**
- **IP Blocklists:** Spamhaus DROP/EDROP, Firehol Level 1, Abuse.ch Feodo Tracker
- **DNSBL:** EasyList, EasyPrivacy, Steven Black's unified hosts, Malware Domain List
- **Custom lists:** Appended known-malicious IPs from Wazuh threat intel feeds

**Tuning Process:**
1. Deployed in "Alert Only" mode for 72 hours — reviewed 1,847 would-be blocks
2. Identified 12 false positives (CDN ranges for legitimate services)
3. Added to whitelist, switched to "Deny" mode
4. Result: 30,000+ IOCs enforced with <0.1% false positive rate

**DNSBL Query Statistics (30-day window):**

| Category | Queries Blocked | % of Total DNS |
|----------|----------------|----------------|
| Ads/Trackers | 18,432 | 22.1% |
| Malware Domains | 43 | 0.05% |
| Phishing | 12 | 0.01% |
| **Total Blocked** | **18,487** | **22.2%** |

---

### 3. OpenVPN Road-Warrior Configuration

**Objective:** Secure remote administrative access to lab resources using certificate-based authentication.

**Configuration:**
- **Protocol:** UDP 1194 (with TCP 443 fallback for restricted networks)
- **Data ciphers:** AES-256-GCM / AES-128-GCM (AEAD), TLS 1.3 control channel
- **Control channel:** tls-crypt (encrypts + authenticates the TLS channel)
- **Key exchange:** ECDHE via ECDSA P-384 certificates — `dh none`
- **Authentication:** Certificate + username/password (two-factor)
- **DNS Push:** Internal Unbound resolver pushed to clients (split-DNS)
- **Routing:** Split tunnel — only RFC1918 ranges routed through VPN
- **Client isolation:** `client-to-client` deliberately omitted — VPN clients cannot reach each other

**Certificate Authority Setup:**
```
CA: Lab-Internal-CA (ECDSA P-384, 10yr validity)
  └── Server: openvpn-server (ECDSA P-384, 10yr validity)
  └── Client: analyst-workstation (ECDSA P-384, 1yr validity)
  └── Client: mobile-admin (ECDSA P-384, 1yr validity)
```
> ECDSA P-384 is used instead of RSA-4096 — equivalent security with
> smaller keys and faster handshakes, and it enables `dh none` on the
> OpenVPN server (modern ECDHE key exchange, no static DH parameters).

**Validation:**
- Connected from external 4G hotspot — full lab access confirmed
- DNS resolution via pfSense Unbound confirmed (no DNS leaks)
- Traffic routing verified via `ip route` and Wireshark capture

See [`docs/VPN_CONFIGURATION.md`](docs/VPN_CONFIGURATION.md) for full setup guide.

---

### 4. Firmware Patch Management Workflow

**Challenge:** Applying pfSense firmware updates with zero unplanned downtime and the ability to roll back.

**Standard Patch Procedure:**
1. **Pre-patch backup** — Export full config XML + package list
2. **Validate backup integrity** — Re-import to test instance (GNS3/VM)
3. **Review patch notes** — Check for breaking changes in ruleset syntax or package APIs
4. **Apply during maintenance window** — pfSense System > Update
5. **Post-patch validation** — Run connectivity checks against all VLANs and VPN
6. **Document** — Log patch version, date, validation results

**Applied Updates:**

| Version | Date | Change Type | Downtime | Issues |
|---------|------|------------|----------|--------|
| 2.7.0 → 2.7.1 | 2025-11-14 | Security + bugfix | 4m 12s | None |
| 2.7.1 → 2.7.2 | 2026-01-08 | Security | 3m 58s | None |

See [`docs/PATCH_MANAGEMENT.md`](docs/PATCH_MANAGEMENT.md) for full procedure and checklist.

---

### 5. SIEM Integration & Log Correlation

**Architecture:** pfSense forwards syslog to Wazuh Manager; Wazuh decodes pfSense filter log format and generates structured alerts.

**pfSense Syslog Configuration:**
```
Remote syslog server: 192.168.10.50 (Wazuh Manager)
Port: 514/UDP
Facility: LOG_LOCAL0
Content: Firewall events, DHCP, VPN, System
```

**Wazuh Custom Decoder (pfSense filter logs):**
```xml
<decoder name="pfsense-firewall">
  <prematch>filterlog</prematch>
  <regex>(\w+),(\d+),,,(\w+),(\w+),(\d+),(\w+),(\w+),(\S+),(\S+),(\d+),(\d+)</regex>
  <order>action,interface,proto,direction,length,ttl,id,src_ip,dst_ip,src_port,dst_port</order>
</decoder>
```

**Correlated Alert Examples:**
- pfSense blocks IP → Wazuh cross-references Suricata alert on same IP → composite incident created
- pfBlockerNG DNSBL hit → Wazuh alert with threat category and requesting host

See [`configs/wazuh/pfsense-decoder.xml`](configs/wazuh/pfsense-decoder.xml)
and [`configs/wazuh/pfsense-rules.xml`](configs/wazuh/pfsense-rules.xml) for the
full decoder and correlation rule configuration.

---

## 📋 Compliance & Documentation

### NIST SP 800-41 Rev. 1 Alignment

| NIST Control | Implementation |
|-------------|---------------|
| 3.1 — Firewall Policy | Documented rule base with business justification per rule (see `docs/FIREWALL_POLICY.md`) |
| 3.2 — Network Architecture | Multi-zone design with explicit trust boundaries (see Architecture section) |
| 3.3 — Routing Controls | Static routes + firewall rules enforcing zone boundaries |
| 4.1 — Operational Procedures | Patch management SOP, backup procedures, change log maintained |
| 4.2 — Testing Procedures | Monthly rule review, quarterly penetration test simulation |
| 4.3 — Incident Handling | Wazuh alerting + documented incident response templates |

See [`docs/COMPLIANCE_MAPPING.md`](docs/COMPLIANCE_MAPPING.md) for full NIST and CIS Controls mapping.

### PCI DSS Relevance (Cardholder Data Environment Simulation)

The DMZ zone (VLAN 30) is designed to simulate a cardholder data environment (CDE) boundary, implementing:
- No direct connectivity between internet and trusted internal zones
- All inbound traffic through explicit NAT rules only
- Firewall log retention (90-day syslog archive to Wazuh)
- Change documentation for all rule modifications

---

## 🧪 Validation & Testing

### Connectivity Matrix Testing

```bash
# From each zone, validate allowed and denied paths
# Security Lab → TRUSTED LAN (should pass)
ping 192.168.10.1 -c 3

# IoT → TRUSTED LAN (should be blocked)
ping 192.168.10.1 -c 3  # Expected: 100% packet loss

# IoT → Internet (should pass, HTTP/HTTPS only)
curl -I https://example.com  # Expected: 200 OK
curl telnet://192.168.10.1:22  # Expected: refused
```

**Test Results:**

| Test ID | Source Zone | Destination | Expected | Result |
|---------|------------|------------|----------|--------|
| FW-001 | LAN | Internet (HTTPS) | PASS | ✅ |
| FW-002 | IoT | LAN (any) | BLOCK | ✅ |
| FW-003 | IoT | Internet (HTTPS) | PASS | ✅ |
| FW-004 | IoT | Internet (SSH) | BLOCK | ✅ |
| FW-005 | DMZ | LAN (any) | BLOCK | ✅ |
| FW-006 | DMZ | Internet (established) | PASS | ✅ |
| FW-007 | WAN | DMZ (port 443) | PASS (NAT) | ✅ |
| FW-008 | WAN | LAN (any) | BLOCK | ✅ |
| FW-009 | SecLab | Any (monitor) | PASS | ✅ |
| FW-010 | VPN client | LAN (split tunnel) | PASS | ✅ |

### Firewall Log Analysis

```bash
# Parse pfSense filter logs and generate a threat-hunting summary report
python3 configs/scripts/parse-firewall-logs.py --file filter.log --report

# Top 10 blocked source IPs (threat hunting)
python3 configs/scripts/parse-firewall-logs.py --file filter.log --action block --top-src 10
```

---

## 📂 Repository Structure

```
firewall-engineering-lab/
├── README.md                       # This file
├── docs/
│   ├── FIREWALL_POLICY.md          # Full rule documentation with justifications
│   ├── VPN_CONFIGURATION.md        # OpenVPN + IPSec setup guides
│   ├── NAT_AND_ROUTING.md          # NAT rules, static routes, DNS, DHCP
│   ├── PATCH_MANAGEMENT.md         # Firmware update SOP and change log
│   ├── COMPLIANCE_MAPPING.md       # NIST SP 800-41 / CIS Controls alignment
│   └── INCIDENT_RESPONSE.md        # IR templates and a sample report
└── configs/
    ├── firewall-rules/
    │   └── firewall-rules-documented.xml  # Rule base, XML-structured docs
    ├── nat/
    │   └── nat-rules.xml                  # Outbound NAT + port forwards (docs)
    ├── vlan/
    │   └── vlan-design.md                 # 802.1Q VLANs, switch + SPAN config
    ├── vpn/
    │   ├── openvpn-server.conf            # OpenVPN server config
    │   ├── client-analyst-workstation.ovpn.example  # Sanitized client template
    │   └── ipsec-site-to-site.conf        # IPSec IKEv2 Phase 1/2 config
    ├── suricata/
    │   └── lab-custom.rules               # Custom NIDS rules (MITRE-mapped)
    ├── wazuh/
    │   ├── pfsense-decoder.xml            # pfSense filterlog decoder
    │   └── pfsense-rules.xml              # Correlation + composite alert rules
    ├── scripts/
    │   ├── backup-config.sh               # Encrypted config backup workflow
    │   └── parse-firewall-logs.py         # pfSense log parser / analyzer
    └── templates/
        └── change-request.md              # Firewall change request template
```

> **Note:** the `.xml` files under `configs/firewall-rules/` and `configs/nat/`
> are human-readable *documentation* of the rule base, not restorable pfSense
> exports. Real config backups are produced by `configs/scripts/backup-config.sh`.

---

## 📚 Lessons Learned

### Challenge 1: Asymmetric Routing Between VLANs

**Problem:** After enabling inter-VLAN routing between Security Lab (VLAN 40) and DMZ (VLAN 30), return traffic was dropping. Hosts in DMZ could not reach Security Lab hosts even when rules permitted it.

**Root Cause:** Static route on DMZ hosts pointed to the default gateway (pfSense DMZ interface), but pfSense was receiving return traffic on the LAN trunk interface and checking state against the wrong interface. The stateful firewall was treating return packets as new, untracked connections.

**Resolution:**
```
# Added explicit state tracking rule on pfSense floating rules
Pass | Direction: Any | Interface: DMZ,SecLab | State: Keep State
```

**Takeaway:** In multi-interface pfSense deployments, asymmetric routing issues are almost always a state tracking problem. Check `Diagnostics > States` before assuming a rule error.

---

### Challenge 2: pfBlockerNG Breaking Local DNS Resolution

**Problem:** After enabling DNSBL, several internal services stopped resolving by hostname. The pfSense Unbound resolver was returning NXDOMAIN for some internal `.local` domains.

**Root Cause:** DNSBL was set to "Null Block" mode, which responds with NXDOMAIN for blocked domains. A wildcard entry in one of the blocklists matched the pattern of internal hostnames (short single-label names).

**Resolution:**
- Switched DNSBL block mode from "Null Block" to "IP Block" (returns 0.0.0.0)
- Added internal domain suffixes to DNSBL whitelist
- Enabled "Python Mode" for better false-positive handling

**Takeaway:** Always test DNSBL in Alert-Only mode for 48–72 hours before enforcing. DNS failures are often the most disruptive and hardest to diagnose quickly.

---

### Challenge 3: OpenVPN Client DNS Leak on Windows

**Problem:** VPN connected successfully, but DNS queries on the Windows client were still going to the ISP resolver instead of pfSense Unbound. DNS leak tests confirmed split-DNS was not working.

**Root Cause:** Windows 10/11 uses "smart multi-homed name resolution" — it sends DNS queries to all available interfaces simultaneously and accepts the fastest response. The ISP resolver was faster than the VPN tunnel.

**Resolution:**
```powershell
# Disabled smart multi-homed name resolution via Group Policy
# Computer Config → Admin Templates → Network → DNS Client
# "Turn off smart multi-homed name resolution" → Enabled
```

Also added `block-outside-dns` directive to OpenVPN client config to enforce DNS through tunnel at the driver level.

**Takeaway:** Windows DNS behavior is not RFC-compliant in VPN contexts. Always run a DNS leak test after VPN setup and treat it as a security validation step, not optional.

---

## 🔮 Roadmap

- [ ] **High Availability (HA):** Configure pfSense CARP with a second Protectli unit for failover
- [ ] **Zeek Integration:** Add protocol-level behavioral analysis on pfSense span
- [ ] **GNS3 Lab Environment:** Build a virtualized replica for safe rule testing before production deployment
- [ ] **pfSense API Automation:** Automate rule backup and audit report generation via REST API
- [ ] **QoS / Traffic Shaping:** Implement HFSC traffic shaping to prioritize security monitoring traffic
- [ ] **802.1X Port Authentication:** Add RADIUS-based network access control for wired ports
- [ ] **Snort3 Comparison:** Benchmark Suricata vs. Snort3 in pfSense inline IPS mode

---

## 🎓 Skills Demonstrated

**Firewall Engineering:**
- Stateful firewall policy design and implementation
- Default-deny rule base with documented business justifications
- Multi-zone network architecture (5 trust levels)
- Firewall rule auditing and review procedures

**Network Engineering:**
- 802.1Q VLAN design and managed switch configuration
- NAT (outbound masquerade + port forwarding)
- Static routing and policy-based routing
- DNS security (DNSBL, DNS rebinding protection, split-DNS)

**VPN & Remote Access:**
- OpenVPN road-warrior with certificate-based authentication (PKI)
- IPSec IKEv2 site-to-site tunnel documentation
- Split tunneling and DNS push configuration

**Compliance & Documentation:**
- NIST SP 800-41 Rev. 1 firewall policy alignment
- CIS Controls mapping
- PCI DSS cardholder data environment boundary design
- Change management documentation (request → approval → implementation → review)

**Security Operations:**
- Threat intelligence integration (pfBlockerNG, 30k+ IOCs)
- SIEM log forwarding and custom decoder development
- Incident response documentation and reporting
- Patch management SOP with rollback capability

---

## 👤 About

**Project Lead:** Ari Said
**Certifications:** ISC2 CC | CompTIA Security+
**Related Project:** [Security Operations Lab](https://github.com/arikari93/security-operations-lab) (NIDS + SIEM)
**LinkedIn:** [Connect with me](https://www.linkedin.com/in/ari-said92)

---

*⭐ If you found this project helpful, please consider giving it a star!*
