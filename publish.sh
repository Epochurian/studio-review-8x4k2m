#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

SYNC_PHYSICAL=true
COMMIT_MSG="Update review round ($(date '+%Y-%m-%d %H:%M'))"

for arg in "$@"; do
  case "$arg" in
    --no-sync) SYNC_PHYSICAL=false ;;
    *) COMMIT_MSG="$arg" ;;
  esac
done

if [ "$SYNC_PHYSICAL" = true ] && [ -d "$WORKSPACE_ROOT/Physical Media" ]; then
  echo "Syncing Physical Media..."
  mkdir -p "$SCRIPT_DIR/physical-media"
  rsync -a --delete \
    --exclude='.DS_Store' \
    "$WORKSPACE_ROOT/Physical Media/" "$SCRIPT_DIR/physical-media/"
fi

# Rebuild sections.json from known galleries + any extra folders in review/
python3 - <<'PY'
import json, os, datetime

root = os.getcwd()
sections = []

if os.path.exists(os.path.join(root, "physical-media/gallery.html")):
    sections.append({
        "title": "Posters & Flyers",
        "tag": "Print & Visual",
        "description": "Poster concepts, museum-style layouts, and print renders (HTML & PDF).",
        "href": "physical-media/gallery.html"
    })

if os.path.exists(os.path.join(root, "physical-media/leaflets/leaflet-gallery.html")):
    sections.append({
        "title": "Leaflets",
        "tag": "Print & Fold",
        "description": "Tri-fold, gatefold, and z-fold leaflet iterations.",
        "href": "physical-media/leaflets/leaflet-gallery.html"
    })

skip = {"physical-media", ".git"}
for name in sorted(os.listdir(root)):
    if name in skip or name.startswith("."):
        continue
    full = os.path.join(root, name)
    if not os.path.isdir(full):
        continue
    target = None
    for candidate in ("index.html", "gallery.html"):
        if os.path.exists(os.path.join(full, candidate)):
            target = f"{name}/{candidate}"
            break
    if not target:
        htmls = sorted(f for f in os.listdir(full) if f.endswith(".html"))
        if htmls:
            target = f"{name}/{htmls[0]}"
    if target:
        pretty = name.replace("-", " ").replace("_", " ").title()
        sections.append({
            "title": pretty,
            "tag": "Area",
            "description": f"Review files in {name}/",
            "href": target
        })

payload = {
    "updated_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "sections": sections
}
with open(os.path.join(root, "sections.json"), "w") as f:
    json.dump(payload, f, indent=2)
PY

git add -A
if git diff --cached --quiet; then
  echo "No changes to publish."
else
  git commit -m "$COMMIT_MSG"
  git push -u origin main
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  OWNER_LC="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
  echo ""
  echo "Live review URL: https://${OWNER_LC}.github.io/${REPO}/"
fi
