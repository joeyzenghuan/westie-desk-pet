#!/usr/bin/env python3
"""
Generate 6-frame pose-locked "翻肚皮打滚" (Belly-Up Roll-Over) pixel-art sprite sheets
for BOTH Westie dog and Golden Shaded British Shorthair cat directly from `assets_raw/打滚.mp4`
(extracted frames in `/tmp/westie_roll_video/frame_XXX.png`):

3 cols x 2 rows (1536x1024 -> 6 equal 512x512 cells -> 128x128 bottom-aligned transparent PNGs):
  R1C1 (`*_belly_roll_1`, F68): Low side-flop entry/exit bridge (lying low on side, front paws touching bar to flop down or push back up)
  R1C2 (`*_belly_roll_2`, F62): Belly-up waiting Pose A (lying on left shoulder, fluffy belly exposed toward viewer-right, bright happy eyes, front paw curled over chest)
  R1C3 (`*_belly_roll_3`, F59): Belly-up waiting Pose B (playful happy open-mouth grin, paws curled higher & hind paw lifted slightly — gently alternates with Pose A while waiting!)
  R2C1 (`*_belly_roll_4`, F53): Roll-in wind-up (pulling both paws inward over chest, tipping head backward onto crown with grinning face to roll across spine)
  R2C2 (`*_belly_roll_5`, F55): Supine dead-center apex (spine flat on ground, fluffy belly straight UP, head completely upside-down smiling at camera, ears splayed flat, ALL 4 paws kicking UP in the air!)
  R2C3 (`*_belly_roll_6`, F57): Roll-out quarter-tilt (tipping past vertical onto opposite shoulder, hind paw kicking over, happy smile)
"""
from __future__ import annotations

import argparse
import concurrent.futures
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_assets import FLARE_DEPLOYMENT, SUNBURST_DEPLOYMENT, load_api_key
from generate_cat_and_flashstep import edit_image_multi_ref
from generate_new_effects_sprites import CAT_DESC, WESTIE_DESC, slice_grid_height_locked


BELLY_ROLL_FRAME_NUMS = [68, 62, 59, 53, 55, 57]


def build_video_pose_grid(frames_dir: Path, frame_nums: list[int], out_path: Path) -> Path:
    cols, rows = 3, 2
    cw, ch = 1536 // cols, 1024 // rows
    grid = Image.new("RGB", (cw * cols, ch * rows), (210, 224, 236))
    for idx, num in enumerate(frame_nums):
        c, r = idx % cols, idx // cols
        src = Image.open(frames_dir / f"frame_{num:03d}.png").convert("RGB")
        sw, sh = src.size
        scale = min(cw / sw, ch / sh)
        nw, nh = int(round(sw * scale)), int(round(sh * scale))
        resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
        grid.paste(resized, (c * cw + (cw - nw) // 2, r * ch + (ch - nh) // 2))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(out_path)
    print(f"[REF] Built 3x2 belly-roll pose ref grid -> {out_path.name} ({grid.size})", flush=True)
    return out_path


def make_belly_roll_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow, NO rug or sofa), "
        "faithfully transfer the EXACT 6 adorable lying-down BELLY-UP ROLL-OVER poses ('翻肚皮打滚') shown in the "
        "3-column by 2-row real video reference grid in Image 2! "
        "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 3 columns by 2 rows grid "
        "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO corgi, NO furniture, generous transparent margin in every cell). "
        "CRITICAL CONSISTENCY RULES: "
        "1) Keep the pet's BODY VOLUME and HEAD SIZE 100% consistent across all 6 cells, resting cleanly on a horizontal bottom floor line in every cell! "
        "2) Match Image 2's adorable high-angle FRONT-3/4 lying-down perspective where the pet's face always stays clearly visible toward the camera while rolling across its fluffy back! "
        "Row 1 Col 1 (R1C1, matches Image 2 R1C1): LOW SIDE-FLOP BRIDGE — lying low on its left side facing front-right, both front paws lowered near the floor (bridging between sitting upright and flopping belly-up), cute bright eyes looking at owner. "
        "Row 1 Col 2 (R1C2, matches Image 2 R1C2): BELLY-UP WAITING POSE A — lying comfortably rolled onto its left shoulder/cheek with its soft fluffy BELLY tilted wide open toward VIEWER'S RIGHT waiting for belly rubs! Upper front paw curled cutely over chest, lower paw extended right, bright expectant happy eyes looking right at viewer! "
        "Row 1 Col 3 (R1C3, matches Image 2 R1C3): BELLY-UP WAITING POSE B (WIGGLE/GRIN) — same side belly-up pose as R1C2, but with an extra joyful happy smile/grin, upper front paw curled slightly higher and fluffy belly/hind paw wiggling playfully asking for pets! "
        "Row 2 Col 1 (R2C1, matches Image 2 R2C1): ROLL-IN WIND-UP — starting to roll backward onto its spine! Both front paws curled snugly inward over chest, head tipping backward with playful grinning expression as ears press toward the floor. "
        "Row 2 Col 2 (R2C2, matches Image 2 R2C2): SUPINE DEAD-CENTER APEX — lying completely flat on its back/spine! Soft fluffy BELLY facing straight UP, head UPSIDE-DOWN smiling blissfully at the camera with BOTH ears splayed flat to the sides, and ALL FOUR cute stubby paws (with tiny pink paw pads) kicked happily UP in the air! "
        "Row 2 Col 3 (R2C3, matches Image 2 R2C3): ROLL-OUT QUARTER-TILT — rolling past center from its back toward the right side! Fluffy belly turning over, paws lifted mid-tumble, head un-inverting with a joyful happy grin!"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", required=True)
    parser.add_argument("--frames-dir", default="/tmp/westie_roll_video")
    parser.add_argument("--raw-dir", default=str(Path(__file__).resolve().parent.parent / "assets_raw"))
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent / "Sources" / "WestieDeskPet" / "Resources" / "Sprites"),
    )
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    endpoint, api_key = load_api_key(args.config_ini)
    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)

    pose_ref = build_video_pose_grid(Path(args.frames_dir), BELLY_ROLL_FRAME_NUMS, raw_dir / "belly_roll_6f_pose_ref.png")
    westie_sheet = raw_dir / "westie_belly_roll_6f_sheet.png"
    cat_sheet = raw_dir / "cat_belly_roll_6f_sheet.png"
    if args.force:
        westie_sheet.unlink(missing_ok=True)
        cat_sheet.unlink(missing_ok=True)

    print("=== Generating 6-frame Belly-Up Roll-Over sheets for BOTH Westie & Golden Cat concurrently ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        fw = pool.submit(
            edit_image_multi_ref, endpoint, api_key, FLARE_DEPLOYMENT,
            [out_dir / "westie_sit_tilt.png", pose_ref],
            make_belly_roll_prompt(WESTIE_DESC), westie_sheet, "1536x1024", "high",
        )
        fc = pool.submit(
            edit_image_multi_ref, endpoint, api_key, SUNBURST_DEPLOYMENT,
            [out_dir / "cat_sit_tilt.png", pose_ref],
            make_belly_roll_prompt(CAT_DESC), cat_sheet, "1536x1024", "high",
        )
        fw.result()
        fc.result()

    slice_grid_height_locked(westie_sheet, 3, 2, 128, 128, "westie_belly_roll", out_dir, ref_cell_idx=1, center_vertical=False)
    slice_grid_height_locked(cat_sheet, 3, 2, 128, 128, "cat_belly_roll", out_dir, ref_cell_idx=1, center_vertical=False)
    print("=== DONE 12 Belly-Up Roll-Over sprites! ===", flush=True)


if __name__ == "__main__":
    main()
