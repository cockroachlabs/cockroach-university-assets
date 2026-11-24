#!/bin/bash
# Start the Talc app on port 8000. --reload restarts it whenever you save a file.
cd "$(dirname "$0")"
[ -f .env ] && source .env
source .venv/bin/activate
exec uvicorn talc.main:app --host 0.0.0.0 --port 8000 --reload
