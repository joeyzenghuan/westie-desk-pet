#!/usr/bin/env python3
"""
Generate a crisp 4-frame quadruped pixel-art walk/trot cycle for WestieDeskPet
using Azure GPT-Image-2.5 (/images/edits locked to westie_idle.png).

Layout (1024x1024, 2 columns x 2 rows, transparent PNG, facing RIGHT):
  (0,0) westie_walk_1 : Wide stride A (front-right leg extended forward, front-left back, hind legs opposite)
  (1,0) westie_walk_2 : Passing mid-step A (legs crossing under belly, one front paw lifted cleanly off ground)
  (0,1) westie_walk_3 : Wide stride B (front-left leg extended forward, front-right back, hind legs opposite)
  (1,1) westie_walk_4 : Passing mid-step B (legs crossing under belly, opposite front paw lifted cleanly off ground)
"""
from __future__ import annotations

import argparse
from pathlib import Path

from generate_assets import FLARE_DEPLOYMENT, edit_image_with_reference, load_api_key
from process_sprites import clean_and_normalize_sprite
from PIL import Image


WALK_CYCLE_PROMPT = (
    "Using the EXACT SAME pixel-art West Highland White Terrier (Westie) puppy character from the reference image "
    "(identical fluffy white pixel fur, strictly TWO symmetrical pointed pink-lined ears, round black eyes, black button nose, "
    "light-blue collar with tiny silver tag, perky short white tail, clean dark pixel outline, 32-bit retro pixel art, NO anti-aliasing blur), "
    "create a 1024x1024 transparent-background 4-frame SIDE-PROFILE WALK CYCLE sprite sheet arranged in a strict 2 columns by 2 rows grid "
    "(4 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin around each sprite). "
    "ALL 4 frames MUST face strictly RIGHT in clean side-profile with IDENTICAL head size, torso length, and ground baseline, "
    "and CLEAR dark pixel outlines separating all four legs so the legs stepping forward and backward are unmistakably readable even at small 66px size! "
    "Keep the puppy's belly fur slightly higher off the ground so the 4 short white legs and paws are clearly visible against transparent background: "
    "Row 1 Col 1 (top-left): WALK FRAME 1 (WIDE STRIDE A) — front-right leg reaching clearly FORWARD, front-left leg angled clearly BACKWARD, "
    "back-left leg reaching clearly FORWARD under belly, back-right leg pushing clearly BACKWARD behind rump (clear scissors gap between legs!). "
    "Row 1 Col 2 (top-right): WALK FRAME 2 (PASSING A) — front-right leg planted straight down supporting weight, front-left paw lifted bent forward off the ground, "
    "hind legs passing close together underneath, tail wagging slightly up. "
    "Row 2 Col 1 (bottom-left): WALK FRAME 3 (WIDE STRIDE B, OPPOSITE) — front-left leg reaching clearly FORWARD, front-right leg angled clearly BACKWARD, "
    "back-right leg reaching clearly FORWARD under belly, back-left leg pushing clearly BACKWARD behind rump (clear opposite scissors gap!). "
    "Row 2 Col 2 (bottom-right): WALK FRAME 4 (PASSING B) — front-left leg planted straight down supporting weight, front-right paw lifted bent forward off the ground, "
    "hind legs passing close together underneath, tail slightly lower."
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", default=None)
    parser.add_argument("--raw-dir", default=str(Path(__file__).resolve().parent.parent / "assets_raw"))
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent / "Sources" / "WestieDeskPet" / "Resources" / "Sprites"),
    )
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)
    ref_idle = out_dir / "westie_idle.png"
    sheet_path = raw_dir / "westie_walk_cycle_4f_sheet.png"

    if args.force and sheet_path.exists():
        sheet_path.unlink()

    if not sheet_path.exists():
        endpoint, api_key = load_api_key(args.config_ini)
        edit_image_with_reference(
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            ref_idle,
            WALK_CYCLE_PROMPT,
            sheet_path,
            size="1024x1024",
            quality="high",
        )

    sheet = Image.open(sheet_path).convert("RGBA")
    sw, sh = sheet.size
    cw, rh = sw // 2, sh // 2

    cells = [
        (0, 0, "westie_walk_1"),
        (1, 0, "westie_walk_2"),
        (0, 1, "westie_walk_3"),
        (1, 1, "westie_walk_4"),
    ]
    ref_scale: float | None = None
    for col, row, name in cells:
        cell = sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        sprite, used_scale = clean_and_normalize_sprite(
            cell,
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=ref_scale,
        )
        if ref_scale is None:
            ref_scale = used_scale
        sprite.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (128x128, scale={used_scale:.3f})")


if __name__ == "__main__":
    main()
