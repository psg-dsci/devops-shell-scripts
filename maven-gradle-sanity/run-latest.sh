#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/divyamohan1993/devops-shell-scripts/refs/heads/main/maven-gradle-sanity/autoconfig.sh"

cd ~/

# cache-bust via timestamp param + no-cache headers
wget -O autoconfig.sh --header="Cache-Control: no-cache" "${URL}?nocache=$(date +%s)"
chmod 755 autoconfig.sh

# VERBOSE=1 for xtrace; otherwise quiet
./autoconfig.sh --debug