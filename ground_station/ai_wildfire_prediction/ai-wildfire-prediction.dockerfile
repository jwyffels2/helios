FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=2.2.1 \
    POETRY_NO_INTERACTION=1

RUN pip install --no-cache-dir "poetry==2.2.1"
#    && useradd -m -u 1000 -s /bin/bash appuser
#   Need to run as root to have access to USB/COM Port

# podman build -t helios-ai-wildfire-prediction -f ./ai-wildfire-prediction.dockerfile .
# podman run -it --rm -v "$PWD :/workspace" -w /workspace helios-ai-wildfire-prediction bash
