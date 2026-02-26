#!/usr/bin/env bash
set -e
echo "Gateway:"; curl -sS http://localhost:8080 || true
echo "Adapter health:"; curl -sS http://localhost:3000/health || true
echo "Agent health:"; curl -sS http://localhost:8081/health || true
