#!/usr/bin/env python3
"""
Generate 6 reference-locked pixel-art frames for WestieDeskPet v0.4.3
using Azure GPT-Image-2.5 (/images/edits locked to westie_walk_1.png):

Layout (1536x1024, 3 columns x 2 rows, transparent PNG):
  Row 1 (True 3-frame bouncy puppy hop cycle, side profile facing RIGHT):
    (0,0) westie_hop_crouch : Coiled anticipation crouch before leaping right (chest low, paws bent ready to spring).
    (1,0) westie_hop_air    : True mid-air joyful puppy bound facing right (all 4 paws off ground, front paws reaching forward, hind legs extended back).
    (2,0) westie_hop_land   : Soft landing cushion facing right (front paws touching down first, hind paws descending behind).
  Row 2 (Stationary standing body facing LEFT, ONLY head turns to look around):
    (0,1) westie_look_left_head_left   : Standing still side-profile facing LEFT, 4 paws planted, head peering curiously LEFT.
    (1,1) westie_look_left_head_center : IDENTICAL standing body & 4 paws facing LEFT, head turned curiously toward front-center.
    (2,1) westie_look_left_head_right  : IDENTICAL standing body & 4 paws facing LEFT, ONLY head & neck turned back over shoulder peering curiously RIGHT!
"""
from __future__ import annotations

import argparse
from pathlib import Path

from generate_assets import FLARE_DEPLOYMENT, edit_image_with_reference, load_api_key
from process_sprites import clean_and_normalize_sprite
from PIL import Image


HOP_LOOK_PROMPT = (
    "Using the EXACT SAME pixel-art West Highland White Terrier (Westie) puppy character from the reference image "
    "(identical fluffy white pixel fur, STRICTLY TWO symmetrical pointed pink-lined ears — NEVER three ears, "
    "round black eyes, black button nose, light-blue collar with tiny silver tag, perky short white tail, "
    "clean dark pixel outline, 32-bit retro pixel art, NO anti-aliasing blur), "
    "create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous empty transparent margin around each sprite). "
    "Keep the puppy's body size and head size 100% consistent with the reference across all 6 cells. "
    "ROW 1 (3-frame joyful bouncy puppy hop/bound cycle in clean side-profile facing RIGHT): "
    "Row 1 Col 1 (top-left): HOP CROUCH (facing RIGHT) — playful anticipation crouch before jumping: front legs bent low, chest lowered toward the ground, hind legs coiled tightly ready to spring forward, happy excited eyes, tail perked high. "
    "Row 1 Col 2 (top-center): HOP MID-AIR LEAP (facing RIGHT) — authentic joyful mid-air puppy leap/bunny-hop: body stretched in a lively airborne arc, BOTH front paws reaching joyfully forward-up, BOTH hind legs extended playfully backward-down with clear air under the belly, ears bounced slightly back, happy open-mouth smile. "
    "Row 1 Col 3 (top-right): HOP LANDING (facing RIGHT) — soft front-paw landing cushion: both front paws touching down forward absorbing the jump, hind paws trailing slightly behind in the air about to touch down, happy expression. "
    "ROW 2 (Stationary body facing LEFT — ALL THREE CELLS in Row 2 MUST have the EXACT SAME stationary standing body, tail, and 4 planted paws facing LEFT, ONLY the puppy's head turns!): "
    "Row 2 Col 1 (bottom-left): STANDING FACING LEFT, HEAD LOOKING LEFT — puppy standing quietly in side profile facing LEFT with all 4 paws planted steadily on the ground, head craning forward-left curiously with perked ears. "
    "Row 2 Col 2 (bottom-center): STANDING FACING LEFT, HEAD LOOKING CENTER — IDENTICAL stationary body, tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the head is turned 3/4 toward the front viewer curiously. "
    "Row 2 Col 3 (bottom-right): STANDING FACING LEFT, HEAD LOOKING RIGHT — IDENTICAL stationary body, tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the head and neck are turned backward over the shoulder peering curiously to the RIGHT!"
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
    ref_walk = out_dir / "westie_walk_1.png"
    sheet_path = raw_dir / "westie_hop_look_sheet.png"

    if args.force and sheet_path.exists():
        sheet_path.unlink()

    if not sheet_path.exists():
        endpoint, api_key = load_api_key(args.config_ini)
        edit_image_with_reference(
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            ref_walk,
            HOP_LOOK_PROMPT,
            sheet_path,
            size="1536x1024",
            quality="high",
        )

    sheet = Image.open(sheet_path).convert("RGBA")
    sw, sh = sheet.size
    cw, rh = sw // 3, sh // 2

    # Row 1: 3-frame hop cycle locked to identical scale
    hop_cells = [
        (0, 0, "westie_hop_crouch"),
        (1, 0, "westie_hop_air"),
        (2, 0, "westie_hop_land"),
    ]
    hop_ref_scale: float | None = None
    for col, row, name in hop_cells:
        cell = sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        sprite, used_scale = clean_and_normalize_sprite(
            cell,
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=hop_ref_scale,
        )
        if hop_ref_scale is None:
            hop_ref_scale = used_scale
        sprite.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (128x128, scale={used_scale:.3f})")

    # Row 2: 3 locked-body look-around frames locked to identical scale!
    look_cells = [
        (0, 1, "westie_look_left_head_left"),
        (1, 1, "westie_look_left_head_center"),
        (2, 1, "westie_look_left_head_right"),
    ]
    look_ref_scale: float | None = None
    for col, row, name in look_cells:
        cell = sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        sprite, used_scale = clean_and_normalize_sprite(
            cell,
            canvas_size=128,
            bottom_align=True,
            padding=8,
            fixed_scale=look_ref_scale,
        )
        if look_ref_scale is None:
            look_ref_scale = used_scale
        sprite.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (128x128, scale={used_scale:.3f})")


if __name__ == "__main__":
    main()
