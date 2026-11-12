"""Derived amounts and ECB reference conversions; independent of OCR/translation."""

import asyncio
import hashlib
import re
import time
import unicodedata
from datetime import date
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation, localcontext
from typing import Literal
from urllib.request import urlopen
from xml.etree import ElementTree

Currency = Literal["CNY", "PLN", "USD", "EUR"]
CURRENCIES = ("CNY", "PLN", "USD", "EUR")
ECB_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
MARKER = r"(?:CNY|RMB|CN¥|¥|元|块|PLN|zł|USD|US\$|\$|EUR|€)"
PREFIX = re.compile(rf"({MARKER})\s*$", re.IGNORECASE)
SUFFIX = re.compile(rf"^\s*({MARKER})(?![A-Za-z])", re.IGNORECASE)
NUMBER = re.compile(r"(?<![\d.,])[-+]?\d+(?:[.,]\d+)*(?:[ \u00a0\u202f]\d{3}(?!\d)(?:[.,]\d+)*)*")


def normalize_number(text):
    text = re.sub(r"\s", "", text)
    if "." in text and "," in text:
        decimal = "." if text.rfind(".") > text.rfind(",") else ","
        grouping = "," if decimal == "." else "."
        whole, fraction = text.rsplit(decimal, 1)
        if not re.fullmatch(rf"[-+]?\d{{1,3}}(?:{re.escape(grouping)}\d{{3}})+", whole):
            return None
        text = whole.replace(grouping, "") + "." + fraction
    else:
        separator = "," if "," in text else "."
        if separator in text:
            if re.fullmatch(rf"[-+]?\d{{1,3}}(?:{re.escape(separator)}\d{{3}})+", text):
                text = text.replace(separator, "")
            elif text.count(separator) == 1:
                text = text.replace(separator, ".")
            else:
                return None
    if len(text.replace(".", "").lstrip("-+")) > 18:
        return None
    return format(Decimal(text), "f")


def marker_currency(marker):
    marker = marker.upper()
    if marker in ("CNY", "RMB", "CN¥", "¥", "元", "块"):
        return "CNY"
    if marker in ("PLN", "ZŁ"):
        return "PLN"
    if marker in ("USD", "US$", "$"):
        return "USD"
    return "EUR"


def amount_candidates(region, choices=None):
    # Versioned offset/content IDs distinguish repeated amounts without saving derived data.
    text = unicodedata.normalize("NFKC", region.get("source") or region.get("raw_text") or "")
    result = []
    consumed_until = 0
    for match in NUMBER.finditer(text):
        value = normalize_number(match.group())
        if value is None:
            continue
        prefix = PREFIX.search(text[:match.start()])
        if prefix and prefix.start(1) < consumed_until:
            prefix = None
        suffix = SUFFIX.search(text[match.end():])
        marker = prefix or suffix
        currency = marker_currency(marker.group(1)) if marker else None
        start = prefix.start(1) if prefix else match.start()
        end = match.end() + suffix.end(1) if suffix and not prefix else match.end()
        consumed_until = end
        identifier = f"a1-{match.start()}-{hashlib.sha256(match.group().encode()).hexdigest()[:10]}"
        result.append({
            "id": identifier, "text": text[start:end], "value": value,
            "detected_currency": currency, "source_currency": (choices or {}).get(identifier),
        })
    return result


class RatesUnavailable(Exception):
    pass


def parse_rates(raw):
    try:
        root = ElementTree.fromstring(raw)
        daily = next(node for node in root.iter() if "time" in node.attrib)
        rate_date = date.fromisoformat(daily.attrib["time"]).isoformat()
        rates = {node.attrib["currency"]: node.attrib["rate"] for node in daily if "currency" in node.attrib}
        rates["EUR"] = "1"
        rates = {code: rates[code] for code in CURRENCIES}
        if any(not Decimal(v).is_finite() or not Decimal("0") < Decimal(v) < Decimal("1000000") for v in rates.values()):
            raise ValueError("Invalid reference rate")
        return {"date": rate_date, "rates": rates}
    except (ElementTree.ParseError, StopIteration, KeyError, InvalidOperation) as error:
        raise ValueError("Invalid ECB snapshot") from error


def fetch_rates():
    # Fixed URL, verified TLS, no screenshot content or user-controlled query parameters.
    with urlopen(ECB_URL, timeout=10) as response:
        raw = response.read(128_001)
    if len(raw) > 128_000:
        raise ValueError("ECB response too large")
    return raw


class RateService:
    def __init__(self, store, *, clock=time.time, fetch=fetch_rates):
        self.store, self.clock, self.fetch = store, clock, fetch
        self.lock = asyncio.Lock()
        self.next_check = 0

    async def snapshot(self):
        async with self.lock:
            saved = self.store.rate_snapshot()
            now = self.clock()
            if saved and now < max(self.next_check, saved["checked_at"] + 3600):
                return saved
            try:
                snapshot = parse_rates(await asyncio.to_thread(self.fetch))
                # A delayed upstream response must not roll back a newer successful snapshot.
                if saved and saved["date"] > snapshot["date"]:
                    snapshot = saved.copy()
                snapshot["checked_at"] = now
                self.store.save_rate_snapshot(snapshot)
                return snapshot
            except (OSError, ValueError):
                if saved:
                    self.next_check = now + 3600
                    return saved
                raise RatesUnavailable("Reference rates are unavailable. Retry in a moment.") from None


def convert(value, source_currency, rates):
    with localcontext() as context:
        context.prec = 50
        amount = Decimal(value)
        return {code: format(
            (amount * Decimal(rates[code]) / Decimal(rates[source_currency])).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP,
            ), ".2f",
        ) for code in CURRENCIES}
