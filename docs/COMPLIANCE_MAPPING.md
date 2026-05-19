# Compliance Mapping

> Alignment of pfSense Firewall Engineering Lab controls against NIST SP 800-41 Rev. 1 (Guidelines on Firewalls and Firewall Policy), CIS Controls v8, and selected PCI DSS v4.0 requirements.

---

## NIST SP 800-41 Rev. 1 — Firewalls and Firewall Policy

### Section 3: Firewall Policies

| NIST Requirement | Control Description | Lab Implementation | Evidence |
|-----------------|--------------------|--------------------|----------|
| 3.1.1 | Document firewall policy with business justification for each rule | All 47 rules documented in `docs/FIREWALL_POLICY.md` with justification, owner, and review date | FIREWALL_POLICY.md |
| 3.1.2 | Default deny — block all traffic not explicitly permitted | Explicit BLOCK+LOG rules at end of each interface; pfSense implicit deny as final catch | Rule IDs *-999 |
| 3.1.3 | Block inbound packets with spoofed source addresses | WAN-IN-010: Block RFC1918 source on WAN; pfBlockerNG bogon blocking | WAN-IN-010 |
| 3.1.4 | Block outbound packets with source addresses not in the internal IP range | Outbound NAT enforces correct source IPs; pfBlockerNG FLOAT-020 blocks exfil to malicious IPs | FLOAT-010/020 |
| 3.2.1 | Identify all networks connected to the firewall | 5-zone architecture documented: LAN, IoT, DMZ, SecLab, MGMT + WAN | README.md architecture diagram |
| 3.2.2 | Determine traffic flows between networks | Inter-VLAN policy matrix with explicit permit/deny for all zone pairs | FIREWALL_POLICY.md matrix |
| 3.3.1 | Block all traffic from lower-trust to higher-trust zones by default | IoT cannot reach LAN, DMZ, or SecLab; DMZ cannot reach LAN | IOT-IN-030, DMZ-IN-040 |

### Section 4: Operational Procedures

| NIST Requirement | Control Description | Lab Implementation | Evidence |
|-----------------|--------------------|--------------------|----------|
| 4.1.1 | Establish formal procedures for making changes to firewall configurations | Change request template and review log maintained | `templates/change-request.md`, FIREWALL_POLICY.md change log |
| 4.1.2 | Back up firewall configurations and verify backups | Pre-patch config XML backup; backup script runs weekly | `scripts/backup-config.sh` |
| 4.1.3 | Perform firewall testing after changes | Connectivity matrix test run after every rule change | `docs/FIREWALL_POLICY.md` validation section |
| 4.2.1 | Review firewall rule sets periodically | Quarterly full rule review; ad-hoc on incident or change | FIREWALL_POLICY.md review log |
| 4.2.2 | Test firewall rule sets periodically | Monthly connectivity matrix test; pfBlockerNG alert review | Testing section in README |
| 4.3.1 | Respond to security incidents | Wazuh alerting with pfSense log correlation; IR templates | `docs/INCIDENT_RESPONSE.md` |

---

## CIS Controls v8 — Selected Controls

| CIS Control | Description | Lab Implementation |
|-------------|-------------|-------------------|
| **Control 4** | Secure Configuration of Enterprise Assets | pfSense hardened per CIS benchmarks: admin GUI on MGMT VLAN only, SSH disabled by default, default credentials changed, HTTPS enforced |
| **Control 6** | Access Control Management | VPN certificate-based auth; VLAN segmentation limits access by network zone; Management VLAN restricted to admin hosts |
| **Control 7** | Continuous Vulnerability Management | pfSense firmware patched within defined SLAs; Suricata signatures updated daily; pfBlockerNG lists updated 4x/day |
| **Control 8** | Audit Log Management | All firewall deny events logged; syslog forwarded to Wazuh with 90-day retention; log integrity via centralized SIEM |
| **Control 12** | Network Infrastructure Management | Documented VLAN architecture; managed switch configured with 802.1Q; firewall rules reviewed quarterly |
| **Control 13** | Network Monitoring and Defense | pfSense + Suricata inline IPS; Wazuh correlation of firewall and NIDS alerts; pfBlockerNG threat intel |

---

## PCI DSS v4.0 — Relevant Requirements (CDE Boundary Simulation)

The DMZ (VLAN 30) is designed to simulate a cardholder data environment (CDE) network boundary for lab purposes.

| PCI Requirement | Description | Lab Implementation |
|----------------|-------------|-------------------|
| **1.2.1** | All traffic to/from CDE is restricted to that which is necessary | DMZ rules: explicit permit list only; DMZ-IN-040 blocks all DMZ→internal |
| **1.3.1** | Inbound traffic to CDE restricted to necessary traffic | Only port-forwarded ports (443) accepted inbound from WAN to DMZ |
| **1.3.2** | Outbound traffic from CDE restricted to necessary traffic | DMZ egress: established/related outbound only; no DMZ-initiated internal connections |
| **1.4.1** | NSC (firewall) between untrusted and trusted networks | pfSense sits between WAN/internet and all internal zones |
| **1.5.1** | Security controls for all connections between CDE and untrusted networks | pfBlockerNG + Suricata IPS active on WAN; firewall rule logging enabled |
| **10.2.1** | Audit logs generated for all access to CDE | All WAN-IN-030 (DMZ access) hits logged; syslog to Wazuh with tamper-evident forwarding |
| **10.5.1** | Retain audit logs for at least 12 months | Wazuh configured for 90-day hot storage + archive policy (lab constraint; production = 12 months) |
| **6.3.3** | All security components protected from known vulnerabilities | Patch SOP enforces Critical patches within 24 hours, High within 72 hours |

---

## Common Attack Vectors Mitigated

| Attack Vector | Mitigation | Implementation |
|--------------|------------|----------------|
| **IP Spoofing** | Ingress filtering (RFC 3704) | WAN-IN-010: Block RFC1918 source on WAN |
| **DNS Hijacking** | DNS rebinding protection in Unbound | Enabled by default in pfSense Unbound config |
| **DNS Tunneling** | DNSBL + Suricata custom rule (from NSM lab) | pfBlockerNG DNSBL + CUSTOM rule 9000002 in Suricata |
| **DDoS (volumetric)** | pfBlockerNG + pfSense rate limiting | pfBlockerNG GeoIP + IP reputation; syn proxy on WAN |
| **IoT Pivot / Lateral Movement** | VLAN isolation + default deny inter-VLAN | IOT-IN-030: Hard block IoT→RFC1918 |
| **Credential Stuffing (VPN)** | Certificate + password auth; failed auth lockout | OpenVPN requires cert + username; pfSense auth lockout after 5 failures |
| **Firewall Management Exposure** | GUI restricted to MGMT VLAN and VPN tunnel IPs | LAN-IN-050 blocks LAN→MGMT; WAN has no access to GUI port |
| **Malware C2 Outbound** | pfBlockerNG IP blocklists + Suricata IPS | FLOAT-020 blocks known C2 IPs; Suricata ET rules flag C2 patterns |
| **Unpatched Vulnerability** | Defined patch SLA + pre/post validation | PATCH_MANAGEMENT.md: Critical = 24hr, High = 72hr |
| **Log Tampering** | Centralized syslog to Wazuh (off-device) | Logs forwarded off-box immediately; local logs are secondary |

---

## Compliance Review Schedule

| Review Type | Frequency | Owner | Last Completed |
|-------------|-----------|-------|----------------|
| Full rule base review | Quarterly | Ari Said | 2026-03-01 |
| pfBlockerNG list audit | Monthly | Ari Said | 2026-04-15 |
| VPN certificate audit | Semi-annual | Ari Said | 2026-02-01 |
| Patch compliance review | After each patch | Ari Said | 2026-01-08 |
| Log retention verification | Quarterly | Ari Said | 2026-03-01 |
