#!/usr/bin/env python3
"""
Generate pixel-art dried fish snack (小鱼干) + 2-frame chewing/eating animations for BOTH
Westie (chewing bone) and Golden Shaded Cat (chewing dried fish) via Azure GPT-Image-2.5.

Layout (1536x1024, 3 columns x 2 rows, transparent PNG):
  (0,0) dried_fish_treat : Cute crisp golden-brown pixel-art dried little fish snack (小鱼干)
  (1,0) westie_eat_1     : Westie puppy facing right crouched nibbling a bone biscuit (bite frame 1, mouth open crunching)
  (2,0) westie_eat_2     : Westie puppy facing right chewing happily (munch frame 2, happy squinted ^ ^ eyes, puffed cheeks)
  (0,1) cat_eat_1        : Golden Shaded Cat facing right crouched nibbling a crispy dried fish (bite frame 1, mouth open)
  (1,1) cat_eat_2        : Golden Shaded Cat facing right chewing happily (munch frame 2, happy squinted ^ ^ eyes, chubby cheeks)
  (2,1) extra_happy_cat  : Satisfied licking lips pose (optional)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_assets import FLARE_DEPLOYMENT, load_api_key
from generate_cat_and_flashstep import edit_image_multi_ref
from process_sprites import clean_and_normalize_sprite


TREAT_EAT_PROMPT = (
    "Using the EXACT SAME pixel-art white Westie puppy from Image 1 (fluffy white fur, STRICTLY TWO pointed pink-lined ears, light-blue collar) "
    "and the EXACT SAME pixel-art chubby Golden Shaded British Shorthair cat from Image 2 (round golden-cream cheeks, grey-brown shading, emerald eyes, STRICTLY TWO rounded cat ears, ringed tail, NO hat, NO collar), "
    "create a 1536x1024 transparent-background 32-bit retro pixel art sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO drop shadows, crisp dark pixel outline, generous transparent margin): "
    "Row 1 Col 1 (top-left): DRIED FISH SNACK ('小鱼干') — a cute, appetizing crispy golden-brown & silver-tan dried little fish cat treat angled slightly diagonally, clean bold dark pixel outline, readable at small 26px game icon size. "
    "Row 1 Col 2 (top-center): WESTIE EATING FRAME 1 (facing RIGHT) — the Westie puppy from Image 1 crouched happily on the ground holding a small white bone biscuit between its front paws, head dipped down taking an eager bite with mouth slightly open, happy eyes. "
    "Row 1 Col 3 (top-right): WESTIE EATING FRAME 2 (facing RIGHT) — EXACT same body & position as Row 1 Col 2, chewing the bone blissfully with eyes happily squinted shut in cute curved '^ ^' happy arches, cheeks puffed chewing, tail perked happily. "
    "Row 2 Col 1 (bottom-left): GOLDEN CAT EATING FRAME 1 (facing RIGHT) — the chubby Golden Shaded Cat from Image 2 crouched happily on the ground holding a small golden-brown dried fish snack ('小鱼干') between its front paws, head dipped down taking an eager nibble with mouth slightly open. "
    "Row 2 Col 2 (bottom-center): GOLDEN CAT EATING FRAME 2 (facing RIGHT) — EXACT same body & position as Row 2 Col 1, munching the dried fish blissfully with eyes happily squinted shut in cute curved '^ ^' happy arches, chubby cheeks puffed chewing, ringed tail happily curled. "
    "Row 2 Col 3 (bottom-right): GOLDEN CAT HAPPY LICKING LIPS (facing front-right) — chubby golden cat sitting happily licking its tiny pink tongue after finishing its snack."
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", required=True)
    parser.add_argument("--raw-dir", default=str(Path(__file__).resolve().parent.parent / "assets_raw"))
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent / "Sources" / "WestieDeskPet" / "Resources" / "Sprites"),
    )
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)
    sheet_path = raw_dir / "treat_eating_sheet.png"
    if args.force and sheet_path.exists():
        sheet_path.unlink()

    if not sheet_path.exists():
        endpoint, api_key = load_api_key(args.config_ini)
        edit_image_multi_ref(
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            [out_dir / "westie_idle.png", out_dir / "cat_idle.png"],
            TREAT_EAT_PROMPT,
            sheet_path,
            size="1536x1024",
            quality="high",
        )

    sheet = Image.open(sheet_path).convert("RGBA")
    cw, rh = sheet.width // 3, sheet.height // 2

    # (0,0) dried_fish_treat (64x64 matching bone_treat.png!)
    fish, _ = clean_and_normalize_sprite(sheet.crop((0, 0, cw, rh)), canvas_size=64, bottom_align=False, padding=6)
    fish.save(out_dir / "dried_fish_treat.png")
    print("[SPRITE] Saved dried_fish_treat.png (64x64)", flush=True)

    # Westie eating 1 & 2 locked to identical scale!
    w_scale: float | None = None
    for col, name in [(1, "westie_eat_1"), (2, "westie_eat_2")]:
        spr, sc = clean_and_normalize_sprite(
            sheet.crop((col * cw, 0, (col + 1) * cw, rh)),
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=w_scale,
        )
        if w_scale is None:
            w_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # Cat eating 1 & 2 locked to identical scale!
    c_scale: float | None = None
    for col, name in [(0, "cat_eat_1"), (1, "cat_eat_2")]:
        spr, sc = clean_and_normalize_sprite(
            sheet.crop((col * cw, rh, (col + 1) * cw, 2 * rh)),
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=c_scale,
        )
        if c_scale is None:
            c_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)


if __name__ == "__main__":
    main()
