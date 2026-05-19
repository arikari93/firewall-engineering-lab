# Incident Response Documentation

> Incident response templates and a sample completed incident report demonstrating SOC analyst documentation practices. Follows NIST SP 800-61 Rev. 2 (Computer Security Incident Handling Guide) structure.

---

## Incident Severity Classification

| Severity | Criteria | Response Time | Escalation |
|----------|----------|---------------|------------|
| **P1 — Critical** | Active breach confirmed, data exfiltration in progress, firewall bypassed | Immediate | All stakeholders |
| **P2 — High** | Suspected breach, C2 communication detected, admin credential compromise | 1 hour | Security lead |
| **P3 — Medium** | Anomalous traffic pattern, failed brute force, policy violation | 4 hours | Security team |
| **P4 — Low** | Single failed auth, isolated policy hit, informational | Next business day | Documented only |

---

## Incident Report Template

```markdown
# Security Incident Report

**Incident ID:**      IR-[YYYY]-[SEQ]
**Severity:**         P[1-4]
**Status:**           Open / Contained / Resolved / Closed
**Date Detected:**    [YYYY-MM-DD HH:MM] [TZ]
**Date Resolved:**    [YYYY-MM-DD HH:MM] [TZ]
**Detection Source:** [Wazuh Alert / pfSense Log / Suricata Alert / Manual]

---

## 1. Executive Summary
[2-3 sentence non-technical description of what happened, what was affected, and what was done.]

## 2. Detection
- **Alert/Log Source:** 
- **Alert ID / Rule:**
- **Initial Indicator:**

## 3. Timeline
| Time | Event |
|------|-------|
| HH:MM | Alert triggered |
| HH:MM | Investigation started |
| HH:MM | Containment action taken |
| HH:MM | Resolved |

## 4. Technical Analysis
[Detailed technical findings: IPs, ports, protocols, payloads, affected hosts]

## 5. Containment Actions
[What was done to stop/limit the incident]

## 6. Eradication & Recovery
[How the root cause was eliminated and systems restored]

## 7. Root Cause
[What allowed the incident to occur]

## 8. Lessons Learned
[What will be done differently to prevent recurrence]

## 9. Follow-up Actions
| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| | | | |
```

---

## Sample Completed Incident Report

```
# Security Incident Report

Incident ID:      IR-2026-001
Severity:         P3 — Medium
Status:           Resolved
Date Detected:    2026-02-14 22:47 CST
Date Resolved:    2026-02-14 23:31 CST
Detection Source: Wazuh Alert (correlated pfSense + Suricata)
```

### 1. Executive Summary

At 22:47 CST, Wazuh generated a composite alert correlating a pfSense firewall block event with a Suricata signature match on a single source IP (203.0.113.47). The source IP was making repeated connection attempts to the DMZ on non-standard ports. Investigation confirmed this was an automated port scan originating from a known-malicious IP range. No successful connections were established. pfBlockerNG was updated to include the source ASN in the block list.

### 2. Detection

- **Alert Source:** Wazuh composite rule — pfSense block + Suricata ET SCAN alert on same source IP within 60-second window
- **Wazuh Rule:** Custom correlation rule (local rule 100201)
- **Initial Indicator:** 847 pfSense WAN-IN-999 (default deny) hits from 203.0.113.47 in 4 minutes

### 3. Timeline

| Time (CST) | Event |
|------------|-------|
| 22:43 | First pfSense WAN-IN-999 hit from 203.0.113.47 |
| 22:47 | Wazuh composite alert fires (threshold: 500 blocks + Suricata match) |
| 22:51 | Analyst reviews Wazuh dashboard; confirms port scan pattern |
| 22:54 | IP reputation check: Shodan, AbuseIPDB — 203.0.113.47 confirmed malicious (Mirai botnet node) |
| 23:02 | pfBlockerNG custom block list updated with 203.0.113.0/24 |
| 23:05 | Verified no successful connections in pfSense state table |
| 23:10 | Checked Wazuh for any internal hosts attempting to communicate with this IP (none found) |
| 23:31 | Incident closed — no breach; documentation completed |

### 4. Technical Analysis

**Source IP:** 203.0.113.47 (TEST-NET-3 — anonymized for documentation)
**ASN:** AS64496 — known botnet infrastructure
**Scan Pattern:** SYN scan across ports 22, 80, 443, 8080, 8443, 1433, 3306, 5432 (common service ports)
**Target:** WAN IP → NAT to DMZ (10.0.30.x)
**pfSense Firewall Action:** All connections blocked by WAN-IN-999 (default deny)
**Suricata Rule Triggered:** ET SCAN Potential SSH Scan (sid:2001219), ET SCAN Potential SQLI Scan (sid:2006445)

**pfSense Log Sample:**
```
Feb 14 22:43:12  filterlog: 5,,,, em0, match, block, in, 4, 0x0,, 128, 49201, 0, S, 203.0.113.47, [WAN_IP], 54832, 22, 0
Feb 14 22:43:12  filterlog: 5,,,, em0, match, block, in, 4, 0x0,, 128, 49202, 0, S, 203.0.113.47, [WAN_IP], 54832, 80, 0
```

**Suricata Alert (from Raspberry Pi NIDS — mirrored WAN traffic):**
```json
{
  "timestamp": "2026-02-14T22:43:15.221-0600",
  "event_type": "alert",
  "src_ip": "203.0.113.47",
  "alert": {
    "signature": "ET SCAN Potential SSH Scan OUTBOUND",
    "severity": 2
  }
}
```

### 5. Containment Actions

1. Verified pfSense default-deny blocked all connection attempts (no action required to stop traffic — already blocked)
2. Added 203.0.113.0/24 to pfBlockerNG custom block list to pre-emptively block the entire /24 range
3. Enabled temporary GeoIP block on source country (documented; removed after 24 hours to avoid over-blocking)

### 6. Eradication & Recovery

No internal systems were affected. No eradication required. pfBlockerNG update constitutes the remediation.

### 7. Root Cause

Automated botnet port scanning — expected background noise on any internet-facing IP. Root cause: no root cause for remediation (inherent internet threat); the firewall performed as designed.

### 8. Lessons Learned

- The Wazuh composite correlation rule worked correctly — detected a scan that individual log sources would have treated as noise
- pfBlockerNG IP reputation lists did not pre-block this IP despite it being a known Mirai node — lists are updated 4x/day but this IP may have been recently added to botnet infrastructure
- Consider adding AbuseIPDB API integration to pfBlockerNG for real-time reputation lookups

### 9. Follow-up Actions

| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| Research pfBlockerNG AbuseIPDB integration | Ari Said | 2026-02-28 | Complete — added to lab roadmap |
| Review Wazuh correlation rule threshold (500 blocks) — possibly too high | Ari Said | 2026-02-21 | Complete — lowered to 200 |
| Add IR-2026-001 to quarterly compliance review | Ari Said | Next quarterly review | Pending |

---

## Firewall Change Request Template

```markdown
# Firewall Change Request

**Request ID:**     CR-[YYYY]-[SEQ]
**Requested By:**   
**Date Submitted:** 
**Priority:**       Standard / Urgent / Emergency

## Change Description
[What rule(s) are being added, modified, or removed]

## Business Justification
[Why is this change needed? What business requirement does it support?]

## Security Risk Assessment
- **Risk of Change:** Low / Medium / High
- **Risk of NOT Changing:** Low / Medium / High  
- **Potential Impact:** [What could break or be exposed]

## Implementation Plan
1. 
2.
3.

## Rollback Plan
[How to undo this change if it causes issues]

## Testing / Validation
[How will we verify the change is working correctly and not breaking anything]

## Approvals
- [ ] Security Review
- [ ] Change Implemented
- [ ] Post-Change Validation Complete
```
