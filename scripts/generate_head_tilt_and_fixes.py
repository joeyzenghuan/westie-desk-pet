#!/usr/bin/env python3
"""
1. Generate 6-frame "歪头杀" (Head-Tilt Kill) pixel-art sprite sheets for BOTH Westie & Golden Cat
   (3x2 grid, 1536x1024 -> 128x128 bottom-aligned transparent PNGs, stationary planted paws!):
   Frames from `assets_raw/歪头杀.gif`: [94, 128, 105, 117, 157, 168]
   Outputs: {westie,cat}_head_tilt_1..6.png

2. Regenerate `cat_bear_shake_7.png` (unclipped right paw, height-locked to `cat_bear_shake_1.png`).

3. Rebuild `westie_roll_2..4.png` and `cat_roll_2..4.png` via lossless exact 90° CCW pixel rotations
   of the QA-verified `westie_roll_1.png` and `cat_roll_1.png` curled somersault balls so rolling
   chirality, outline crispness, and ball radius are 100% consistent across the full 360° roll.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_assets import FLARE_DEPLOYMENT, SUNBURST_DEPLOYMENT, load_api_key
from generate_cat_and_flashstep import edit_image_multi_ref
from generate_new_effects_sprites import CAT_DESC, WESTIE_DESC, build_pose_grid, slice_grid_height_locked
from process_sprites import keep_largest_component


HEAD_TILT_FRAMES = [94, 128, 105, 117, 157, 168]


def make_head_tilt_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow), "
        "faithfully replicate the EXACT 6 adorable front-facing head-tilt poses ('歪头杀') shown in the "
        "3-column by 2-row reference grid in Image 2! "
        "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 3 columns by 2 rows grid "
        "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO real photo background, generous transparent margin in every cell). "
        "CRITICAL CONSISTENCY RULES: "
        "1) The seated BODY, chest, shoulders, and TWO STRAIGHT SYMMETRICAL FRONT PAWS planted side-by-side on the floor must be 100% IDENTICAL, UPRIGHT, and COMPLETELY STATIONARY across all 6 cells! "
        "2) ONLY the HEAD (with both perked ears rotating rigidly with the skull!) pivots cleanly around the neck to exact tilt angles while wide sparkling eyes stay locked straight onto the viewer! "
        "3) Identical head size, body height, and bottom paw baseline in all 6 cells. "
        "Row 1 Col 1 (R1C1 — Upright Happy Sit): Sitting upright facing straight front, head level (0°), happy open mouth with a tiny cute pink tongue peeking out! "
        "Row 1 Col 2 (R1C2 — Upright Attentive Neutral): Exact same upright front-facing sit, head level (0°), mouth CLOSED attentively, wide bright curious eyes staring straight at viewer. "
        "Row 1 Col 3 (R1C3 — Deep Left Tilt -34°): Exact same stationary upright body & front paws, HEAD tilted deeply ~34° COUNTER-CLOCKWISE to VIEWER'S LEFT (top of head & ears lean LEFT, right ear dips low!), mouth CLOSED, super curious eyes locked on camera! "
        "Row 2 Col 1 (R2C1 — Moderate Right Tilt +20°): Exact same stationary upright body & front paws, HEAD tilted moderately ~20° CLOCKWISE to VIEWER'S RIGHT (top of head & ears lean RIGHT), mouth CLOSED, curious eyes locked on camera! "
        "Row 2 Col 2 (R2C2 — Deep Right Tilt +33°): Exact same stationary upright body & front paws, HEAD tilted deeply ~33° CLOCKWISE to VIEWER'S RIGHT (top of head & ears lean far RIGHT, left ear dips low!), mouth CLOSED, adorable questioning stare! "
        "Row 2 Col 3 (R2C3 — Hero Deepest Left Tilt -36°): Exact same stationary upright body & front paws, HEAD perked slightly up and tilted MAXIMALLY ~36° COUNTER-CLOCKWISE to VIEWER'S LEFT, mouth CLOSED, ultra-cute wide sparkling eyes staring right into viewer's soul!"
    )


def build_single_frame_ref(gif_path: Path, frame_idx: int, out_path: Path) -> Path:
    im = Image.open(gif_path)
    im.seek(frame_idx)
    rgb = im.convert("RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    rgb.save(out_path)
    return out_path


def make_cat_bear_shake_7_prompt() -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({CAT_DESC}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow), "
        "draw a SINGLE full-body sprite centered with GENEROUS EMPTY TRANSPARENT MARGIN on ALL FOUR SIDES "
        "(keep at least 18% blank transparent space on left, right, top, and bottom so NO paw, ear, or tail EVER touches or clips the canvas edge!). "
        "Match the EXACT signature diagonal '/' lean floppy T-pose from Image 3 (reference dancer) and the exact pixel-art style/scale of Image 2: "
        "Standing upright on two hind feet tightly X-crossed, entire straight chubby golden cat body tilted ~25° diagonally UP-RIGHT (/), "
        "BOTH arms flung out wide into a slanted floppy T-pose (viewer's-left arm angled up-left, viewer's-right arm stretched out to viewer's right with COMPLETE unclipped round drooping paw/wrist!), "
        "hilarious intense wide emerald-green eyes staring straight at camera + small round open 'O' mouth (😮), plush ringed golden-grey tail arcing left for balance!"
    )


def normalize_single_to_height(src_path: Path, ref_sprite_path: Path, dest_path: Path, canvas_w: int = 192, canvas_h: int = 128) -> None:
    src = Image.open(src_path).convert("RGBA")
    rgba = np.array(src)
    mask = rgba[:, :, 3] >= 45
    if np.any(mask):
        mask = keep_largest_component(mask)
    rgba[~mask] = [0, 0, 0, 0]
    ys, xs = np.where(mask)
    crop = Image.fromarray(rgba[int(ys.min()):int(ys.max()) + 1, int(xs.min()):int(xs.max()) + 1], mode="RGBA")

    # Match height to ref_sprite's visible height * 0.90 (frame 7 leans ~25° so height is ~90% of standing arms-up frame 1)
    ref_rgba = np.array(Image.open(ref_sprite_path).convert("RGBA"))
    rys, _ = np.where(ref_rgba[:, :, 3] >= 45)
    target_h = int(round((int(rys.max()) - int(rys.min()) + 1) * 0.90))
    scale = min(target_h / max(1, crop.height), (canvas_w - 10) / max(1, crop.width), (canvas_h - 8) / max(1, crop.height))
    nw = max(1, int(round(crop.width * scale)))
    nh = max(1, int(round(crop.height * scale)))
    resized = crop.resize((nw, nh), resample=Image.Resampling.NEAREST)
    out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    out.paste(resized, ((canvas_w - nw) // 2, canvas_h - nh - 4), resized)
    out.save(dest_path)
    print(f"[FIX] Saved {dest_path.name} ({canvas_w}x{canvas_h}, content={nw}x{nh}, scale={scale:.3f})", flush=True)


def rebuild_exact_90deg_roll_sprites(out_dir: Path, prefix: str) -> None:
    """Lossless exact 90° CCW pixel transposes from verified `*_roll_1.png` (128x128 centered)."""
    base_path = out_dir / f"{prefix}_roll_1.png"
    base = Image.open(base_path).convert("RGBA")
    # Center the tight bounding box of roll_1 perfectly in 128x128 so rotation axis = exact geometric ball center!
    rgba = np.array(base)
    ys, xs = np.where(rgba[:, :, 3] >= 45)
    crop = Image.fromarray(rgba[int(ys.min()):int(ys.max()) + 1, int(xs.min()):int(xs.max()) + 1], mode="RGBA")
    centered = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    centered.paste(crop, ((128 - crop.width) // 2, (128 - crop.height) // 2), crop)
    centered.save(base_path)

    for idx, transpose_op in [
        (2, Image.Transpose.ROTATE_90),
        (3, Image.Transpose.ROTATE_180),
        (4, Image.Transpose.ROTATE_270),
    ]:
        rot = centered.transpose(transpose_op)
        dest = out_dir / f"{prefix}_roll_{idx}.png"
        rot.save(dest)
        print(f"[ROLL] Rebuilt {dest.name} via exact lossless {90 * (idx - 1)}° CCW transpose", flush=True)


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

    endpoint, api_key = load_api_key(args.config_ini)
    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)

    # 1. Exact lossless 360° roll frames from QA-verified roll_1
    rebuild_exact_90deg_roll_sprites(out_dir, "westie")
    rebuild_exact_90deg_roll_sprites(out_dir, "cat")

    # 2. Build pose refs
    ht_ref = build_pose_grid(raw_dir / "歪头杀.gif", HEAD_TILT_FRAMES, 3, 2, raw_dir / "head_tilt_6f_pose_ref.png")
    bs7_ref = build_single_frame_ref(raw_dir / "狗熊哆嗦毛.gif", 135, raw_dir / "bear_shake_f135_ref.png")

    westie_ht_sheet = raw_dir / "westie_head_tilt_6f_sheet.png"
    cat_ht_sheet = raw_dir / "cat_head_tilt_6f_sheet.png"
    cat_bs7_raw = raw_dir / "cat_bear_shake_7_fix.png"
    if args.force:
        westie_ht_sheet.unlink(missing_ok=True)
        cat_ht_sheet.unlink(missing_ok=True)
        cat_bs7_raw.unlink(missing_ok=True)

    print("=== Generating Head-Tilt 6f sheets (Westie + Cat) & Cat Bear-Shake #7 fix concurrently ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        f1 = pool.submit(
            edit_image_multi_ref, endpoint, api_key, FLARE_DEPLOYMENT,
            [out_dir / "westie_sit_tilt.png", ht_ref],
            make_head_tilt_prompt(WESTIE_DESC), westie_ht_sheet, "1536x1024", "high",
        )
        f2 = pool.submit(
            edit_image_multi_ref, endpoint, api_key, SUNBURST_DEPLOYMENT,
            [out_dir / "cat_sit_tilt.png", ht_ref],
            make_head_tilt_prompt(CAT_DESC), cat_ht_sheet, "1536x1024", "high",
        )
        f3 = pool.submit(
            edit_image_multi_ref, endpoint, api_key, FLARE_DEPLOYMENT,
            [out_dir / "cat_sit_tilt.png", out_dir / "cat_bear_shake_6.png", bs7_ref],
            make_cat_bear_shake_7_prompt(), cat_bs7_raw, "1024x1024", "high",
        )
        f1.result()
        f2.result()
        f3.result()

    slice_grid_height_locked(westie_ht_sheet, 3, 2, 128, 128, "westie_head_tilt", out_dir, ref_cell_idx=0, center_vertical=False)
    slice_grid_height_locked(cat_ht_sheet, 3, 2, 128, 128, "cat_head_tilt", out_dir, ref_cell_idx=0, center_vertical=False)
    normalize_single_to_height(cat_bs7_raw, out_dir / "cat_bear_shake_1.png", out_dir / "cat_bear_shake_7.png")
    print("=== DONE Head-Tilt 12 sprites + Cat Bear-Shake #7 fix + Roll 360° fixes! ===", flush=True)


if __name__ == "__main__":
    main()
