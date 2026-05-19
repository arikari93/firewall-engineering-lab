# Patch Management & Firmware Update Procedures

> Standard Operating Procedure for pfSense firmware updates, package upgrades, and rollback procedures. Aligns with NIST SP 800-40 Rev. 4 (Guide to Enterprise Patch Management Planning).

---

## Overview

Unpatched firewall firmware is one of the highest-risk exposures in any network environment. This SOP defines the complete patch lifecycle: pre-patch validation, execution, post-patch testing, and rollback.

**Patch Sources Monitored:**
- [pfSense Security Advisories](https://www.netgate.com/blog/security-advisories)
- [CISA Known Exploited Vulnerabilities Catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog)
- [NVD CVE feed](https://nvd.nist.gov/vuln/full-listing) — filtered for pfSense, FreeBSD, Suricata, Unbound

**Patch Priority Classification:**

| Priority | Criteria | Target Window |
|----------|----------|---------------|
| **Critical** | CVSS ≥ 9.0 or active exploitation known | 24 hours |
| **High** | CVSS 7.0–8.9 | 72 hours |
| **Medium** | CVSS 4.0–6.9 | 14 days |
| **Low** | CVSS < 4.0 / cosmetic | Next maintenance window |

---

## Pre-Patch Checklist

Complete all steps before applying any update.

```
PRE-PATCH VALIDATION — [DATE] — pfSense [CURRENT VERSION] → [TARGET VERSION]
────────────────────────────────────────────────────────────────────────────
□ 1. Read the full patch release notes at netgate.com/blog
□ 2. Check for known breaking changes (package API changes, deprecated config syntax)
□ 3. Export full configuration backup:
       Diagnostics > Backup & Restore > Download Configuration XML
       → Save as: pfsense-config-[YYYY-MM-DD]-pre-[VERSION].xml
□ 4. Record installed packages:
       System > Package Manager > Installed Packages
       → Screenshot or text export to: docs/patch-history/[DATE]-packages.txt
□ 5. Document current rule count and floating rule state
□ 6. Verify Wazuh is receiving pfSense syslog (confirm in Wazuh dashboard)
□ 7. Note VPN tunnel status (connected clients / active IPSec SAs)
□ 8. Confirm maintenance window with any active lab users
□ 9. Have rollback config ready (previous config XML on local machine)
□ 10. Estimated downtime communicated: typically 3–7 minutes for reboot
```

---

## Patch Execution Procedure

```bash
# Step 1: Verify update is available
# System > Update > System Update tab
# Confirm: "A new version of pfSense is available"

# Step 2: Trigger update
# Click "Confirm" on update page
# pfSense will: download update → verify checksum → apply → reboot

# Step 3: Monitor console (optional — SSH or physical)
# tail -f /var/log/system.log

# Step 4: Wait for reboot completion (typically 3–5 minutes)
# Watch for pfSense web GUI to return on https://192.168.99.1
```

---

## Post-Patch Validation Checklist

```
POST-PATCH VALIDATION — [DATE] — pfSense [NEW VERSION]
────────────────────────────────────────────────────────
□ 1. Confirm version:  System > Update — shows "System is up to date"
□ 2. Verify package versions match pre-patch list (no unexpected downgrades)
□ 3. Run connectivity matrix test (see testing/CONNECTIVITY_MATRIX.md)
       □ LAN → Internet: PASS
       □ IoT → LAN: BLOCK (confirmed)
       □ DMZ → LAN: BLOCK (confirmed)
       □ VPN client → LAN: PASS
□ 4. Verify pfBlockerNG is active and enforcing
       □ Check pfBlockerNG > Reports > Alerts for activity
□ 5. Verify Suricata is running on WAN interface
       □ Services > Suricata > Interface Status: Running
□ 6. Verify syslog forwarding to Wazuh is active
       □ Check Wazuh dashboard for pfSense events within last 5 minutes
□ 7. Verify OpenVPN service is running
       □ Status > OpenVPN: "up"
□ 8. Test VPN connection from external network
□ 9. Check system logs for errors:  Status > System Logs > System
□ 10. Document completion in patch change log below
```

---

## Rollback Procedure

If post-patch validation fails and the issue cannot be quickly resolved:

```
ROLLBACK STEPS:
1. Do NOT attempt further config changes — preserve state for analysis
2. Navigate to: Diagnostics > Backup & Restore
3. Upload pre-patch config XML
4. If web GUI is unavailable:
   a. Connect via console (serial or physical keyboard)
   b. Select option 14: "Enable Secure Shell (sshd)"
   c. SCP config from backup machine:
      scp pfsense-config-[DATE]-pre-[VERSION].xml admin@192.168.99.1:/tmp/
   d. Run from pfSense console:
      php /usr/local/sbin/restore-config.php /tmp/pfsense-config-[DATE]-pre-[VERSION].xml
5. Reboot and validate with post-patch checklist
6. Document rollback event and open issue on this repo for investigation
```

---

## Patch Change Log

| Date | Version (Before) | Version (After) | CVEs Addressed | Downtime | Validated By | Notes |
|------|-----------------|-----------------|----------------|----------|--------------|-------|
| 2025-11-14 | 2.7.0 | 2.7.1 | FreeBSD SA-25:03, pfSense-SA-24_01 | 4m 12s | Ari Said | All checks passed. pfBlockerNG required manual list update post-patch. |
| 2026-01-08 | 2.7.1 | 2.7.2 | pfSense-SA-25_02 (XSS in GUI) | 3m 58s | Ari Said | Clean upgrade. No breaking changes. |

---

## Package Update Procedure

pfSense packages (pfBlockerNG, Suricata, OpenVPN) are updated separately from the base firmware.

```
Package Update Checklist:
□ 1. System > Package Manager > Check for Updates
□ 2. Review changelogs for each package before updating
□ 3. Update one package at a time — avoid batch updates
□ 4. After each package update, validate that service is running
□ 5. Log update in patch change log above
```

**Critical Note on Suricata Package Updates:** After a Suricata package update, always re-validate that rules are loading correctly:
```bash
# From pfSense console or SSH
suricata -T -c /usr/local/etc/suricata/suricata.yaml
# Expected: "Configuration provided was successfully loaded."
```

This mirrors the rule-path mismatch issue documented in the [Security Operations Lab](https://github.com/arikari93/security-operations-lab) — always verify rule ingestion after updates.

---

## Firmware Integrity Verification

Before trusting any downloaded pfSense image:

```bash
# Verify SHA256 hash matches Netgate's published checksum
sha256sum pfSense-CE-2.7.2-RELEASE-amd64.iso.gz

# Compare against: https://www.netgate.com/downloads
# Any mismatch = do NOT proceed — contact Netgate support
```
