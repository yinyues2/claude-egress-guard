#!/usr/bin/env python3
"""Privacy and secret leak scanner for this repository.

Fails when a tracked file contains something that should never be published:
credentials, personal identifiers, or infrastructure addresses outside the
documentation ranges.

Usage:
    python3 tools/leak-scan.py [path ...]

Exit status: 0 clean, 1 findings, 2 usage error.
"""

from __future__ import annotations

import ipaddress
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ALLOWED_EMAIL_DOMAINS = {
    "example.com",
    "example.org",
    "example.net",
    "users.noreply.github.com",
    "noreply.github.com",
}

# Ranges that are safe to publish: loopback, link-local, RFC 1918, CGNAT and the
# three documentation blocks.
ALLOWED_NETS = [
    ipaddress.ip_network(n)
    for n in (
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.2.0/24",
        "192.168.0.0/16",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",
        "255.255.255.255/32",
    )
]

ALLOWED_HOME_USER = {"user", "runner", "example", "name"}

UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
IPV4_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")
HOME_RE = re.compile(r"(?:/home/|/Users/)([A-Za-z0-9._-]+)")
WIN_HOME_RE = re.compile(r"[Cc]:\\Users\\([A-Za-z0-9._-]+)")
LONG_HEX_RE = re.compile(r"\b[0-9a-fA-F]{64,}\b")
CN_MOBILE_RE = re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")
TG_TOKEN_RE = re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{35}\b")

TOKENS = {
    "private-key": re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
    "github-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"),
    "aws-key": re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    "slack-token": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    "openai-key": re.compile(r"\bsk-[A-Za-z0-9]{32,}"),
    "google-key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "huggingface-token": re.compile(r"\bhf_[A-Za-z0-9]{30,}"),
}


@dataclass
class Finding:
    path: str
    line: int
    rule: str
    preview: str


def redact(value: str, keep: int = 3) -> str:
    if len(value) <= keep:
        return "***"
    return value[:keep] + "***"


def iter_files(paths: list[str]) -> list[Path]:
    roots = [Path(p) for p in paths] or [Path(".")]
    out: list[Path] = []
    for root in roots:
        if root.is_file():
            out.append(root)
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            if any(part in {".git", "node_modules", "__pycache__"} for part in path.parts):
                continue
            out.append(path)
    return out


def is_binary(path: Path) -> bool:
    try:
        chunk = path.read_bytes()[:4096]
    except OSError:
        return True
    return b"\x00" in chunk


def check_line(rule: str, text: str, match: re.Match[str]) -> Finding | None:
    value = match.group(0)
    if rule == "email":
        if match.group(1).lower() in ALLOWED_EMAIL_DOMAINS:
            return None
        return Finding("", 0, rule, redact(value))
    if rule == "ipv4":
        try:
            addr = ipaddress.ip_address(value)
        except ValueError:
            return None
        if any(addr in net for net in ALLOWED_NETS):
            return None
        return Finding("", 0, rule, redact(value, keep=6))
    if rule == "home-path":
        if value.split("/")[-1].lower() in ALLOWED_HOME_USER:
            return None
        return Finding("", 0, rule, value.rsplit("/", 1)[0] + "/***")
    if rule == "win-home-path":
        if value.split("\\")[-1].lower() in ALLOWED_HOME_USER:
            return None
        return Finding("", 0, rule, value.rsplit("\\", 1)[0] + "\\***")
    if rule in TOKENS or rule in {"uuid", "long-hex", "cn-mobile", "telegram-token"}:
        return Finding("", 0, rule, redact(value))
    return Finding("", 0, rule, redact(value))


def scan(path: Path) -> list[Finding]:
    if is_binary(path):
        return []
    findings: list[Finding] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return findings
    for lineno, line in enumerate(text.splitlines(), start=1):
        for rule, regex in TOKENS.items():
            for match in regex.finditer(line):
                found = check_line(rule, line, match)
                if found:
                    found.path, found.line = str(path), lineno
                    findings.append(found)
        for rule, regex in (
            ("uuid", UUID_RE),
            ("long-hex", LONG_HEX_RE),
            ("email", EMAIL_RE),
            ("ipv4", IPV4_RE),
            ("home-path", HOME_RE),
            ("win-home-path", WIN_HOME_RE),
            ("cn-mobile", CN_MOBILE_RE),
            ("telegram-token", TG_TOKEN_RE),
        ):
            for match in regex.finditer(line):
                found = check_line(rule, line, match)
                if found:
                    found.path, found.line = str(path), lineno
                    findings.append(found)
    return findings


def main(argv: list[str]) -> int:
    if argv and argv[0] in {"-h", "--help"}:
        print(__doc__)
        return 0
    findings: list[Finding] = []
    for path in iter_files(argv):
        if path.name == "leak-scan.py":
            continue
        findings.extend(scan(path))
    if not findings:
        print("leak-scan: clean")
        return 0
    for item in findings:
        print(f"{item.path}:{item.line}: {item.rule}: {item.preview}")
    print(f"leak-scan: {len(findings)} finding(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
