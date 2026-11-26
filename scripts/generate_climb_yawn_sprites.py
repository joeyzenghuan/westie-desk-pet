#!/usr/bin/env python3
"""
Generate 6 reference-locked pixel-art transition frames for WestieDeskPet v0.4.2
using Azure GPT-Image-2.5 (/images/edits against westie_companion_sheet.png):

Layout (1536x1024, 3 columns x 2 rows, transparent PNG):
  (0,0) westie_top_peek_center : Peeking over horizontal top edge, head + two white paws on bottom ledge, looking straight ahead.
  (1,0) westie_top_peek_left   : Exact same top-edge head + paws pose, head gently turned looking LEFT.
  (2,0) westie_top_peek_right  : Exact same top-edge head + paws pose, head gently turned looking RIGHT.
  (0,1) westie_climb_up        : Pulling body up onto the horizontal ledge — front paws planted, chest/back lifting into standing 3/4 view facing right.
  (1,1) westie_yawn            : Tired Westie facing right sitting/crouching with squinted sleepy eyes and wide cute pink yawn, ears relaxed.
  (2,1) westie_drowsy          : Westie lying flat on belly facing right (exact same loaf silhouette as westie_sleep), heavy half-closed sleepy eyelids, chin lowering onto front paws.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from generate_assets import FLARE_DEPLOYMENT, edit_image_with_reference, load_api_key
from process_sprites import clean_and_normalize_sprite
from PIL import Image


CLIMB_YAWN_SHEET_PROMPT = (
    "Using the EXACT SAME pixel-art West Highland White Terrier (Westie) puppy character from the reference image "
    "(identical fluffy white pixel fur, pointed pink-lined ears, round black eyes, black button nose, light-blue collar with tiny silver tag, "
    "clean dark pixel outline, 32-bit retro pixel art, NO anti-aliasing blur), create a 1536x1024 transparent-background "
    "sprite sheet arranged in a strict 3 columns by 2 rows grid (6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO Zzz letters, "
    "generous empty transparent margin around each sprite). Keep the puppy's HEAD SIZE consistent across all 6 cells. "
    "Row 1 Col 1 (top-left): TOP PEEK CENTER — only the Westie puppy's cute head, pointed ears, blue collar rim, and two little white front paws resting cleanly on a flat invisible horizontal bottom line, looking straight forward curiously (no wall or ledge drawn). "
    "Row 1 Col 2 (top-center): TOP PEEK LEFT — the EXACT same top-edge peeking head and two front paws in the exact same position and scale as Row 1 Col 1, but the puppy's head is gently turned and glancing LEFT curiously. "
    "Row 1 Col 3 (top-right): TOP PEEK RIGHT — the EXACT same top-edge peeking head and two front paws in the exact same position and scale as Row 1 Col 1, but the puppy's head is gently turned and glancing RIGHT curiously. "
    "Row 2 Col 1 (bottom-left): CLIMBING UP OVER LEDGE — mid-climb transition pose facing slightly right: the Westie puppy pulling its whole body up onto the flat horizontal floor, front paws planted forward, torso and hind paws scrambling up into a standing posture, lively cute expression. "
    "Row 2 Col 2 (bottom-center): BIG CUTE YAWN — the full-body Westie puppy in side-3/4 view facing RIGHT (same scale as standing idle), sitting/crouching slightly with eyes tightly squinted in a sleepy happy curve, mouth open wide showing a cute little pink yawn, ears relaxed slightly back. "
    "Row 2 Col 3 (bottom-right): DROWSY HALF-ASLEEP LOAF — the full-body Westie puppy lying low and flat on its belly facing RIGHT (matching the exact compact loaf silhouette of the sleeping pose), chin lowering onto its front paws, eyelids heavy and half-closed just before falling asleep."
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
    ref_sheet = raw_dir / "westie_companion_sheet.png"
    sheet_path = raw_dir / "westie_climb_yawn_sheet.png"

    if args.force and sheet_path.exists():
        sheet_path.unlink()

    if not sheet_path.exists():
        endpoint, api_key = load_api_key(args.config_ini)
        edit_image_with_reference(
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            ref_sheet,
            CLIMB_YAWN_SHEET_PROMPT,
            sheet_path,
        )

    sheet = Image.open(sheet_path).convert("RGBA")
    sw, sh = sheet.size
    cw, rh = sw // 3, sh // 2

    # Top-row 3 peek frames lock to the EXACT same scale so center <-> left <-> right has ZERO scale jitter!
    top_row = [
        (0, 0, "westie_top_peek_center"),
        (1, 0, "westie_top_peek_left"),
        (2, 0, "westie_top_peek_right"),
    ]
    peek_ref_scale: float | None = None
    for col, row, name in top_row:
        cell = sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        sprite, used_scale = clean_and_normalize_sprite(
            cell,
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=peek_ref_scale,
        )
        if peek_ref_scale is None:
            peek_ref_scale = used_scale
        sprite.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (128x128, scale={used_scale:.3f})")

    # Bottom-row 3 full-body transition frames (climb_up, yawn, drowsy)
    bottom_row = [
        (0, 1, "westie_climb_up"),
        (1, 1, "westie_yawn"),
        (2, 1, "westie_drowsy"),
    ]
    for col, row, name in bottom_row:
        cell = sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        sprite, used_scale = clean_and_normalize_sprite(
            cell,
            canvas_size=128,
            bottom_align=True,
            padding=8,
        )
        sprite.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (128x128, scale={used_scale:.3f})")


if __name__ == "__main__":
    main()
