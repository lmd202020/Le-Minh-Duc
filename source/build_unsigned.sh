
#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

PROJECT="$ROOT/ThreeOneOSFive.xcodeproj"
SCHEME="OGIOS"
CONFIGURATION="Release"

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/OGIOS.xcarchive"
PAYLOAD="$BUILD_DIR/Payload"
IPA="$BUILD_DIR/OGIOS-unsigned.ipa"
LOG_DIR="$BUILD_DIR/logs"

echo "======================================"
echo "          OGIOS BUILD SYSTEM"
echo "======================================"

# Kiểm tra môi trường
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: Không tìm thấy xcodebuild"
    exit 1
fi

if [ ! -d "$PROJECT" ]; then
    echo "ERROR: Không tìm thấy project"
    exit 1
fi

# Dọn build cũ
rm -rf "$BUILD_DIR"

mkdir -p "$BUILD_DIR" "$LOG_DIR"

# Resolve dependencies
echo "[1/4] Resolving Swift Packages..."

xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT" \
    -scheme "$SCHEME" 2>&1 | tee "$LOG_DIR/resolve-packages.log"

# Build archive
echo "[2/4] Building unsigned archive..."

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    archive 2>&1 | tee "$LOG_DIR/archive-build.log"

# Locate app
echo "[3/4] Locating application..."

APP_PATH="$ARCHIVE/Products/Applications"

APP=""

if [ -d "$APP_PATH" ]; then
    APP="$(find "$APP_PATH" -maxdepth 1 -type d -name "*.app" -print -quit)"
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "ERROR: Không tìm thấy ứng dụng trong archive"
    find "$ARCHIVE" -maxdepth 6 -print
    exit 1
fi

echo "Application: $APP"

# Package IPA
echo "[4/4] Packaging IPA..."

rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"

cp -R "$APP" "$PAYLOAD/"

(
    cd "$BUILD_DIR"

    /usr/bin/ditto \
        -c \
        -k \
        --sequesterRsrc \
        --keepParent \
        Payload \
        "$IPA"
)

rm -rf "$PAYLOAD"

# Verify output
if [ ! -s "$IPA" ]; then
    echo "ERROR: Không tạo được IPA"
    exit 1
fi

echo ""
echo "======================================"
echo "          BUILD SUCCESS"
echo "======================================"
echo "IPA: $IPA"

ls -lh "$IPA"
