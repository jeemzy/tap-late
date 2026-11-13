# /// script
# requires-python = ">=3.12"
# dependencies = ["zeroconf==0.154.0"]
# ///
"""Advertise the Windows-hosted viewer on one LAN interface, independently of Docker."""

import argparse
import ipaddress
import json
import logging
import signal
import socket
import subprocess
import threading
from pathlib import Path


def interface_address(alias):
    escaped = alias.replace("'", "''")
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
         f"Get-NetIPAddress -InterfaceAlias '{escaped}' -AddressFamily IPv4 -ErrorAction Stop "
         "| Where-Object { $_.AddressState -eq 'Preferred' } "
         "| Select-Object -ExpandProperty IPAddress | ConvertTo-Json -Compress"],
        capture_output=True, text=True, check=True, timeout=15,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    addresses = json.loads(result.stdout)
    for value in [addresses] if isinstance(addresses, str) else addresses:
        address = ipaddress.IPv4Address(value)
        if address.is_private and not address.is_link_local and not address.is_loopback:
            return str(address)
    raise ValueError("The selected interface has no usable private IPv4 address")


def main():
    from zeroconf import IPVersion, ServiceInfo, Zeroconf

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", default="Wi-Fi")
    parser.add_argument("--log", type=Path)
    options = parser.parse_args()
    if options.log:
        options.log.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=options.log, filemode="w", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    stopped = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    active, info, current = None, None, None
    try:
        while not stopped.is_set():
            try:
                address = interface_address(options.interface)
                if address != current:
                    if active:
                        active.unregister_service(info)
                        active.close()
                        active, info, current = None, None, None
                    active = Zeroconf(interfaces=[address], ip_version=IPVersion.V4Only)
                    info = ServiceInfo(
                        "_http._tcp.local.", "tap-late._http._tcp.local.",
                        addresses=[socket.inet_aton(address)], port=8000,
                        properties={"path": "/"}, server="tap-late.local.",
                    )
                    active.register_service(info)
                    current = address
                    logging.info("Advertising http://tap-late.local:8000 on %s (%s)", options.interface, address)
            except (OSError, ValueError, subprocess.SubprocessError):
                if active:
                    active.close()
                    active, info, current = None, None, None
                logging.exception("Cannot advertise on %s; retrying", options.interface)
            stopped.wait(30)
    finally:
        if active:
            active.unregister_service(info)
            active.close()


if __name__ == "__main__":
    main()
