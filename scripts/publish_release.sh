#!/bin/sh
# Uploads the built files in ./out to the "latest" release on GitHub, replacing files of the same name,
# so the public download links stay the same whichever service did the build.
# Needs GITHUB_TOKEN (a token allowed to write this repository's contents). Without it, nothing is published.
set -e
REPO="FarisSoze/baytna"
API="https://api.github.com/repos/$REPO"
if [ -z "$GITHUB_TOKEN" ]; then echo "GITHUB_TOKEN is not set: the files stay on the build service only"; exit 0; fi
auth() { curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

auth "$API/releases/tags/latest" > release.json
RID=$(python3 -c "import json;print(json.load(open('release.json'))['id'])")
for f in out/*.apk out/*.ipa; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  old=$(python3 -c "import json,sys;print(next((str(a['id']) for a in json.load(open('release.json'))['assets'] if a['name']==sys.argv[1]),''))" "$name")
  if [ -n "$old" ]; then auth -X DELETE "$API/releases/assets/$old" > /dev/null; fi
  auth -X POST -H "Content-Type: application/octet-stream" --data-binary "@$f" \
    "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=$name" > /dev/null
  echo "published $name"
done
rm -f release.json
