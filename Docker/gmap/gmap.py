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
import re
import statistics
from collections import defaultdict
from datetime import datetime, timezone, tzinfo
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from pathlib import Path
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple, Union
from urllib.parse import urlparse

import matplotlib
matplotlib.use("Agg")  # headless-safe backend for PNG output
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
from playwright.sync_api import Page, sync_playwright


HEADLESS = True  # set to False to watch the browser
OUTPUT_DIR = Path("data_runs")
LOG_PATH = OUTPUT_DIR / "logs.txt"
SNAPSHOT_LOG_PATH = OUTPUT_DIR / "snapshots.log"
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
	"timestamp_local",
	"day_of_week",
	"name",
	"page_title",
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


def log_message(message: str) -> None:
	"""Append a timestamped log line to the host-mounted logs file."""
	LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
	now = datetime.now(timezone.utc).astimezone(LOCAL_TZ).isoformat()
	with LOG_PATH.open("a", encoding="utf-8") as f:
		f.write(f"{now}\t{message}\n")


def log_snapshot(entry: UrlEntry, message: str) -> None:
	"""Append a timestamped line to a per-URL snapshot log file for easier navigation."""
	base = OUTPUT_DIR / "snapshots" / clean_segment(entry.name) / clean_segment(entry.direction)
	base.mkdir(parents=True, exist_ok=True)
	date_str = datetime.now(LOCAL_TZ).strftime("%Y-%m-%d")
	file_path = base / f"{date_str}.log"
	now = datetime.now(timezone.utc).astimezone(LOCAL_TZ).isoformat()
	with file_path.open("a", encoding="utf-8") as f:
		f.write(f"{now}\t{message}\n")


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


def extract_duration_fragment(text: str) -> Optional[str]:
	"""Pull a plausible duration fragment (e.g., '1 hr 5 min' or '38 min') from free text."""
	patterns = [
		r"(\d+\s*hr\s*\d+\s*min)",
		r"(\d+\s*hr)",
		r"(\d+\s*min)",
	]
	for pat in patterns:
		match = re.search(pat, text, re.IGNORECASE)
		if match:
			return match.group(1)
	return None


def scrape_duration_value(page: Page, selector: Union[str, List[str]]) -> Optional[str]:
	"""Fetch a duration string using primary/fallback selectors."""
	selector_list = selector if isinstance(selector, list) else [selector]
	for sel in selector_list:
		node = page.query_selector(sel)
		if node:
			text = (node.inner_text() or "").strip()
			if text:
				return text
	return None


def route_card_text(page: Page) -> Optional[str]:
	"""Return flattened text from the first route card if present."""
	node = page.query_selector("#section-directions-trip-0")
	if node:
		text = (node.inner_text() or "").strip()
		if text:
			return " ".join(text.split())
	return None


def route_cards_texts(page: Page) -> List[str]:
	"""Return flattened texts for all visible route cards (ordered)."""
	nodes = page.query_selector_all("[id^='section-directions-trip-']")
	texts: List[str] = []
	for node in nodes:
		text = (node.inner_text() or "").strip()
		if text:
			texts.append(" ".join(text.split()))
	return texts


def snapshot_text(page: Page) -> str:
	"""Capture a lightweight text snapshot from the first route card (fallback to body)."""
	for sel in ["#section-directions-trip-0", "body"]:
		node = page.query_selector(sel)
		if node:
			text = (node.inner_text() or "").strip()
			if text:
				flat = " ".join(text.split())
				return flat[:800]
	return ""


def write_url_manifest(entries: List[UrlEntry], slugs: List[str], timestamp: str) -> None:
	"""Deprecated: per-run manifests removed in favor of per-URL histories."""
	raise NotImplementedError("Manifest writing is disabled; use per-URL CSVs instead.")



def write_outputs_for_result(result: Dict[str, Optional[Any]], entry: UrlEntry, slug: str) -> None:
	"""Append per-URL CSV (single rolling file) grouped by name/direction."""
	name_part = clean_segment(entry.name)
	dir_part = clean_segment(entry.direction)
	output_base = OUTPUT_DIR / name_part / dir_part
	output_base.mkdir(parents=True, exist_ok=True)

	# Keep file names short: just the friendly name + direction
	csv_path = output_base / f"{name_part}-{dir_part}.csv"
	write_header = not csv_path.exists()
	with csv_path.open("a", newline="") as f:
		writer = csv.DictWriter(f, fieldnames=OUTPUT_FIELDS)
		if write_header:
			writer.writeheader()
		writer.writerow({field: result.get(field) for field in OUTPUT_FIELDS})


def parse_timestamp(value: str) -> Optional[datetime]:
	"""Parse ISO timestamps while tolerating missing timezone info."""
	if not value:
		return None
	try:
		dt = datetime.fromisoformat(value)
		dt = dt.astimezone(LOCAL_TZ) if dt.tzinfo else dt.replace(tzinfo=LOCAL_TZ)
		return dt
	except Exception:
		return None


def load_csv_points(csv_path: Path) -> List[Tuple[datetime, float]]:
	"""Return sorted (timestamp, duration_minutes) tuples for plotting."""
	points: List[Tuple[datetime, float]] = []
	with csv_path.open() as f:
		reader = csv.DictReader(f)
		for row in reader:
			ts = parse_timestamp(row.get("timestamp_local", ""))
			try:
				duration = float(row.get("duration_minutes", ""))
			except (TypeError, ValueError):
				duration = None
			if ts and duration is not None:
				points.append((ts, duration))
	return sorted(points, key=lambda p: p[0])


def weekday_medians(points: List[Tuple[datetime, float]]) -> Dict[str, float]:
	"""Compute median duration per weekday name."""
	by_day: Dict[str, List[float]] = defaultdict(list)
	for ts, duration in points:
		by_day[ts.strftime("%A")].append(duration)
	return {day: statistics.median(values) for day, values in by_day.items() if values}


def generate_graph(csv_path: Path) -> Optional[Path]:
	"""Create/overwrite a PNG for the given CSV; returns image path."""
	points = load_csv_points(csv_path)
	if not points:
		return None
	medians = weekday_medians(points)

	x_vals, y_vals = zip(*points)
	img_path = csv_path.with_suffix(".png")

	fig, ax = plt.subplots(figsize=(10, 4))
	ax.plot(x_vals, y_vals, marker="o", linewidth=2, markersize=4)
	ax.set_title(csv_path.stem.replace("-", " "))
	ax.set_ylabel("Minutes")
	ax.set_xlabel("Local time")
	ax.grid(True, linewidth=0.5, alpha=0.3)

	if medians:
		lines = [f"{day[:3]}: {val:.1f}" for day, val in sorted(medians.items())]
		stats_text = "Weekday medians\n" + "\n".join(lines)
		ax.text(
			0.99,
			0.01,
			stats_text,
			transform=ax.transAxes,
			ha="right",
			va="bottom",
			fontsize=9,
			bbox={"facecolor": "white", "alpha": 0.7, "edgecolor": "none"},
		)

	locator = mdates.AutoDateLocator(minticks=4, maxticks=10)
	formatter = mdates.ConciseDateFormatter(locator)
	ax.xaxis.set_major_locator(locator)
	ax.xaxis.set_major_formatter(formatter)
	fig.autofmt_xdate()

	fig.tight_layout()
	img_path.parent.mkdir(parents=True, exist_ok=True)
	fig.savefig(img_path, dpi=120)
	plt.close(fig)
	return img_path


def generate_all_graphs(output_dir: Path = OUTPUT_DIR) -> None:
	"""Generate/refresh PNG graphs for every per-URL CSV."""
	csv_paths: Iterable[Path] = output_dir.glob("*/*/*.csv")
	for csv_path in csv_paths:
		try:
			generate_graph(csv_path)
		except Exception as exc:
			log_message(f"Graph generation failed for {csv_path}: {exc}")


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
	local_dt = now_utc.astimezone(LOCAL_TZ)
	timestamp_local = local_dt.isoformat()
	day_of_week = local_dt.strftime("%A")

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
			try:
				result = scrape_page(page, entry.url, selectors)
			except Exception as exc:
				log_message(f"Exception while scraping '{entry.name}' ({entry.direction}) url={entry.url}: {exc}")
				raise
			result["timestamp_local"] = timestamp_local
			result["day_of_week"] = day_of_week
			result["name"] = entry.name
			duration_text = result.get("duration")
			duration_minutes = parse_duration_minutes(duration_text)
			retry_duration_text: Optional[str] = None
			if duration_minutes is None:
				log_message(
					f"Missing duration (first pass) for '{entry.name}' ({entry.direction}) url={entry.url}; "
					f"selectors={selectors.get('duration')} raw_value={duration_text}"
				)
				page.wait_for_timeout(3000)
				retry_duration_text = scrape_duration_value(page, selectors.get("duration", []))
				if retry_duration_text:
					duration_text = retry_duration_text
					duration_minutes = parse_duration_minutes(duration_text)
				if duration_minutes is None:
					card_text = route_card_text(page)
					derived_fragment = extract_duration_fragment(card_text or "") if card_text else None
					if derived_fragment:
						duration_text = derived_fragment
						duration_minutes = parse_duration_minutes(duration_text)
					if duration_minutes is None:
						all_cards = route_cards_texts(page)
						fragments: List[str] = []
						minutes_list: List[float] = []
						for card in all_cards:
							frag = extract_duration_fragment(card)
							if frag:
								val = parse_duration_minutes(frag)
								if val is not None:
									fragments.append(frag)
									minutes_list.append(val)
						if minutes_list:
							best_idx = minutes_list.index(min(minutes_list))
							duration_minutes = minutes_list[best_idx]
							duration_text = fragments[best_idx]
					if duration_minutes is None:
						snap = snapshot_text(page)
						log_snapshot(
							entry,
							f"Missing duration after retry for '{entry.name}' ({entry.direction}) url={entry.url}; "
							f"raw_first={result.get('duration')} raw_retry={retry_duration_text} "
							f"card_text_fragment={derived_fragment} snapshot='{snap}'"
						)
			result["duration_minutes"] = duration_minutes
			result.pop("duration", None)
			write_outputs_for_result(result, entry, slug)
			results.append(result)

		browser.close()

	# Per-run combined outputs and manifests removed; history lives in per-URL CSVs only.

	generate_all_graphs()

	print(f"Wrote {len(results)} rows (per-URL CSV histories only)")


if __name__ == "__main__":
	main()
