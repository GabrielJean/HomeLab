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
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

from playwright.sync_api import Page, sync_playwright


HEADLESS = True  # set to False to watch the browser
OUTPUT_DIR = Path("data_runs")
ENV_PATH = Path(".env")
ENV_URL_KEY = "URLS"
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


def load_urls(env_key: str = ENV_URL_KEY, env_path: Path = ENV_PATH) -> List[str]:
	"""Load URLs from the specified environment variable, populating from .env if present."""
	load_env_file(env_path)
	raw = os.getenv(env_key, "")
	urls = parse_urls(raw)
	if not urls:
		raise SystemExit(
			f"Set {env_key} in {env_path} (JSON array or comma-separated list) before running."
		)
	return urls


def safe_slug(url: str, index: int) -> str:
	"""Create a stable, filename-safe slug for a URL."""
	parsed = urlparse(url)
	host = (parsed.hostname or "url").replace(" ", "-")
	first_path = (parsed.path.strip("/") or "path").split("/")[0]
	first_path = first_path.replace(" ", "-") or "path"
	digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:8]
	return f"{index + 1}-{host}-{first_path}-{digest}"


def write_outputs_for_result(result: Dict[str, Optional[str]], slug: str, timestamp: str) -> None:
	"""Write per-URL JSON (timestamped) and CSV (append-only) outputs."""
	OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
	ts_safe = timestamp.replace(":", "-")

	json_path = OUTPUT_DIR / f"{slug}_{ts_safe}.json"
	json_path.write_text(json.dumps(result, indent=2))

	csv_path = OUTPUT_DIR / f"{slug}.csv"
	fieldnames = sorted(result.keys())
	write_header = not csv_path.exists()
	with csv_path.open("a", newline="") as f:
		writer = csv.DictWriter(f, fieldnames=fieldnames)
		if write_header:
			writer.writeheader()
		writer.writerow(result)


def scrape_page(page: Page, url: str, selectors: Dict[str, str]) -> Dict[str, Optional[str]]:
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

	results: List[Dict[str, Optional[str]]] = []
	timestamp = datetime.now(timezone.utc).isoformat()

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

		for idx, url in enumerate(urls):
			result = scrape_page(page, url, selectors)
			result["timestamp"] = timestamp
			slug = safe_slug(url, idx)
			write_outputs_for_result(result, slug, timestamp)
			results.append(result)

		browser.close()

	# Still emit a combined snapshot for convenience per run.
	OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
	json_path = OUTPUT_DIR / "scrape_output.json"
	json_path.write_text(json.dumps(results, indent=2))

	csv_path = OUTPUT_DIR / "scrape_output.csv"
	fieldnames = sorted(results[0].keys()) if results else []
	write_header = not csv_path.exists()
	with csv_path.open("a", newline="") as f:
		writer = csv.DictWriter(f, fieldnames=fieldnames)
		if write_header:
			writer.writeheader()
		writer.writerows(results)

	print(
		f"Wrote {len(results)} rows (per-URL files + aggregate {json_path.resolve()} and {csv_path.resolve()})"
	)


if __name__ == "__main__":
	main()
