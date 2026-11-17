#!/usr/bin/env python3
"""Select or create the physical test phone's exact simulator counterpart."""
import json
import subprocess
import sys

MODEL = "iPhone 17 Pro Max"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
OS_VERSION = "27.2"


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


runtimes = json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
runtime = next((r for r in runtimes if r.get("isAvailable")
                and r.get("version") == OS_VERSION
                and any(t["identifier"] == DEVICE_TYPE
                        for t in r.get("supportedDeviceTypes", []))), None)
if runtime is None:
    sys.exit(f"Required simulator unavailable: {MODEL}, iOS {OS_VERSION}. No fallback device is allowed.")

devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
device = next((d for d in devices.get(runtime["identifier"], [])
               if d["name"] == MODEL and d.get("isAvailable")), None)
udid = device["udid"] if device else simctl("create", MODEL, DEVICE_TYPE, runtime["identifier"])
print(f"Using {MODEL}, iOS {OS_VERSION} ({udid})", file=sys.stderr)
print(udid)
