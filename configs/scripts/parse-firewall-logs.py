#!/usr/bin/env python3
"""
parse-firewall-logs.py — pfSense Filterlog Parser
Firewall Engineering Lab | Author: Ari Said
Version: 1.3 | Updated: 2026-03-01

PURPOSE:
    Parse pfSense filterlog (pf packet filter) syslog output into
    structured JSON or human-readable reports. Useful for:
    - Manual log analysis and threat hunting
    - Generating compliance audit reports
    - Feeding data into external tools (SIEM, spreadsheets)

USAGE:
    # Parse live syslog (pipe from remote)
    ssh admin@10.0.99.1 "clog /var/log/filter.log" | python3 parse-firewall-logs.py

    # Parse log file
    python3 parse-firewall-logs.py --file filter.log

    # Filter by action
    python3 parse-firewall-logs.py --file filter.log --action block

    # Top 10 blocked source IPs (threat hunting)
    python3 parse-firewall-logs.py --file filter.log --action block --top-src 10

    # Output as JSON (pipe to jq for further filtering)
    python3 parse-firewall-logs.py --file filter.log --format json | jq '.[] | select(.dst_port == "22")'

    # Generate summary report
    python3 parse-firewall-logs.py --file filter.log --report

pfSense filterlog CSV format (IPv4 TCP):
    rule,sub-rule,anchor,tracker,interface,reason,action,direction,
    ip-ver,tos,ecn,ttl,id,offset,flags,proto-id,proto,length,
    src-ip,dst-ip,src-port,dst-port,data-len
"""

import sys
import re
import json
import argparse
from collections import Counter, defaultdict
from datetime import datetime


# ── pfSense filterlog field definitions ───────────────────────────────────────

# Common fields (indices 0–17 in the CSV after 'filterlog: ')
COMMON_FIELDS = [
    "rule_id", "sub_rule", "anchor", "tracker", "interface",
    "reason", "action", "direction", "ip_version", "tos",
    "ecn", "ttl", "id", "offset", "flags", "proto_id", "proto", "length"
]

# Protocol-specific fields appended after common fields
TCP_FIELDS  = ["src_ip", "dst_ip", "src_port", "dst_port", "data_len"]
UDP_FIELDS  = ["src_ip", "dst_ip", "src_port", "dst_port", "data_len"]
ICMP_FIELDS = ["src_ip", "dst_ip", "icmp_type", "icmp_code", "icmp_id", "icmp_seq"]

# Regex to extract the filterlog CSV from a syslog line
FILTERLOG_PATTERN = re.compile(
    r'(\w+\s+\d+\s+\d+:\d+:\d+)\s+\S+\s+filterlog\[\d+\]:\s+(.+)'
)


# ── Parsing ───────────────────────────────────────────────────────────────────

def parse_filterlog_line(syslog_line: str) -> dict | None:
    """Parse a single pfSense filterlog syslog line into a structured dict."""
    match = FILTERLOG_PATTERN.search(syslog_line)
    if not match:
        return None

    timestamp_str, csv_data = match.groups()
    fields = csv_data.strip().split(",")

    if len(fields) < 18:
        return None  # Malformed line

    # Parse common fields
    entry = {COMMON_FIELDS[i]: fields[i] for i in range(min(18, len(fields)))}
    entry["raw_timestamp"] = timestamp_str
    entry["year"] = datetime.now().year  # syslog doesn't include year

    # Parse protocol-specific fields
    proto = entry.get("proto", "").lower()
    remaining = fields[18:]

    if proto == "tcp" and len(remaining) >= 5:
        for i, key in enumerate(TCP_FIELDS):
            entry[key] = remaining[i] if i < len(remaining) else ""
    elif proto == "udp" and len(remaining) >= 5:
        for i, key in enumerate(UDP_FIELDS):
            entry[key] = remaining[i] if i < len(remaining) else ""
    elif proto == "icmp" and len(remaining) >= 2:
        for i, key in enumerate(ICMP_FIELDS):
            entry[key] = remaining[i] if i < len(remaining) else ""

    return entry


def parse_log_source(source) -> list[dict]:
    """Parse all filterlog entries from a file-like source."""
    entries = []
    skipped = 0

    for line in source:
        line = line.strip()
        if not line or "filterlog" not in line:
            continue

        parsed = parse_filterlog_line(line)
        if parsed:
            entries.append(parsed)
        else:
            skipped += 1

    if skipped > 0:
        print(f"[info] Skipped {skipped} unparseable lines", file=sys.stderr)

    return entries


# ── Filtering ─────────────────────────────────────────────────────────────────

def apply_filters(entries: list[dict], args) -> list[dict]:
    """Apply CLI filters to parsed entries."""
    filtered = entries

    if args.action:
        filtered = [e for e in filtered if e.get("action", "").lower() == args.action.lower()]

    if args.interface:
        filtered = [e for e in filtered if e.get("interface", "").lower() == args.interface.lower()]

    if args.src_ip:
        filtered = [e for e in filtered if e.get("src_ip", "").startswith(args.src_ip)]

    if args.dst_port:
        filtered = [e for e in filtered if e.get("dst_port", "") == str(args.dst_port)]

    if args.proto:
        filtered = [e for e in filtered if e.get("proto", "").lower() == args.proto.lower()]

    return filtered


# ── Output formatters ─────────────────────────────────────────────────────────

def output_json(entries: list[dict]):
    print(json.dumps(entries, indent=2))


def output_table(entries: list[dict]):
    """Human-readable tabular output."""
    if not entries:
        print("No entries found.")
        return

    print(f"\n{'TIMESTAMP':<20} {'ACTION':<7} {'IFACE':<6} {'PROTO':<5} "
          f"{'SRC IP':<18} {'SRC PORT':<10} {'DST IP':<18} {'DST PORT':<10}")
    print("─" * 100)

    for e in entries:
        print(
            f"{e.get('raw_timestamp', ''):<20} "
            f"{e.get('action', ''):<7} "
            f"{e.get('interface', ''):<6} "
            f"{e.get('proto', ''):<5} "
            f"{e.get('src_ip', ''):<18} "
            f"{e.get('src_port', ''):<10} "
            f"{e.get('dst_ip', ''):<18} "
            f"{e.get('dst_port', ''):<10}"
        )
    print(f"\nTotal: {len(entries)} entries")


def output_report(entries: list[dict]):
    """Generate a summary threat-hunting report."""
    if not entries:
        print("No entries to report on.")
        return

    total = len(entries)
    blocks = [e for e in entries if e.get("action") == "block"]
    passes = [e for e in entries if e.get("action") == "pass"]

    print("\n" + "═" * 60)
    print("  pfSense Firewall Log Analysis Report")
    print(f"  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("═" * 60)

    print(f"\n{'SUMMARY':}")
    print(f"  Total events analyzed:  {total}")
    print(f"  Blocked:                {len(blocks)} ({len(blocks)/total*100:.1f}%)")
    print(f"  Permitted:              {len(passes)} ({len(passes)/total*100:.1f}%)")

    # Top blocked source IPs
    block_sources = Counter(e.get("src_ip", "unknown") for e in blocks)
    print(f"\n{'TOP 10 BLOCKED SOURCE IPs':}")
    print(f"  {'IP ADDRESS':<20} {'COUNT':<10} {'% OF BLOCKS'}")
    print("  " + "─" * 45)
    for ip, count in block_sources.most_common(10):
        pct = count / len(blocks) * 100 if blocks else 0
        print(f"  {ip:<20} {count:<10} {pct:.1f}%")

    # Top targeted destination ports (blocks only)
    block_ports = Counter(e.get("dst_port", "unknown") for e in blocks if e.get("dst_port"))
    print(f"\n{'TOP 10 TARGETED PORTS (blocked)':}")
    print(f"  {'PORT':<10} {'COUNT':<10} {'SERVICE'}")
    print("  " + "─" * 35)
    port_names = {
        "22": "SSH", "23": "Telnet", "80": "HTTP", "443": "HTTPS",
        "445": "SMB", "3389": "RDP", "1433": "MSSQL", "3306": "MySQL",
        "5432": "PostgreSQL", "8080": "HTTP-Alt", "8443": "HTTPS-Alt"
    }
    for port, count in block_ports.most_common(10):
        service = port_names.get(port, "unknown")
        print(f"  {port:<10} {count:<10} {service}")

    # Events by interface
    by_interface = defaultdict(lambda: defaultdict(int))
    for e in entries:
        by_interface[e.get("interface", "unknown")][e.get("action", "unknown")] += 1

    print(f"\n{'EVENTS BY INTERFACE':}")
    print(f"  {'INTERFACE':<10} {'BLOCKED':<10} {'PASSED':<10} {'TOTAL'}")
    print("  " + "─" * 40)
    for iface, actions in sorted(by_interface.items()):
        b = actions.get("block", 0)
        p = actions.get("pass", 0)
        print(f"  {iface:<10} {b:<10} {p:<10} {b+p}")

    # Protocol distribution
    proto_dist = Counter(e.get("proto", "unknown") for e in entries)
    print(f"\n{'PROTOCOL DISTRIBUTION':}")
    for proto, count in proto_dist.most_common():
        bar = "█" * min(int(count / total * 40), 40)
        print(f"  {proto:<6} {count:<6} {bar}")

    print("\n" + "═" * 60)


# ── Top N helper ──────────────────────────────────────────────────────────────

def print_top_n(entries: list[dict], field: str, n: int, label: str):
    counter = Counter(e.get(field, "unknown") for e in entries if e.get(field))
    print(f"\nTop {n} {label}:")
    print(f"  {'VALUE':<25} {'COUNT'}")
    print("  " + "─" * 35)
    for value, count in counter.most_common(n):
        print(f"  {value:<25} {count}")


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Parse pfSense filterlog output for analysis and reporting.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("--file", "-f", help="Log file to parse (default: stdin)")
    parser.add_argument("--action", choices=["block", "pass"], help="Filter by action")
    parser.add_argument("--interface", help="Filter by interface (e.g. wan, opt1)")
    parser.add_argument("--src-ip", dest="src_ip", help="Filter by source IP prefix")
    parser.add_argument("--dst-port", dest="dst_port", type=str, help="Filter by destination port")
    parser.add_argument("--proto", choices=["tcp", "udp", "icmp"], help="Filter by protocol")
    parser.add_argument("--format", choices=["table", "json"], default="table", help="Output format")
    parser.add_argument("--report", action="store_true", help="Generate summary threat-hunting report")
    parser.add_argument("--top-src", dest="top_src", type=int, metavar="N", help="Show top N source IPs")
    parser.add_argument("--top-dst", dest="top_dst", type=int, metavar="N", help="Show top N destination IPs")
    return parser.parse_args()


def main():
    args = parse_args()

    # Read input
    if args.file:
        with open(args.file, "r", encoding="utf-8", errors="replace") as f:
            entries = parse_log_source(f)
    else:
        entries = parse_log_source(sys.stdin)

    print(f"[info] Parsed {len(entries)} filterlog entries", file=sys.stderr)

    # Apply filters
    filtered = apply_filters(entries, args)
    print(f"[info] {len(filtered)} entries after filtering", file=sys.stderr)

    # Output
    if args.report:
        output_report(filtered)
    elif args.top_src:
        print_top_n(filtered, "src_ip", args.top_src, "Source IPs")
    elif args.top_dst:
        print_top_n(filtered, "dst_ip", args.top_dst, "Destination IPs")
    elif args.format == "json":
        output_json(filtered)
    else:
        output_table(filtered)


if __name__ == "__main__":
    main()
