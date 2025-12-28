"""Scrape a list of URLs (dynamic pages too) with Playwright.

How to use with Chrome DevTools selectors:
1) Open the page in Chrome, right-click the element -> Inspect.
2) Right-click the highlighted node -> Copy -> Copy selector.
3) Paste that selector into the `selectors` dict below.


Set your URLs in `.env` (key `URLS`) as a JSON array or comma-separated list, then run:
	pip install playwright
	playwright install chromium
	python test.py

Outputs consistent fields to scrape_output.json.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
from datetime import datetime, timezone, tzinfo
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from pathlib import Path
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Union
from urllib.parse import urlparse

from playwright.sync_api import Page, sync_playwright


HEADLESS = True  # set to False to watch the browser
OUTPUT_DIR = Path("data_runs")
ENV_PATH = Path(".env")
ENV_URL_KEY = "URLS"
def get_local_tz(key: str = "America/Toronto") -> tzinfo:
	"""Return desired TZ or UTC if tzdata is missing in the container."""
	try:
		return ZoneInfo(key)
	except ZoneInfoNotFoundError:
		print(f"Warning: timezone '{key}' not found; falling back to UTC")
		return timezone.utc


LOCAL_TZ = get_local_tz()

# Keep a stable field order for CSV-friendly outputs.
OUTPUT_FIELDS = [
	"timestamp_utc",
	"timestamp_local",
	"name",
	"direction",
	"slug",
	"url",
	"page_title",
	"duration_text",
	"duration_minutes",
]


@dataclass
class UrlEntry:
	name: str
	direction: str
	url: str

def load_env_file(env_path: Path = ENV_PATH) -> None:
	"""Populate os.environ with values from a simple .env file if present."""
	if not env_path.exists():
		return

	for line in env_path.read_text().splitlines():
		line = line.strip()
		if not line or line.startswith("#") or "=" not in line:
			continue
		key, value = line.split("=", 1)
		key = key.strip()
		# Remove surrounding quotes to make comma or JSON parsing easier later.
		value = value.strip().strip("\"").strip("'")
		os.environ.setdefault(key, value)


def parse_urls(raw_urls: str) -> List[str]:
	"""Return a list of URLs from a JSON array or comma-separated string."""
	urls: List[str] = []
	if not raw_urls:
		return urls

	try:
		parsed = json.loads(raw_urls)
		if isinstance(parsed, str):
			urls = [parsed]
		elif isinstance(parsed, list):
			urls = [u for u in parsed if isinstance(u, str)]
		else:
			parsed = []  # fall back to comma parsing below
	except json.JSONDecodeError:
		parsed = []

	if not urls and raw_urls:
		urls = [u.strip() for u in raw_urls.split(",") if u.strip()]

	return [u for u in urls if u]


def parse_url_entries(raw_urls: str) -> List[UrlEntry]:
	"""Return structured URL entries from a JSON array of strings or objects."""
	if not raw_urls:
		return []
	try:
		parsed = json.loads(raw_urls)
	except json.JSONDecodeError:
		parsed = None

	entries: List[UrlEntry] = []
	if isinstance(parsed, list):
		for idx, item in enumerate(parsed):
			if isinstance(item, str):
				entries.append(UrlEntry(name=f"group-{idx + 1}", direction=f"dir-{idx + 1}", url=item))
			elif isinstance(item, dict):
				url = item.get("url") or item.get("URL") or item.get("href")
				if not isinstance(url, str) or not url.strip():
					continue
				name = item.get("name") or item.get("label") or f"group-{idx + 1}"
				direction = item.get("direction") or item.get("dir") or f"dir-{idx + 1}"
				entries.append(UrlEntry(name=name, direction=direction, url=url.strip()))
	elif isinstance(parsed, str):
		entries.append(UrlEntry(name="group-1", direction="dir-1", url=parsed))

	return entries


def load_urls(env_key: str = ENV_URL_KEY, env_path: Path = ENV_PATH) -> List[UrlEntry]:
	"""Load URLs from env var (JSON/CSV) with optional friendly names and directions."""
	load_env_file(env_path)

	raw = os.getenv(env_key, "")
	entries = parse_url_entries(raw)

	# Fallback: plain JSON/CSV list of URLs without objects
	if not entries:
		urls = parse_urls(raw)
		entries = [
			UrlEntry(name=f"group-{idx + 1}", direction=f"dir-{idx + 1}", url=url)
			for idx, url in enumerate(urls)
		]

	if not entries:
		raise SystemExit(
			f"Provide URLs via {env_key} in {env_path} (JSON array or comma-separated) before running."
		)
	return entries


def clean_segment(text: str) -> str:
	"""Make a string filesystem-safe (alnum, dash, underscore)."""
	cleaned = "".join(c if c.isalnum() or c in "-_" else "-" for c in text.strip())
	return cleaned or "default"


def safe_slug(entry: UrlEntry, index: int) -> str:
	"""Create a stable, filename-safe slug using friendly name, direction, and URL context."""
	parsed = urlparse(entry.url)
	host = (parsed.hostname or "url").replace(" ", "-")
	path_parts = [p.replace(" ", "-") for p in parsed.path.split("/") if p]
	path_part = "-".join(path_parts[:3]) if path_parts else "root"
	query_hint = ""
	if parsed.query:
		query_hint = f"-q{hashlib.sha1(parsed.query.encode('utf-8')).hexdigest()[:6]}"
	digest = hashlib.sha1(entry.url.encode("utf-8")).hexdigest()[:6]
	name_part = clean_segment(entry.name)
	dir_part = clean_segment(entry.direction)
	return f"{index + 1}-{name_part}-{dir_part}-{host}-{path_part}{query_hint}-{digest}"


def parse_duration_minutes(duration_text: Optional[str]) -> Optional[float]:
	"""Convert duration strings like '1 hr 5 min' or '45 min' to total minutes."""
	if not duration_text:
		return None

	tokens = duration_text.lower().replace("hrs", "hr").replace("mins", "min").split()
	hours = 0
	minutes = 0

	for idx, token in enumerate(tokens):
		if token.isdigit():
			next_token = tokens[idx + 1] if idx + 1 < len(tokens) else ""
			if next_token.startswith("hr"):
				hours += int(token)
			elif next_token.startswith("min"):
				minutes += int(token)

	total_minutes = hours * 60 + minutes
	return total_minutes if total_minutes > 0 else None


def write_url_manifest(entries: List[UrlEntry], slugs: List[str], timestamp: str) -> None:
	"""Deprecated: per-run manifests removed in favor of per-URL histories."""
	raise NotImplementedError("Manifest writing is disabled; use per-URL CSVs instead.")



def write_outputs_for_result(result: Dict[str, Optional[Any]], entry: UrlEntry, slug: str) -> None:
	"""Append per-URL CSV (single rolling file) grouped by name/direction."""
	name_part = clean_segment(entry.name)
	dir_part = clean_segment(entry.direction)
	output_base = OUTPUT_DIR / name_part / dir_part
	output_base.mkdir(parents=True, exist_ok=True)

	csv_path = output_base / f"{slug}.csv"
	write_header = not csv_path.exists()
	with csv_path.open("a", newline="") as f:
		writer = csv.DictWriter(f, fieldnames=OUTPUT_FIELDS)
		if write_header:
			writer.writeheader()
		writer.writerow({field: result.get(field) for field in OUTPUT_FIELDS})


def scrape_page(page: Page, url: str, selectors: Dict[str, Union[str, List[str]]]) -> Dict[str, Optional[Any]]:
	"""Navigate and extract text for each named selector."""
	# Longer timeout because Google Maps can be slow; fall back to page load
	page.goto(url, wait_until="load", timeout=60_000)

	# Ensure at least one result card is present before scraping; ignore if missing
	try:
		page.wait_for_selector("#section-directions-trip-0, #section-directions-trip-1", timeout=30_000)
	except Exception:
		pass

	data: Dict[str, Optional[str]] = {"url": url}
	for field, selector in selectors.items():
		# Allow a selector string or a list of fallback selectors.
		selector_list = selector if isinstance(selector, list) else [selector]
		value: Optional[str] = None
		for sel in selector_list:
			node = page.query_selector(sel)
			if node:
				value = node.inner_text().strip()
				break
		data[field] = value
	return data


def main() -> None:
	# Replace these with selectors you copy from DevTools.
	# Example for Google Maps directions page (adjust as needed):
	selectors = {
		"page_title": "title",
		# Try primary then fallback selectors (first and second route cards)
		"duration": [
			"#section-directions-trip-0 > div.MespJc > div > div.XdKEzd > div.Fk3sm.fontHeadlineSmall.bKVTGe",
			"#section-directions-trip-1 > div.MespJc > div > div.XdKEzd > div.Fk3sm.fontHeadlineSmall.bKVTGe",
		],
		# "distance": "div[jslog][aria-label*='Directions'] span+span",
	}

	urls = load_urls()

	results: List[Dict[str, Optional[Any]]] = []
	now_utc = datetime.now(timezone.utc)
	timestamp_utc = now_utc.isoformat()
	timestamp_local = now_utc.astimezone(LOCAL_TZ).isoformat()

	with sync_playwright() as p:
		browser = p.chromium.launch(headless=HEADLESS)
		page = browser.new_page()

		# Set a common UA to reduce bot friction and extend default timeouts
		page.set_extra_http_headers({
			"User-Agent": (
				"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
				"AppleWebKit/537.36 (KHTML, like Gecko) "
				"Chrome/120.0 Safari/537.36"
			)
		})
		page.set_default_timeout(60_000)

		url_slugs: List[str] = []
		for idx, entry in enumerate(urls):
			slug = safe_slug(entry, idx)
			url_slugs.append(slug)
			result = scrape_page(page, entry.url, selectors)
			result["timestamp_utc"] = timestamp_utc
			result["timestamp_local"] = timestamp_local
			result["slug"] = slug
			result["name"] = entry.name
			result["direction"] = entry.direction
			result["duration_minutes"] = parse_duration_minutes(result.get("duration"))
			result["duration_text"] = result.pop("duration", None)
			write_outputs_for_result(result, entry, slug)
			results.append(result)

		browser.close()

	# Per-run combined outputs and manifests removed; history lives in per-URL CSVs only.

	print(f"Wrote {len(results)} rows (per-URL CSV histories only)")


if __name__ == "__main__":
	main()
