# Minimal image with Playwright + Chromium preinstalled
FROM mcr.microsoft.com/playwright/python:v1.45.0-jammy

WORKDIR /app

# System dependencies for Chromium (most already present in the base image; kept explicit for clarity)
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		libnss3 libatk1.0-0 libx11-xcb1 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
		libasound2 libxshmfence1 libgtk-3-0 libpango-1.0-0 libcups2 libdrm2 tzdata \
	&& rm -rf /var/lib/apt/lists/*

# Python deps + browser binaries
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
	&& python -m playwright install chromium

# Application code
COPY gmap.py ./
COPY run.sh ./

RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]
