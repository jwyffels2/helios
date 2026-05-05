#!/usr/bin/env sh
set -eu
cd ./ground_station
poetry install
poetry run python listen.py
