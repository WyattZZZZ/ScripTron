#!/usr/bin/env python3
from pathlib import Path
from PIL import Image


TARGET_DIR = Path.home() / "Desktop" / "test001_hider"


def rotate_pngs_clockwise_90(root: Path) -> int:
    if not root.exists():
        raise FileNotFoundError(f"Folder not found: {root}")

    png_files = sorted(root.rglob("*.png"))
    for path in png_files:
        with Image.open(path) as image:
            rotated = image.rotate(-90, expand=True)
            rotated.save(path)
        print(f"rotated: {path}")

    return len(png_files)


if __name__ == "__main__":
    count = rotate_pngs_clockwise_90(TARGET_DIR)
    print(f"Done. Rotated {count} PNG file(s).")
