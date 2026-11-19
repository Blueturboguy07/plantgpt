"""TLS connections in a pktap capture, by process (tests/updater/live-proof-macos.sh).

Reads `tcpdump -r <capture> -n -kNP -A` on stdin: each packet header carries the process
("proc <name>:<pid>") when the capture was made on the pktap interface. The host name is
the SNI in the TLS ClientHello, which is plain text. Prints one line per ClientHello:
<time> <process> <pid> <destination> <host>. Run with python3 -I.
"""
import re
import sys

HEADER = re.compile(r"^(\d{2}:\d{2}:\d{2}\.\d+) ")
PROC = re.compile(r"proc ([^:,()\s]+):(\d+)")
DEST = re.compile(r" > ([0-9A-Fa-f:.]+)\.443: ")
HOST = re.compile(
    r"(publikhq\.com|[a-z0-9-]+(?:\.[a-z0-9-]+)*\.githubusercontent\.com|(?:api\.|codeload\.)?github\.com)"
)


def flush(packet):
    if not packet:
        return
    header, payload = packet[0], "".join(packet[1:])
    hosts = sorted(set(HOST.findall(payload)))
    if not hosts:
        return
    when = HEADER.match(header).group(1)
    proc = PROC.search(header)
    dest = DEST.search(header)
    print(
        when,
        proc.group(1) if proc else "?",
        proc.group(2) if proc else "?",
        dest.group(1) if dest else "?",
        ",".join(hosts),
    )


packet = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if HEADER.match(line):
        flush(packet)
        packet = [line]
    elif packet:
        packet.append(line)
flush(packet)
