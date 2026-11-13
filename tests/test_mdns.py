import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "advertise-mdns.py"
spec = importlib.util.spec_from_file_location("taplate_mdns", MODULE)
mdns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mdns)


def test_mdns_uses_private_address_from_selected_interface(monkeypatch):
    commands = []

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(stdout='["169.254.1.2", "192.168.89.30"]')

    monkeypatch.setattr(mdns.subprocess, "run", run)
    assert mdns.interface_address("Wi-Fi") == "192.168.89.30"
    assert "-InterfaceAlias 'Wi-Fi'" in commands[0][-1]


@pytest.mark.parametrize("addresses", ['"127.0.0.1"', '"169.254.1.2"', '"8.8.8.8"', '[]'])
def test_mdns_does_not_advertise_loopback_disconnected_or_public_addresses(monkeypatch, addresses):
    monkeypatch.setattr(mdns.subprocess, "run", lambda *args, **kwargs: SimpleNamespace(stdout=addresses))
    with pytest.raises(ValueError):
        mdns.interface_address("Wi-Fi")
