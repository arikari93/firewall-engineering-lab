# VPN Configuration

> OpenVPN road-warrior (remote access) and IPSec IKEv2 (site-to-site) configuration documentation for the pfSense Firewall Engineering Lab.

---

## OpenVPN — Road-Warrior (Remote Access)

### Use Case
Secure administrative access to all lab VLANs from external networks (coffee shop, mobile hotspot, travel). Enables remote management without exposing the pfSense GUI to the internet.

### Configuration Parameters

**Server Settings:**
```
Mode:               Remote Access (SSL/TLS + User Auth)
Protocol:           UDP on IPv4 only
Interface:          WAN
Port:               1194
Control Channel:    tls-crypt (encrypts + authenticates the TLS channel)
Peer Certificate Authority: Lab-Internal-CA
Server Certificate: openvpn-server (CN: vpn.lab.internal)
Key Exchange:       ECDHE — dh none (no static DH parameters)
ECDH Curve:         secp384r1
Data Ciphers:       AES-256-GCM, AES-128-GCM (AEAD)
Control Auth Digest: SHA256
Hardware Crypto:    AES-NI CPU-based Acceleration
TLS Version:        1.3 minimum
```

**Tunnel Settings:**
```
IPv4 Tunnel Network:    10.8.0.0/24
IPv4 Local Network(s):  192.168.10.0/24, 192.168.20.0/24, 10.0.30.0/24, 10.0.40.0/24
Concurrent Connections: 5
```

**Client Settings:**
```
DNS Default Domain:     lab.internal
DNS Server 1:           192.168.99.1 (pfSense Unbound — pushed to client)
DNS Server 2:           (none — enforce local resolver)
Block Outside DNS:      Enabled (prevents DNS leaks on Windows)
```

### Certificate Authority Setup

```
Internal CA:        Lab-Internal-CA
CA Key:             ECDSA P-384 (secp384r1)
CA Lifetime:        3650 days (10 years)
Digest Algorithm:   SHA384

Server Certificate: openvpn-server
  Key:              ECDSA P-384
  Lifetime:         3650 days
  Common Name:      vpn.lab.internal

Client Certificates (one per device):
  analyst-workstation  | ECDSA P-384 | 365-day lifetime | Issued: 2026-02-01
  mobile-admin         | ECDSA P-384 | 365-day lifetime | Issued: 2026-02-01
```

> ECDSA P-384 is chosen over RSA-4096: comparable security strength,
> smaller keys, faster TLS handshakes, and it enables modern ECDHE key
> exchange so the OpenVPN server runs with `dh none` (no static DH file).

**Certificate Lifecycle:**
- Certificates expire annually — calendar reminder set 30 days before expiry
- Revoked certificates are added to CRL (Certificate Revocation List) on pfSense CA
- Compromise of any client cert → immediately revoke, issue new cert, re-export client config

### Client Configuration Export

```bash
# pfSense exports a .ovpn bundle (inline cert/key) via:
# VPN > OpenVPN > Client Export > [select client] > Bundled configurations > .ovpn

# Transfer to client securely (SCP or encrypted email — NOT unencrypted USB/email)
scp analyst-workstation.ovpn user@analyst-laptop:/etc/openvpn/
```

### DNS Leak Prevention

Windows-specific fix required (see Lessons Learned in README):

```powershell
# Verify DNS is routing through VPN tunnel
# While connected to VPN, run:
Resolve-DnsName lab.internal

# Expected: returns 10.0.40.x (internal Wazuh/Pi-hole host)
# If returns public IP: DNS leak — apply block-outside-dns fix

# Verify no DNS leak via:
# https://dnsleaktest.com — should show pfSense's ISP, not home ISP
```

### Validation Tests

```bash
# From external network (mobile hotspot), after VPN connect:

# Test 1: pfSense GUI accessible via tunnel IP
curl -k https://10.8.0.1  # pfSense web GUI

# Test 2: Internal VLAN accessible
ping 192.168.10.1          # LAN gateway
ping 10.0.40.50            # Wazuh Manager

# Test 3: DNS pushing correctly
nslookup lab.internal      # Should resolve via 10.8.0.1 (pfSense)

# Test 4: No traffic bypassing tunnel
# Check pfSense firewall logs for VPN client IP (10.8.0.x) making requests
```

---

## IPSec IKEv2 — Site-to-Site Tunnel (Documentation)

> This configuration documents a site-to-site IPSec tunnel between the primary lab and a secondary pfSense instance (cloud VPS running pfSense for testing).

### Phase 1 (IKEv2 — ISAKMP SA)

```
Key Exchange Version:   IKEv2
Internet Protocol:      IPv4
Interface:              WAN
Remote Gateway:         [VPS public IP]
Authentication Method:  Mutual PSK (lab use; high-entropy key required)
                        Production recommendation: mutual ECDSA certificates

Encryption Algorithm:   AES-256-GCM (AEAD)
PRF:                    SHA-384
Key Exchange Group:     ECP-384 (NIST P-384) — fallback ECP-256
Lifetime:               28800 seconds (8 hours)
```

### Phase 2 (ESP — Data SA)

```
Mode:                   Tunnel IPv4
Local Network:          10.0.40.0/24 (Security Lab — source of monitoring traffic)
Remote Network:         10.1.0.0/24 (remote VPS internal range)

Protocol:               ESP
Encryption Algorithm:   AES-256-GCM (AEAD)
PFS Key Group:          ECP-384 (NIST P-384)
Lifetime:               3600 seconds (1 hour)
```

> DH Group 14 (modp2048) was replaced with ECP groups (19/20). Group 14
> is only an acceptable minimum; ECP-384 is the modern target and keeps
> Phase 1, Phase 2, and OpenVPN on a consistent elliptic-curve baseline.

### Routing for IPSec

```
# pfSense automatically adds a route for the remote network via the IPSec SA
# Verify with: netstat -rn | grep [remote subnet]

# For asymmetric routing scenarios, add manual static route:
# System > Routing > Static Routes
# Network: 10.1.0.0/24
# Gateway: [IPSec tunnel interface]
```

### IPSec Troubleshooting

```bash
# Check Phase 1 SA status
# Status > IPsec > Overview: Shows connected/disconnected per tunnel

# View IKE daemon log
clog -f /var/log/ipsec.log

# Common issues:
# - Phase 1 failure: PSK mismatch or encryption algorithm mismatch
# - Phase 2 failure: Subnet mismatch between local and remote definitions
# - DPD (Dead Peer Detection) killing tunnel: check keepalive interval settings
```

---

## VPN Security Hardening

Recommendations applied to both VPN types:

1. **No anonymous access** — All VPN connections require certificate + username/password
2. **Client certificate per device** — Enables per-device revocation without rekeying all clients
3. **TLS 1.3 minimum** — Disabled TLS 1.0 and 1.1 in OpenVPN tls-version-min directive
4. **Short certificate lifetime** — Annual rotation limits blast radius of key compromise
5. **VPN-only admin rule** — pfSense GUI (443) accessible only from VPN tunnel IPs (10.8.0.0/24) and Management VLAN — not from WAN or LAN directly
6. **Audit VPN logs weekly** — Review for unexpected connection sources or time-of-day anomalies in Wazuh
