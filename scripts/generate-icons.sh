#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_SVG="$ROOT_DIR/docs/assets/agentbar-icon.svg"
OUTPUT_DIR="$ROOT_DIR/build/icons"
ICON_NAME="AgentBar"

usage() {
  cat <<'EOF'
Usage: generate-icons.sh [options]

Options:
  --input <path>        Source SVG path (default: docs/assets/agentbar-icon.svg)
  --output-dir <path>   Output directory (default: build/icons)
  --name <name>         Base icon name (default: AgentBar)
  -h, --help            Show this help

Outputs:
  <output-dir>/<name>-1024.png
  <output-dir>/png/<name>-{16,32,64,128,256,512,1024}.png
  <output-dir>/<name>.iconset/*.png
  <output-dir>/<name>.icns
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)
        INPUT_SVG="$2"
        shift 2
        ;;
      --output-dir)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --name)
        ICON_NAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

require_tools() {
  command -v sips >/dev/null 2>&1 || {
    echo "Missing required tool: sips" >&2
    exit 1
  }

  if ! command -v iconutil >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    echo "Missing icns generator: install iconutil (macOS) or python3 + Pillow." >&2
    exit 1
  fi
}

render_with_rsvg() {
  command -v rsvg-convert >/dev/null 2>&1 || return 1
  rsvg-convert -w 1024 -h 1024 "$INPUT_SVG" -o "$MASTER_PNG" >/dev/null 2>&1
}

render_with_inkscape() {
  command -v inkscape >/dev/null 2>&1 || return 1
  inkscape "$INPUT_SVG" \
    --export-type=png \
    --export-filename="$MASTER_PNG" \
    --export-width=1024 \
    --export-height=1024 >/dev/null 2>&1
}

render_with_magick() {
  command -v magick >/dev/null 2>&1 || return 1
  magick -background none "$INPUT_SVG" -resize 1024x1024 -depth 8 "PNG32:$MASTER_PNG" >/dev/null 2>&1
}

render_with_sips() {
  sips -s format png "$INPUT_SVG" --out "$MASTER_PNG" >/dev/null 2>&1 || return 1
  sips -z 1024 1024 "$MASTER_PNG" --out "$MASTER_PNG" >/dev/null 2>&1
}

render_with_qlmanage() {
  command -v qlmanage >/dev/null 2>&1 || return 1

  local tmp_dir generated
  tmp_dir="$(mktemp -d)"
  qlmanage -t -s 1024 -o "$tmp_dir" "$INPUT_SVG" >/dev/null 2>&1 || {
    rm -rf "$tmp_dir"
    return 1
  }

  generated="$(find "$tmp_dir" -maxdepth 1 -type f -name '*.png' | head -n 1 || true)"
  if [[ -z "$generated" ]]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  cp "$generated" "$MASTER_PNG"
  rm -rf "$tmp_dir"
}

render_master_png() {
  if render_with_rsvg; then
    RENDERER="rsvg-convert"
    return 0
  fi
  if render_with_inkscape; then
    RENDERER="inkscape"
    return 0
  fi
  if render_with_magick; then
    RENDERER="magick"
    return 0
  fi
  if render_with_sips; then
    RENDERER="sips"
    return 0
  fi
  if render_with_qlmanage; then
    RENDERER="qlmanage"
    return 0
  fi
  return 1
}

resize_png() {
  local size="$1"
  local out="$2"
  sips -z "$size" "$size" "$MASTER_PNG" --out "$out" >/dev/null
}

build_png_set() {
  mkdir -p "$PNG_DIR"
  local size
  for size in 16 32 64 128 256 512 1024; do
    resize_png "$size" "$PNG_DIR/${ICON_NAME}-${size}.png"
  done
}

normalize_1024_bit_depth() {
  local png_1024="$PNG_DIR/${ICON_NAME}-1024.png"
  local png_512="$PNG_DIR/${ICON_NAME}-512.png"
  local tmp_png="${png_1024}.tmp"

  if file "$png_1024" | grep -q "16-bit/color"; then
    if command -v magick >/dev/null 2>&1; then
      magick "$png_1024" -depth 8 "PNG32:$tmp_png" >/dev/null 2>&1 || true
      if [[ -f "$tmp_png" ]]; then
        mv "$tmp_png" "$png_1024"
      else
        sips -z 1024 1024 "$png_512" --out "$png_1024" >/dev/null
      fi
    else
      sips -z 1024 1024 "$png_512" --out "$png_1024" >/dev/null
    fi
  fi

  cp "$png_1024" "$MASTER_PNG"
}

build_iconset() {
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  cp "$PNG_DIR/${ICON_NAME}-16.png" "$ICONSET_DIR/icon_16x16.png"
  cp "$PNG_DIR/${ICON_NAME}-32.png" "$ICONSET_DIR/icon_16x16@2x.png"
  cp "$PNG_DIR/${ICON_NAME}-32.png" "$ICONSET_DIR/icon_32x32.png"
  cp "$PNG_DIR/${ICON_NAME}-64.png" "$ICONSET_DIR/icon_32x32@2x.png"
  cp "$PNG_DIR/${ICON_NAME}-128.png" "$ICONSET_DIR/icon_128x128.png"
  cp "$PNG_DIR/${ICON_NAME}-256.png" "$ICONSET_DIR/icon_128x128@2x.png"
  cp "$PNG_DIR/${ICON_NAME}-256.png" "$ICONSET_DIR/icon_256x256.png"
  cp "$PNG_DIR/${ICON_NAME}-512.png" "$ICONSET_DIR/icon_256x256@2x.png"
  cp "$PNG_DIR/${ICON_NAME}-512.png" "$ICONSET_DIR/icon_512x512.png"
  cp "$PNG_DIR/${ICON_NAME}-1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
}

generate_icns_with_iconutil() {
  command -v iconutil >/dev/null 2>&1 || return 1
  iconutil --convert icns --output "$ICNS_PATH" "$ICONSET_DIR" >/dev/null 2>&1
}

generate_icns_with_pillow() {
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$PNG_DIR/${ICON_NAME}-1024.png" "$ICNS_PATH" <<'PY'
import sys

try:
    from PIL import Image
except Exception as exc:  # pragma: no cover
    print(f"Pillow unavailable: {exc}", file=sys.stderr)
    raise SystemExit(1)

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
img.save(
    dst,
    format="ICNS",
    sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)],
)
PY
}

generate_icns() {
  if generate_icns_with_iconutil; then
    ICNS_GENERATOR="iconutil"
    return 0
  fi

  if generate_icns_with_pillow; then
    ICNS_GENERATOR="python-pillow"
    return 0
  fi

  return 1
}

main() {
  parse_args "$@"
  require_tools

  if [[ ! -f "$INPUT_SVG" ]]; then
    echo "Input SVG not found: $INPUT_SVG" >&2
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"
  MASTER_PNG="$OUTPUT_DIR/${ICON_NAME}-1024.png"
  PNG_DIR="$OUTPUT_DIR/png"
  ICONSET_DIR="$OUTPUT_DIR/${ICON_NAME}.iconset"
  ICNS_PATH="$OUTPUT_DIR/${ICON_NAME}.icns"
  RENDERER=""

  render_master_png || {
    echo "Failed to render SVG to PNG. Install one of: rsvg-convert, inkscape, magick, or use macOS qlmanage/sips." >&2
    exit 1
  }

  # Normalize to exact 1024x1024.
  sips -z 1024 1024 "$MASTER_PNG" --out "$MASTER_PNG" >/dev/null

  build_png_set
  normalize_1024_bit_depth
  build_iconset
  generate_icns || {
    echo "Failed to generate icns. iconutil rejected the iconset and Pillow fallback is unavailable." >&2
    exit 1
  }

  echo "Renderer: $RENDERER"
  echo "ICNS generator: $ICNS_GENERATOR"
  echo "Master PNG: $MASTER_PNG"
  echo "PNG set dir: $PNG_DIR"
  echo "Iconset dir: $ICONSET_DIR"
  echo "ICNS: $ICNS_PATH"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
