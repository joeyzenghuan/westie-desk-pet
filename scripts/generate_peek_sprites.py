#!/usr/bin/env python3
"""
Generate reference-locked pixel-art edge-peeking & calm loaf sprites for WestieDeskPet v0.2
using Azure GPT-Image-2.5 (/images/edits against westie_companion_sheet.png).

Layout (1536x1024, 3 columns x 2 rows, transparent PNG):
  (0,0) westie_peek_calm: Peeking LEFTWARD out from a vertical right border — front white paws gripping the vertical right edge of the frame, cute Westie head & ears peeking out to the left, calm curious look.
  (1,0) westie_peek_hover: Same vertical right-border peek pose, peeking slightly further out to the left with happy perked ears, tiny pink tongue smile, one paw waving gently.
  (2,0) westie_loaf_calm: Cute Westie lying down flat on its belly ("sploot/loaf" posture) facing right, chin resting calmly on front paws, peaceful eyes open watching quietly.
  (0,1) westie_sit_calm: Cute Westie sitting neatly in 3/4 view, completely calm closed-mouth gentle expression, blue collar.
  (1,1) westie_walk_calm_1: Subtle calm stroll frame 1 facing right.
  (2,1) westie_walk_calm_2: Subtle calm stroll frame 2 facing right.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from generate_assets import FLARE_DEPLOYMENT, edit_image_with_reference, load_api_key
from process_sprites import clean_and_normalize_sprite, keep_largest_component
import numpy as np
from PIL import Image


PEEK_SHEET_PROMPT = (
    "Using the exact same pixel-art West Highland White Terrier (Westie) puppy character from the reference image "
    "(same fluffy white fur pixels, pointed pink-lined ears, round black eyes, black button nose, light-blue collar, "
    "clean dark pixel outline, 32-bit retro pixel art, NO anti-aliasing blur), create a 1536x1024 transparent-background "
    "sprite sheet arranged in a strict 3 columns by 2 rows grid (6 equal cells of 512x512, NO grid lines, NO borders, NO text, "
    "generous empty transparent margin around each sprite). "
    "Row 1 Col 1 (top-left): EDGE PEEK CALM — the Westie puppy hiding behind an invisible vertical wall on the right side of this cell, "
    "only its cute head, ears, blue collar, and two little white front paws gripping the vertical right edge are visible, peeking LEFTWARD with a calm, quiet expression (no wall drawn, just the puppy cut cleanly along a straight vertical right edge). "
    "Row 1 Col 2 (top-center): EDGE PEEK HOVER — same vertical right-edge peeking pose looking LEFTWARD, leaning out a little further with perked-up ears, happy bright eyes, tiny pink tongue, and one little white front paw raised in a gentle hello wave (cut cleanly along a straight vertical right edge, no wall drawn). "
    "Row 1 Col 3 (top-right): CALM LOAF — the Westie puppy lying down low and flat on its belly facing right, chin resting peacefully on its front paws, eyes open and calm, zero motion lines. "
    "Row 2 Col 1 (bottom-left): NEAT SIT — the Westie puppy sitting neatly and quietly facing slightly left/front, calm closed-mouth expression, zero motion ticks. "
    "Row 2 Col 2 (bottom-center): corner-peek top-down/side cute Westie resting chin on window edge facing front, just head and two front paws resting on a horizontal ledge. "
    "Row 2 Col 3 (bottom-right): sleeping peacefully curled in a small compact white ball, no Zzz letters, no motion ticks."
)


def normalize_right_edge_peek(cell_img: Image.Image, canvas_size: int = 128, padding_y: int = 10) -> Image.Image:
    """
    Normalizes an edge-peeking sprite so its right edge sits flush at x = canvas_size - 1
    (ready to anchor cleanly onto the right screen edge or right window edge!).
    """
    rgba = np.array(cell_img.convert("RGBA"))
    alpha = rgba[:, :, 3]
    mask = alpha >= 45
    mask[:4, :] = False
    mask[-4:, :] = False
    mask[:, :4] = False
    mask[:, -4:] = False

    if np.any(mask):
        mask = keep_largest_component(mask)
    rgba[~mask] = [0, 0, 0, 0]

    ys, xs = np.where(mask)
    if len(xs) == 0:
        return Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    cropped = Image.fromarray(rgba[y0:y1, x0:x1], mode="RGBA")
    cw, ch = cropped.size

    target_max_h = canvas_size - padding_y * 2
    target_max_w = canvas_size - 8
    scale = min(target_max_w / cw, target_max_h / ch)
    new_w = max(1, int(round(cw * scale)))
    new_h = max(1, int(round(ch * scale)))

    resized = cropped.resize((new_w, new_h), resample=Image.Resampling.NEAREST)
    out = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    # Flush right! x = canvas_size - new_w so right edge touches x = canvas_size
    paste_x = canvas_size - new_w
    paste_y = (canvas_size - new_h) // 2
    out.paste(resized, (paste_x, paste_y), resized)
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", default=None)
    parser.add_argument("--raw-dir", default=str(Path(__file__).resolve().parent.parent / "assets_raw"))
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent / "Sources" / "WestieDeskPet" / "Resources" / "Sprites"),
    )
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)
    ref_sheet = raw_dir / "westie_companion_sheet.png"
    peek_sheet_path = raw_dir / "westie_peek_sheet.png"

    if not peek_sheet_path.exists():
        endpoint, api_key = load_api_key(args.config_ini)
        edit_image_with_reference(
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            ref_sheet,
            PEEK_SHEET_PROMPT,
            peek_sheet_path,
        )

    sheet = Image.open(peek_sheet_path).convert("RGBA")
    sw, sh = sheet.size
    cw, rh = sw // 3, sh // 2

    peek_calm = normalize_right_edge_peek(sheet.crop((0, 0, cw, rh)), canvas_size=128)
    peek_calm.save(out_dir / "westie_peek_calm.png")
    print("[SPRITE] Saved westie_peek_calm.png (flush-right 128x128)")

    peek_hover = normalize_right_edge_peek(sheet.crop((cw, 0, 2 * cw, rh)), canvas_size=128)
    peek_hover.save(out_dir / "westie_peek_hover.png")
    print("[SPRITE] Saved westie_peek_hover.png (flush-right 128x128)")

    loaf_calm, _ = clean_and_normalize_sprite(sheet.crop((2 * cw, 0, 3 * cw, rh)), canvas_size=128, bottom_align=True)
    loaf_calm.save(out_dir / "westie_loaf_calm.png")
    print("[SPRITE] Saved westie_loaf_calm.png (128x128)")

    chin_ledge, _ = clean_and_normalize_sprite(sheet.crop((cw, rh, 2 * cw, 2 * rh)), canvas_size=128, bottom_align=True)
    chin_ledge.save(out_dir / "westie_chin_ledge.png")
    print("[SPRITE] Saved westie_chin_ledge.png (128x128)")


if __name__ == "__main__":
    main()
