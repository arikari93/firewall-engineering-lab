# Firewall Change Request

**Request ID:** CR-[YYYY]-[SEQ]  
**Requested By:**  
**Date Submitted:**  
**Target Implementation Date:**  
**Priority:** Standard / Urgent / Emergency  
**Status:** Draft / Pending Review / Approved / Implemented / Closed  

---

## 1. Change Description

> What rule(s) are being added, modified, or removed? Be specific about interface, source, destination, port, and action.

**Type of Change:** Add Rule / Modify Rule / Remove Rule / VLAN Change / NAT Change / VPN Change

**Affected Interfaces:** _(e.g., WAN, OPT1/IoT, DMZ)_

**Rule(s) Affected:**

| Rule ID | Current State | Proposed State |
|---------|--------------|----------------|
| | | |

---

## 2. Business Justification

> Why is this change needed? What business or security requirement does it support?
> Every rule requires a written justification — "user requested" is not acceptable.

**Justification:**

**Service/System Affected:**

**Requestor / Ticket Reference:**

---

## 3. Security Risk Assessment

| Risk Factor | Assessment |
|-------------|------------|
| **Risk of implementing change** | Low / Medium / High |
| **Risk of NOT implementing change** | Low / Medium / High |
| **New attack surface introduced** | Yes / No — describe: |
| **Compliance impact** | None / NIST / CIS / PCI DSS — describe: |
| **Logging impact** | Will the change affect log visibility? |

**Mitigating Controls:**
_(What existing or new controls reduce the risk of this change?)_

---

## 4. Implementation Plan

**Maintenance Window:** _(Date, time, estimated duration)_

**Steps:**
1. 
2. 
3. 

**Commands / Config Changes:**
```
# Paste relevant pfSense config changes here
# or describe UI steps
```

---

## 5. Rollback Plan

> How will you undo this change if it causes issues?

**Rollback Steps:**
1. 
2. 

**Estimated Rollback Time:** _(typically <5 minutes for rule revert)_

**Pre-change backup location:** `/opt/backups/pfsense/pfsense-config-[DATE]-pre-patch.xml`

---

## 6. Testing & Validation

> How will you verify the change is working correctly and not breaking anything?

**Validation Tests:**

| Test | Expected Result | Actual Result | Pass/Fail |
|------|----------------|---------------|-----------|
| | | | |
| | | | |

**Tools Used:** _(ping, curl, Wireshark, pfSense packet capture, Wazuh logs)_

---

## 7. Post-Implementation Review

**Implemented By:**  
**Date Implemented:**  
**Actual Downtime:**  
**Issues Encountered:**  

**Validation Result:** Pass / Fail / Partial  

**Notes:**

---

## 8. Approvals

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Requester | | | |
| Security Review | | | |
| Implementation | | | |

---

*File this completed request in `docs/change-history/CR-[YYYY]-[SEQ].md` after implementation.*
