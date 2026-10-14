#!/usr/bin/env bash
# Remove local Lingrove production installations and reset their TCC permissions.
# Useful when stale copies cause confusion about which build is running.
# Usage: bash scripts/clean_local.sh
set -euo pipefail

BUNDLE_ID="io.ichthyoplanktonzyh.lingrove"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Lingrove Local Cleanup ==="

# --- 1. Stop only processes belonging to the production bundle identity ---
echo ""
echo "Stopping Lingrove production processes..."
while IFS= read -r pid; do
    executable=$(ps -ww -p "$pid" -o comm= 2>/dev/null || true)
    [[ "$executable" == *.app/Contents/MacOS/* ]] || continue
    app_path="${executable%/Contents/MacOS/*}"
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)
    [[ "$bid" != "$BUNDLE_ID" ]] || kill "$pid"
done < <(pgrep -x "Lingrove" || true)

# --- 2. Reset TCC permissions ---
echo ""
echo "Resetting TCC permissions for $BUNDLE_ID..."
tccutil reset All "$BUNDLE_ID" && echo "  TCC permissions reset." || echo "  Failed to reset TCC (may need sudo)."

# --- 3. Find and remove Lingrove app bundles ---
echo ""
echo "Searching for Lingrove app bundles..."

SEARCH_PATHS=(
    "$HOME/Applications"
    "/Applications"
    "$HOME/Desktop"
    "$HOME/Downloads"
    "/tmp"
    "$REPO_ROOT/build"
)

found=0
for dir in "${SEARCH_PATHS[@]}"; do
    if [ ! -d "$dir" ]; then
        continue
    fi
    while IFS= read -r app; do
        # A matching filename is insufficient; every removal also checks the product identity.
        plist="$app/Contents/Info.plist"
        if [ -f "$plist" ]; then
            bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true)
            if [ "$bid" = "$BUNDLE_ID" ]; then
                echo "  Removing: $app"
                rm -rf "$app"
                found=$((found + 1))
            fi
        fi
    done < <(find "$dir" -name "Lingrove.app" -type d -prune 2>/dev/null)
done

if [ "$found" -eq 0 ]; then
    echo "  No Lingrove app bundles found."
else
    echo "  Removed $found app bundle(s)."
fi

# --- 4. Eject any mounted Lingrove DMG volumes ---
echo ""
echo "Ejecting mounted Lingrove volumes..."
while IFS= read -r vol; do
    [ -z "$vol" ] && continue
    hdiutil detach "$vol" -quiet 2>/dev/null && echo "  Ejected $vol" || true
done < <(ls /Volumes/ 2>/dev/null | grep -i "^Lingrove" | sed 's|^|/Volumes/|')

# --- 5. Clean up caches and saved state ---
echo ""
echo "Cleaning caches and saved state..."
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" 2>/dev/null && echo "  Removed caches." || true
rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null && echo "  Removed saved state." || true

echo ""
echo "=== Done. You have a clean slate. ==="
