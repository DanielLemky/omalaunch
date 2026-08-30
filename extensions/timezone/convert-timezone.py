#!/usr/bin/env python3

import json
import os
import re
import sys
from datetime import date, datetime
from functools import cache
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones


def normalize(value):
    return re.sub(r"\s+", " ", value.strip().lower().replace("_", " "))


def load_aliases():
    path = Path(__file__).with_name("aliases.json")
    with path.open(encoding="utf-8") as handle:
        return {normalize(key): value for key, value in json.load(handle).items()}


def local_zone_name():
    configured = os.environ.get("TZ", "").strip()
    if configured:
        return configured
    try:
        target = Path("/etc/localtime").resolve()
        marker = "/usr/share/zoneinfo/"
        if marker in str(target):
            return str(target).split(marker, 1)[1]
    except OSError:
        pass
    try:
        value = Path("/etc/timezone").read_text(encoding="utf-8").strip()
        if value:
            return value
    except OSError:
        pass
    return "UTC"


@cache
def zone_index():
    zones = sorted(available_timezones())
    exact = {zone.lower(): zone for zone in zones}
    cities = {}
    ambiguous = set()
    for zone in zones:
        city = normalize(zone.rsplit("/", 1)[-1])
        if city in cities and cities[city] != zone:
            ambiguous.add(city)
        else:
            cities[city] = zone
    for city in ambiguous:
        cities.pop(city, None)
    return exact, cities


ALIASES = load_aliases()


def resolve_zone(value):
    raw = value.strip()
    key = normalize(raw)
    zone_name = ALIASES.get(key)

    # Most lookups are aliases or correctly-cased IANA names. Resolve those
    # without scanning the entire system timezone database on every query.
    if not zone_name:
        try:
            return ZoneInfo(raw), raw
        except ZoneInfoNotFoundError:
            pass

        exact_zones, city_zones = zone_index()
        zone_name = exact_zones.get(raw.lower()) or city_zones.get(key)

    if not zone_name:
        raise ValueError(f"Unknown timezone: {raw}")
    try:
        return ZoneInfo(zone_name), zone_name
    except ZoneInfoNotFoundError:
        raise ValueError(f"Timezone data unavailable: {zone_name}")


def parse_clock(value):
    compact = re.sub(r"\s+", "", value).upper()
    formats = ["%I%p", "%I:%M%p"] if compact.endswith(("AM", "PM")) else ["%H:%M", "%H"]
    for pattern in formats:
        try:
            return datetime.strptime(compact, pattern).time()
        except ValueError:
            pass
    raise ValueError(f"Invalid time: {value}")


def clock(value):
    return value.strftime("%I:%M %p %Z").lstrip("0")


def day(value):
    return value.strftime("%a, %b %d").replace(" 0", " ")


def current_time(place):
    zone, zone_name = resolve_zone(place)
    now = datetime.now(zone)
    return f"{clock(now)} · {day(now)} · {zone_name}"


def convert_time(expression):
    match = re.fullmatch(
        r"(?:(?P<date>\d{4}-\d{2}-\d{2})\s+)?"
        r"(?P<time>\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"
        r"(?:\s+(?P<source>.+?))?\s+to\s+(?P<destination>.+)",
        expression,
        flags=re.IGNORECASE,
    )
    if not match:
        raise ValueError("Try: time 9am winnipeg to seattle")

    source_name = match.group("source") or local_zone_name()
    source_zone, _ = resolve_zone(source_name)
    destination_zone, destination_name = resolve_zone(match.group("destination"))
    source_date = date.fromisoformat(match.group("date")) if match.group("date") else datetime.now(source_zone).date()
    source = datetime.combine(source_date, parse_clock(match.group("time")), source_zone)
    destination = source.astimezone(destination_zone)
    return f"{clock(source)} → {clock(destination)} · {day(destination)} · {destination_name}"


def main():
    query = " ".join(sys.argv[1:]).strip()
    if not re.match(r"^time\s+", query, flags=re.IGNORECASE):
        raise ValueError("Query must start with: time")
    expression = re.sub(r"^time\s+", "", query, count=1, flags=re.IGNORECASE).strip()
    if not expression:
        raise ValueError("Try: time seattle")
    return convert_time(expression) if re.search(r"\s+to\s+", expression, flags=re.IGNORECASE) else current_time(expression)


try:
    print(main())
except (ValueError, ZoneInfoNotFoundError) as error:
    print(error)
