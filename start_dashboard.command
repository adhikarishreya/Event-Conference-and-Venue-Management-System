#!/bin/bash
cd "$(dirname "$0")"
echo "Starting EventOps Web Dashboard on http://localhost:8502 ..."
python3 dashboard.py
