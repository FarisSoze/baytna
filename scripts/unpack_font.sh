#!/bin/sh
# Unpacks the licensed Thmanyah typeface into designs/fonts from the encrypted bundle, when the key is available.
# The files themselves are never committed; the build simply falls back to the old font without them.
set -e
mkdir -p designs/fonts
if [ -z "$FONT_KEY" ]; then echo "FONT_KEY is not set: building with the fallback font"; exit 0; fi
openssl enc -d -aes-256-cbc -pbkdf2 -in ci/thmanyah.enc -pass env:FONT_KEY | tar -xz -C designs/fonts
ls designs/fonts
