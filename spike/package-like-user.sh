#!/bin/bash
# Zips the app the way a download would arrive, stamps the quarantine flag Safari adds,
# and puts it in ~/Downloads for Derek to double-click.
set -euo pipefail
cd "$(dirname "$0")"
ZIP="$HOME/Downloads/SlinkySpike-test.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/SlinkySpike.app "$ZIP"
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$ZIP"
xattr -l "$ZIP"
echo "Ready: $ZIP"
