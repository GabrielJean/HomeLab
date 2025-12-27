# Minimal image with Playwright + Chromium preinstalled
FROM mcr.microsoft.com/playwright/python:v1.45.0-jammy

WORKDIR /app

# Copy only the script and runner; dependencies are already in the base image
COPY gmap.py ./
COPY run.sh ./

RUN chmod +x run.sh

ENTRYPOINT ["./run.sh"]
