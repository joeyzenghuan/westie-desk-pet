#!/usr/bin/env python3
"""
Generate authentic 8-frame "闪身步" (Flash-Step) pixel-art sprite sheets for BOTH
Westie and Golden Shaded Cat, pose-locked directly to the 8 key frames extracted from
`assets_raw/闪身步.gif`:

4 columns x 2 rows (1536x1024 -> 8 cells, saved as 192x128 height-locked transparent PNGs so the
1.8x wide A-frame split NEVER shrinks the character's head/torso!):
  R1 C1 -> *_flash_step_1 (F56)  : Neutral deadpan upright statue (feet together, arms straight at sides)
  R1 C2 -> *_flash_step_2 (F60)  : Micro-unweight pop (knees unlock, feet pop slightly apart, arms flare ~15 deg)
  R1 C3 -> *_flash_step_3 (F66)  : Burst-L Peak Counter-Lean (1.8x wide A-frame split, body low, head/torso tilted ~20° RIGHT, right paw whips LEFT across belly, left paw out down-left)
  R1 C4 -> *_flash_step_4 (F70)  : Burst-L Floating Statue Glide (torso/head snapped 100% vertical deadpan, BOTH paws straight at sides, hind legs STILL 1.4x wide shifting over planted left leg)
  R2 C1 -> *_flash_step_5 (F73)  : Burst-L Trailing Snap-Close (torso/head/paws 100% rigid upright, left leg straight planted, right leg bent sweeping inward)
  R2 C2 -> *_flash_step_6 (F102) : Burst-R Peak Counter-Lean Mirror (1.9x wide split, body low, head/torso tilted ~20° LEFT, left paw whips RIGHT across belly, right paw out down-right)
  R2 C3 -> *_flash_step_7 (F107) : Burst-R Floating Statue Glide Mirror (torso/head snapped 100% vertical deadpan, BOTH paws straight at sides, weight shifting over planted right leg)
  R2 C4 -> *_flash_step_8 (F110) : Burst-R Trailing Snap-Close Mirror (torso/head/paws 100% rigid upright, right leg straight planted, left leg bent sweeping inward)
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
from process_sprites import keep_largest_component


GIF_KEYFRAMES = [56, 60, 66, 70, 73, 102, 107, 110]


def build_pose_reference_grid(gif_path: Path, out_grid_path: Path) -> Path:
    im = Image.open(gif_path)
    frames: dict[int, Image.Image] = {}
    needed = set(GIF_KEYFRAMES)
    for i in range(im.n_frames):
        if i in needed:
            im.seek(i)
            frames[i] = im.convert("RGB")

    # Arrange 4x2 cleanly into 1536x1024 (each cell 384x512, preserving full human pose centered cleanly)
    cw, ch = 384, 512
    grid = Image.new("RGB", (cw * 4, ch * 2), (210, 228, 240))
    for idx, fi in enumerate(GIF_KEYFRAMES):
        c, r = idx % 4, idx // 4
        src = frames[fi]
        # Fit preserving aspect ratio centered inside cell
        sw, sh = src.size
        scale = min(cw / sw, ch / sh)
        nw, nh = int(round(sw * scale)), int(round(sh * scale))
        resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
        grid.paste(resized, (c * cw + (cw - nw) // 2, r * ch + (ch - nh) // 2))

    out_grid_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(out_grid_path)
    print(f"[REF] Built 4x2 real GIF pose reference grid -> {out_grid_path} ({grid.size})", flush=True)
    return out_grid_path


def make_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "STRICTLY TWO symmetrical ears — NEVER three ears, crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow), "
        "faithfully transfer the EXACT 8 bipedal full-body dance poses ('闪身步') shown in the 4-column by 2-row pose reference grid in Image 2! "
        "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 4 columns by 2 rows grid "
        "(8 equal cells of 384x512, NO grid lines, NO borders, NO text, NO human, NO studio background, generous transparent margin in every cell). "
        "CRITICAL CONSISTENCY RULES: "
        "1) The character's HEAD SIZE and STANDING TORSO HEIGHT must be 100% IDENTICAL across all 8 cells (do NOT shrink the character in wide-leg split cells!). "
        "2) Standing upright on two hind legs facing the camera in ALL 8 cells, matching the exact foot baseline across each row. "
        "3) Capture the hilarious DEADPAN serious face during neutral/glide poses and the exaggerated ~20-degree COUNTER-LEAN + 1.8x WIDE A-FRAME LEG SPLIT in cells (1,3) and (2,2)! "
        "Row 1 Col 1 (matches Image 2 R1C1): NEUTRAL STATUE — standing deadpan straight upright facing camera, hind feet neat & close together, BOTH front paws hanging completely straight and relaxed down at the sides. "
        "Row 1 Col 2 (matches Image 2 R1C2): UNWEIGHT POP — knees slightly bent, hind feet popped slightly apart (~0.8x body width), both front paws flared ~15° outward from sides, deadpan alert look. "
        "Row 1 Col 3 (matches Image 2 R1C3): WIDE SPLIT + COUNTER-LEAN RIGHT — extreme 1.8x-wide low A-frame hind-leg straddle (body dropped low!), HEAD & TORSO tilted strongly ~20° to VIEWER'S RIGHT (fake-out lean!), viewer's-left front paw extended diagonally down-left, viewer's-right front paw whipped horizontally LEFT across the belly! "
        "Row 1 Col 4 (matches Image 2 R1C4): FLOATING STATUE GLIDE LEFT — head & torso snapped 100% STRAIGHT VERTICAL & deadpan with BOTH front paws hanging straight and relaxed down at sides, while hind legs remain WIDE (~1.4x width) with weight shifting onto the planted viewer's-left leg! "
        "Row 2 Col 1 (matches Image 2 R2C1): TRAILING LEG SNAP-CLOSE LEFT — head, torso & relaxed side paws stay 100% vertical & deadpan, viewer's-left hind leg planted straight down, viewer's-right hind leg slightly bent sweeping inward toward the left leg! "
        "Row 2 Col 2 (matches Image 2 R2C2): WIDE SPLIT + COUNTER-LEAN LEFT (mirror) — extreme 1.8x-wide low A-frame hind-leg straddle (body dropped low!), HEAD & TORSO tilted strongly ~20° to VIEWER'S LEFT (fake-out lean!), viewer's-left front paw whipped horizontally RIGHT across the belly, viewer's-right front paw extended diagonally down-right! "
        "Row 2 Col 3 (matches Image 2 R2C3): FLOATING STATUE GLIDE RIGHT (mirror) — head & torso snapped 100% STRAIGHT VERTICAL & deadpan with BOTH front paws hanging straight and relaxed down at sides, while hind legs remain WIDE (~1.4x width) shifting weight onto the planted viewer's-right leg! "
        "Row 2 Col 4 (matches Image 2 R2C4): TRAILING LEG SNAP-CLOSE RIGHT (mirror) — head, torso & relaxed side paws stay 100% vertical & deadpan, viewer's-right hind leg planted straight down, viewer's-left hind leg slightly bent sweeping inward toward the right leg!"
    )


def slice_4x2_height_locked(sheet_path: Path, prefix: str, out_dir: Path) -> None:
    """
    Slices a 4x2 sheet into 8 `192x128` transparent PNGs using ONE height-locked scale derived from
    Cell (0,0) (`neutral_stop`), so the pet's head and torso NEVER shrink during the 1.8x wide A-frame split!
    """
    sheet = Image.open(sheet_path).convert("RGBA")
    cw, rh = sheet.width // 4, sheet.height // 2
    canvas_w, canvas_h = 192, 128
    pad_y = 8

    cleaned_crops: list[Image.Image] = []
    for idx in range(8):
        c, r = idx % 4, idx // 4
        cell = sheet.crop((c * cw, r * rh, (c + 1) * cw, (r + 1) * rh))
        rgba = np.array(cell)
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
            cleaned_crops.append(Image.new("RGBA", (1, 1), (0, 0, 0, 0)))
        else:
            x0, x1 = int(xs.min()), int(xs.max()) + 1
            y0, y1 = int(ys.min()), int(ys.max()) + 1
            cleaned_crops.append(Image.fromarray(rgba[y0:y1, x0:x1], mode="RGBA"))

    # Lock scale to neutral standing height (Cell 0) so target standing height = 112px inside 128px height!
    ref_h = max(1, cleaned_crops[0].height)
    base_scale = (canvas_h - pad_y * 2) / ref_h
    # Also ensure even the widest split fits comfortably inside 192px canvas width without clipping!
    max_w = max(c.width for c in cleaned_crops)
    max_h = max(c.height for c in cleaned_crops)
    uniform_scale = min(base_scale, (canvas_w - 8) / max_w, (canvas_h - 8) / max_h)

    for idx, crop in enumerate(cleaned_crops):
        nw = max(1, int(round(crop.width * uniform_scale)))
        nh = max(1, int(round(crop.height * uniform_scale)))
        resized = crop.resize((nw, nh), resample=Image.Resampling.NEAREST)
        out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        paste_x = (canvas_w - nw) // 2
        paste_y = canvas_h - nh - 4
        out.paste(resized, (paste_x, paste_y), resized)
        dest = out_dir / f"{prefix}_flash_step_{idx + 1}.png"
        out.save(dest)
        print(f"[SPRITE] Saved {dest.name} ({canvas_w}x{canvas_h}, content={nw}x{nh}, scale={uniform_scale:.3f})", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", required=True)
    parser.add_argument("--gif-path", default=str(Path(__file__).resolve().parent.parent / "assets_raw" / "闪身步.gif"))
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

    pose_ref = build_pose_reference_grid(Path(args.gif_path), raw_dir / "flash_step_8f_pose_ref.png")

    westie_sheet = raw_dir / "westie_flash_step_8f_sheet.png"
    cat_sheet = raw_dir / "cat_flash_step_8f_sheet.png"
    if args.force:
        westie_sheet.unlink(missing_ok=True)
        cat_sheet.unlink(missing_ok=True)

    westie_prompt = make_prompt(
        "fluffy white West Highland White Terrier (Westie) puppy, pointed pink-lined upright ears, round black eyes, black nose, light-blue collar with tiny silver tag"
    )
    cat_prompt = make_prompt(
        "chubby Golden Shaded British Shorthair cat (金渐层), super round plump golden-cream cheeks, silvery-grey tipped shading, big sparkling emerald-green eyes, pink-brown button nose, thick ringed golden-grey tail, NO hat, NO collar"
    )

    print("=== Generating 8-frame Flash-Step sheets for BOTH Westie & Golden Cat in parallel ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        fw = pool.submit(
            edit_image_multi_ref,
            endpoint, api_key, FLARE_DEPLOYMENT,
            [out_dir / "westie_sit_tilt.png", pose_ref],
            westie_prompt, westie_sheet, "1536x1024", "high",
        )
        fc = pool.submit(
            edit_image_multi_ref,
            endpoint, api_key, SUNBURST_DEPLOYMENT,
            [out_dir / "cat_sit_tilt.png", pose_ref],
            cat_prompt, cat_sheet, "1536x1024", "high",
        )
        fw.result()
        fc.result()

    slice_4x2_height_locked(westie_sheet, "westie", out_dir)
    slice_4x2_height_locked(cat_sheet, "cat", out_dir)
    print("=== DONE 16 height-locked 8-frame Flash-Step sprites! ===", flush=True)


if __name__ == "__main__":
    main()
