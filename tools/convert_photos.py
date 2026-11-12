#!/usr/bin/env python3
"""Convert photos into Kindle photo-frame images.

For each input image this script:

  1. Applies EXIF orientation.
  2. Converts to 8-bit grayscale.
  3. If the photo is landscape (wider than it is tall), rotates it 90 degrees
     so it fills a portrait Kindle screen. By default the rotation is
     counter-clockwise: after that, turning the Kindle 90 degrees clockwise
     (so it lies to the right) shows the photo upright. Use --rotate cw if
     your photos end up upside-down or needing the opposite turn.
  4. Center-crops to the device aspect ratio (full-bleed, no letterboxing)
     and resizes to the exact device resolution.
  5. Saves a sequential JPEG (0001.jpg, 0002.jpg, ...) and writes
     manifest.csv plus landscape.txt for the KUAL orientation filter.

Requirements: Python 3 with Pillow  (`python3 -m pip install pillow`)

Examples:

  python3 tools/convert_photos.py --device pw1 -i ./incoming -o ./photoframe
  python3 tools/convert_photos.py --device oasis -i ./incoming -o ./photoframe
  python3 tools/convert_photos.py --width 1072 --height 1448 -i ./incoming -o ./out

Then copy photoframe/ (images/, settings.sh, landscape.txt, manifest.csv)
to the Kindle USB root, next to documents/.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.stderr.write(
        "This script needs Pillow. Install it with:\n"
        "  python3 -m pip install pillow\n"
    )
    sys.exit(1)

DEVICES = {
    "pw1": (758, 1024),      # Kindle Paperwhite 1st gen
    "oasis": (1072, 1448),   # Kindle Oasis 1st gen
}

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp", ".bmp"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convert photos to grayscale, full-bleed Kindle frames."
    )
    p.add_argument("-i", "--input", required=True, type=Path,
                   help="Folder of source photos (searched recursively).")
    p.add_argument("-o", "--output", required=True, type=Path,
                   help="Output folder (images/ , manifest.csv, landscape.txt).")
    p.add_argument("--device", choices=sorted(DEVICES),
                   help="Resolution preset: pw1 (758x1024) or oasis (1072x1448).")
    p.add_argument("--width", type=int, help="Custom width in pixels.")
    p.add_argument("--height", type=int, help="Custom height in pixels.")
    p.add_argument("--rotate", choices=("ccw", "cw"), default="ccw",
                   help="Rotation for landscape photos (default: ccw).")
    p.add_argument("--quality", type=int, default=90,
                   help="JPEG quality 1-95 (default: 90).")
    p.add_argument("--start", type=int, default=1,
                   help="First output number (default: 1 -> 0001.jpg).")
    p.add_argument("--dry-run", action="store_true",
                   help="List what would be converted, write nothing.")
    return p.parse_args()


def resolve_size(args: argparse.Namespace) -> tuple[int, int]:
    if args.width and args.height:
        if args.width < 1 or args.height < 1:
            sys.exit("width and height must be positive")
        return args.width, args.height
    if args.device:
        return DEVICES[args.device]
    sys.exit("Choose --device pw1 or --device oasis, or pass --width and --height.")


def list_sources(folder: Path) -> list[Path]:
    files = [
        p for p in sorted(folder.rglob("*"))
        if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
        and not p.name.startswith("._")
        and not p.name.startswith(".")
    ]
    return files


def center_crop_to_aspect(im: Image.Image, tw: int, th: int) -> Image.Image:
    """Crop centered to the target aspect ratio, then resize exactly to tw x th."""
    w, h = im.size
    target_ratio = tw / th
    ratio = w / h
    if ratio > target_ratio:
        new_w = max(1, int(round(h * target_ratio)))
        left = (w - new_w) // 2
        im = im.crop((left, 0, left + new_w, h))
    elif ratio < target_ratio:
        new_h = max(1, int(round(w / target_ratio)))
        top = (h - new_h) // 2
        im = im.crop((0, top, w, top + new_h))
    if im.size != (tw, th):
        im = im.resize((tw, th), Image.Resampling.LANCZOS)
    return im


def convert_one(src: Path, size: tuple[int, int], rotate: str) -> tuple[Image.Image, bool]:
    with Image.open(src) as raw:
        im = ImageOps.exif_transpose(raw)
        im = im.convert("L")
        # Work on a copy; the context manager closes the original file.
        im = im.copy()
    landscape = im.width > im.height
    if landscape:
        # PIL ROTATE_90 is 90 degrees counter-clockwise; ROTATE_270 is clockwise.
        im = im.transpose(
            Image.Transpose.ROTATE_90 if rotate == "ccw" else Image.Transpose.ROTATE_270
        )
    im = center_crop_to_aspect(im, size[0], size[1])
    return im, landscape


def main() -> int:
    args = parse_args()
    size = resolve_size(args)
    if not args.input.is_dir():
        sys.stderr.write(f"Input folder not found: {args.input}\n")
        return 1
    sources = list_sources(args.input)
    if not sources:
        sys.stderr.write(f"No photos found in {args.input}\n")
        return 1

    out_root = args.output
    img_dir = out_root / "images"
    if not args.dry_run:
        img_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, str]] = []
    n = args.start
    landscapes = 0
    portraits = 0
    for src in sources:
        name = f"{n:04d}.jpg"
        try:
            if args.dry_run:
                with Image.open(src) as raw:
                    im = ImageOps.exif_transpose(raw)
                    landscape = im.width > im.height
            else:
                im, landscape = convert_one(src, size, args.rotate)
                dest = img_dir / name
                im.save(dest, format="JPEG", quality=args.quality, optimize=True)
            if landscape:
                landscapes += 1
                rotated = "yes"
            else:
                portraits += 1
                rotated = "no"
            rows.append({
                "kindle_file": name,
                "original_path": str(src),
                "rotated_landscape": rotated,
            })
            flag = "landscape" if landscape else "portrait"
            print(f"{name}  {flag}  {src}")
            n += 1
        except Exception as exc:  # noqa: BLE001 - keep going through a mixed folder
            sys.stderr.write(f"SKIP {src}: {exc}\n")

    if args.dry_run:
        print(
            f"dry-run: {len(rows)} photos "
            f"(portrait {portraits}, landscape {landscapes}) -> {size[0]}x{size[1]}"
        )
        return 0

    manifest = out_root / "manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(
            fh, fieldnames=["kindle_file", "original_path", "rotated_landscape"]
        )
        w.writeheader()
        w.writerows(rows)

    landscape_list = out_root / "landscape.txt"
    landscape_list.write_text(
        "".join(r["kindle_file"] + "\n" for r in rows if r["rotated_landscape"] == "yes"),
        encoding="utf-8",
    )
    print(
        f"Wrote {len(rows)} images to {img_dir} ({size[0]}x{size[1]}, grayscale JPEG), "
        f"portrait {portraits}, landscape (rotated) {landscapes}."
    )
    print(f"manifest: {manifest}")
    print(f"landscape list: {landscape_list}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
