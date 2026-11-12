import asyncio
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from taplate.app import create_app
from taplate.storage import Store
from tests.test_sessions import screenshot


def test_amounts_are_derived_from_corrected_source_for_old_sessions():
    from taplate.currency import amount_candidates

    region = {"source": "￥128.00 / 1 234,50 zł / USD 0 / €1.005,25 / $1,234.56", "raw_text": "999"}
    amounts = amount_candidates(region)
    assert [a["value"] for a in amounts] == ["128.00", "1234.50", "0", "1005.25", "1234.56"]
    assert [a["detected_currency"] for a in amounts] == ["CNY", "PLN", "USD", "EUR", "USD"]
    assert amount_candidates(region) == amounts
    assert len({a["id"] for a in amounts}) == 5
    assert amount_candidates({"source": "", "raw_text": "128.00"})[0]["detected_currency"] is None
    assert amount_candidates({"source": "no numbers", "raw_text": "128"}) == []


@pytest.mark.parametrize(("text", "values"), [
    ("0 0.00 ¥0", ["0", "0.00", "0"]),
    ("1,234 1.234 12,50 12.50", ["1234", "1234", "12.50", "12.50"]),
    ("128 / 128", ["128", "128"]),
    ("-12.50", ["-12.50"]),
    ("1,23,45", []),
    ("１２８．００元", ["128.00"]),
])
def test_numeric_separators_and_zero(text, values):
    from taplate.currency import amount_candidates

    assert [a["value"] for a in amount_candidates({"source": text})] == values


def test_currency_markers_are_owned_by_one_amount():
    from taplate.currency import amount_candidates

    amounts = amount_candidates({"source": "10 USD 20 EUR 30 PLN"})
    assert [a["detected_currency"] for a in amounts] == ["USD", "EUR", "PLN"]
    assert [a["text"] for a in amounts] == ["10 USD", "20 EUR", "30 PLN"]


def make_session(client, root):
    identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
    Store(root).update(identifier, status="ready", regions=[
        {"id": "r001", "source": "128 / 128", "raw_text": "999", "translation": "128 / 128"},
        {"id": "r002", "source": "¥0", "raw_text": "¥0", "translation": "¥0"},
    ])
    return identifier


def test_endpoints_validate_and_persist_independent_choices_across_devices_and_restart(tmp_path, monkeypatch):
    from taplate.currency import RateService

    async def rates(self):
        return {"date": "2026-11-12", "rates": {"EUR": "1", "CNY": "8", "PLN": "4", "USD": "1.1"}}

    monkeypatch.setattr(RateService, "snapshot", rates)
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        identifier = make_session(client, tmp_path)
        base = f"/api/sessions/{identifier}"
        amounts = client.get(base).json()["regions"][0]["amounts"]
        paths = [f"{base}/regions/r001/amounts/{a['id']}" for a in amounts]
        assert client.post(paths[0] + "/convert").status_code == 409
        assert client.patch(paths[0] + "/currency", json={"currency": "JPY"}).status_code == 422
        assert client.patch(base + "/regions/r001/amounts/fake/currency", json={"currency": "CNY"}).status_code == 404
        assert client.patch(paths[0] + "/currency", json={"currency": "CNY"}).status_code == 200
        assert client.patch(paths[1] + "/currency", json={"currency": "PLN"}).status_code == 200
        result = client.post(paths[0] + "/convert").json()
        assert result["values"] == {"CNY": "128.00", "PLN": "64.00", "USD": "17.60", "EUR": "16.00"}
        assert result["rate_date"] == "2026-11-12"
        assert client.post(paths[1] + "/convert").json()["values"]["CNY"] == "256.00"
        assert client.patch(paths[0] + "/currency", json={"currency": "EUR"}, headers={"Origin": "https://evil.example"}).status_code == 403
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as other_device:
        saved = other_device.get(base).json()["regions"][0]["amounts"]
        assert [a["source_currency"] for a in saved] == ["CNY", "PLN"]
        assert other_device.delete(base).status_code == 204
        assert other_device.post(paths[0] + "/convert").status_code == 404


def test_choices_merge_atomically_with_session_updates(tmp_path):
    store = Store(tmp_path)
    store.create({"id": "test", "status": "ready", "created_at": 1, "expires_at": 9999999999, "digest": "x", "regions": []})
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(store.save_currency, "test", "r001", f"a{i}", "PLN") for i in range(20)]
        futures += [pool.submit(store.update, "test", error=None) for _ in range(10)]
        for future in futures:
            future.result()
    assert len(Store(tmp_path).get("test")["amount_currencies"]["r001"]) == 20


XML = b'''<Envelope xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref"><Cube><Cube time="2026-11-12"><Cube currency="CNY" rate="8"/><Cube currency="PLN" rate="4"/><Cube currency="USD" rate="1.1"/></Cube></Cube></Envelope>'''


def test_rates_cached_in_sqlite_refresh_hourly_and_fall_back_on_failure(tmp_path):
    from taplate.currency import RateService, RatesUnavailable

    now, calls = [10000], []

    def fetch():
        calls.append(1)
        return XML

    store = Store(tmp_path)
    service = RateService(store, clock=lambda: now[0], fetch=fetch)
    first = asyncio.run(service.snapshot())
    assert first["rates"]["EUR"] == "1"
    assert asyncio.run(RateService(Store(tmp_path), clock=lambda: now[0], fetch=fetch).snapshot()) == first
    assert len(calls) == 1
    now[0] += 3601

    def broken():
        calls.append(1)
        raise OSError("offline")

    service.fetch = broken
    assert asyncio.run(service.snapshot()) == first
    assert asyncio.run(service.snapshot()) == first
    assert len(calls) == 2
    with pytest.raises(RatesUnavailable):
        asyncio.run(RateService(Store(tmp_path / "empty"), fetch=broken).snapshot())


def test_decimal_rounding_and_invalid_feed():
    from taplate.currency import convert, parse_rates

    assert convert("1.005", "EUR", {c: "1" for c in ("EUR", "CNY", "PLN", "USD")})["USD"] == "1.01"
    assert convert("0", "EUR", {c: "1" for c in ("EUR", "CNY", "PLN", "USD")})["USD"] == "0.00"
    assert Decimal(parse_rates(XML)["rates"]["CNY"]) == 8
    for invalid in (XML.replace(b'rate="8"', b'rate="0"'), XML.replace(b'currency="USD"', b'currency="JPY"'), b"bad"):
        with pytest.raises(ValueError):
            parse_rates(invalid)


def test_conversion_unavailable_keeps_details_and_saved_choice(tmp_path, monkeypatch):
    from taplate.currency import RateService, RatesUnavailable

    async def offline(self):
        raise RatesUnavailable("Reference rates are unavailable. Retry in a moment.")

    monkeypatch.setattr(RateService, "snapshot", offline)
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        identifier = make_session(client, tmp_path)
        base = f"/api/sessions/{identifier}"
        amount = client.get(base).json()["regions"][0]["amounts"][0]
        path = f"{base}/regions/r001/amounts/{amount['id']}"
        assert client.patch(path + "/currency", json={"currency": "EUR"}).status_code == 200
        assert client.post(path + "/convert").status_code == 503
        doc = client.get(base).json()
        assert doc["status"] == "ready"
        assert doc["regions"][0]["source"] == "128 / 128"
        assert doc["regions"][0]["amounts"][0]["source_currency"] == "EUR"


def test_conversion_endpoints_obey_session_expiry(tmp_path):
    now = [1000000.0]
    with TestClient(create_app(data_dir=tmp_path, start_worker=False, clock=lambda: now[0])) as client:
        identifier = make_session(client, tmp_path)
        base = f"/api/sessions/{identifier}"
        amount = client.get(base).json()["regions"][0]["amounts"][0]
        path = f"{base}/regions/r001/amounts/{amount['id']}"
        now[0] += 7 * 86400
        assert client.patch(path + "/currency", json={"currency": "CNY"}).status_code == 410
        assert client.post(path + "/convert").status_code == 404
        assert Store(tmp_path).get(identifier) is None


def test_choice_changes_during_rate_fetch_cannot_return_old_conversion(tmp_path, monkeypatch):
    import threading

    from taplate.currency import RateService

    started, finish = threading.Event(), threading.Event()

    async def slow(self):
        started.set()
        while not finish.is_set():
            await asyncio.sleep(.01)
        return {"date": "2026-11-12", "rates": {"EUR": "1", "CNY": "8", "PLN": "4", "USD": "1.1"}}

    monkeypatch.setattr(RateService, "snapshot", slow)
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        identifier = make_session(client, tmp_path)
        base = f"/api/sessions/{identifier}"
        amount = client.get(base).json()["regions"][0]["amounts"][0]
        path = f"{base}/regions/r001/amounts/{amount['id']}"
        client.patch(path + "/currency", json={"currency": "CNY"})
        with ThreadPoolExecutor() as pool:
            future = pool.submit(client.post, path + "/convert")
            try:
                assert started.wait(3)
                assert client.patch(path + "/currency", json={"currency": "USD"}).status_code == 200
            finally:
                finish.set()
            assert future.result().status_code == 409
