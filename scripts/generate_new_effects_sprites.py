#!/usr/bin/env python3
"""
Generate pixel-art sprite sheets for 3 new independent top-bar effects for BOTH
Westie dog and Golden Shaded British Shorthair cat (36 total transparent PNGs):

1. 狗熊哆嗦毛 (Bear Fur Shake / 8-frame bipedal comedic dance, 192x128 height-locked):
   - Pose-locked 4x2 grid from `assets_raw/狗熊哆嗦毛.gif` frames [110, 113, 117, 121, 125, 130, 135, 140]
   - Outputs: {westie,cat}_bear_shake_1..8.png

2. 浪子踢球 (Wanderer Ball Kick / 6-frame folk-dance mimed punt, 192x128 height-locked):
   - Pose-locked 3x2 grid from `assets_raw/浪子踢球.gif` frames [62, 75, 93, 106, 118, 132]
   - Outputs: {westie,cat}_wanderer_kick_1..6.png

3. 窗顶打滚 (Window-Top Barrel Roll / 4-frame 360° curled somersault rolling LEFT, 128x128):
   - 2x2 sheet (1024x1024), mirrored horizontally in code when rolling LEFT -> RIGHT
   - Outputs: {westie,cat}_roll_1..4.png
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


BEAR_SHAKE_FRAMES = [110, 113, 117, 121, 125, 130, 135, 140]
WANDERER_KICK_FRAMES = [62, 75, 93, 106, 118, 132]

WESTIE_DESC = (
    "fluffy white West Highland White Terrier (Westie) puppy, pointed pink-lined upright ears "
    "(STRICTLY TWO symmetrical ears, NEVER three ears), round black eyes, black nose, "
    "light-blue collar with tiny silver tag, stubby carrot tail"
)
CAT_DESC = (
    "chubby Golden Shaded British Shorthair cat (金渐层), super round plump golden-cream cheeks, "
    "warm golden-apricot and silvery-grey tipped shading, big sparkling emerald-green eyes, "
    "tiny pink-brown button nose, STRICTLY TWO neat rounded cat ears (NEVER three ears, NO hat, NO collar), "
    "thick plush ringed golden-grey tail with dark tip"
)


def build_pose_grid(
    gif_path: Path,
    frame_indices: list[int],
    cols: int,
    rows: int,
    out_path: Path,
    trim_x_frac: float = 0.0,
) -> Path:
    im = Image.open(gif_path)
    frames: dict[int, Image.Image] = {}
    needed = set(frame_indices)
    for i in range(im.n_frames):
        if i in needed:
            im.seek(i)
            frames[i] = im.convert("RGB")

    cw, ch = 1536 // cols, 1024 // rows
    grid = Image.new("RGB", (cw * cols, ch * rows), (210, 228, 240))
    for idx, fi in enumerate(frame_indices):
        c, r = idx % cols, idx // cols
        src = frames[fi]
        if trim_x_frac > 0:
            dx = int(src.width * trim_x_frac)
            src = src.crop((dx, 0, src.width - dx, src.height))
        sw, sh = src.size
        scale = min(cw / sw, ch / sh)
        nw, nh = int(round(sw * scale)), int(round(sh * scale))
        resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
        grid.paste(resized, (c * cw + (cw - nw) // 2, r * ch + (ch - nh) // 2))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(out_path)
    print(f"[REF] Built {cols}x{rows} pose ref grid -> {out_path.name} ({grid.size})", flush=True)
    return out_path


def make_bear_shake_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow), "
        "faithfully transfer the EXACT 8 bipedal front-facing comedic dance poses ('狗熊哆嗦毛') shown in the 4-column by 2-row pose reference grid in Image 2! "
        "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 4 columns by 2 rows grid "
        "(8 equal cells of 384x512, NO grid lines, NO borders, NO text, NO human, NO studio background, generous transparent margin in every cell). "
        "CRITICAL CONSISTENCY RULES: "
        "1) The character's HEAD SIZE and STANDING TORSO SCALE must be 100% IDENTICAL across all 8 cells (NEVER shrink the character in wide-arm or straddle cells!). "
        "2) Strictly BIPEDAL upright and FRONT-FACING (chest and face always looking straight at camera!) with feet planted on the same bottom floor line in every cell. "
        "3) Capture the hilarious deadpan wide-eyed stare and small round OPEN 'O' MOUTH (😮) on the forehead-cross and floppy T-pose flap frames! "
        "Row 1 Col 1 (R1C1): WIDE STRADDLE + ARMS STRAIGHT UP — wide inverted-V hind-leg straddle, torso upright, BOTH front paws shot straight UP overhead (|o|), wide deadpan eyes. "
        "Row 1 Col 2 (R1C2): WIDE STRADDLE SQUAT + FOREHEAD X-CROSS — wide straddle knees bent low (head dips slightly), BOTH front paws/wrists CROSSED sharply in an X right in front of the forehead/brow, elbows flared out wide, round 'O' mouth (😮)! "
        "Row 1 Col 3 (R1C3): WIDE STRADDLE + FLOPPY WIDE T-POSE FLAP — wide straddle bounce, BOTH arms flung horizontally wide out at shoulder height (╭o╮) with LIMP DROOPING PAWS/WRISTS shaking like wet paws, wide serious eyes + round 'O' mouth (😮)! "
        "Row 1 Col 4 (R1C4): SHIFT LEFT SEESAW — weight planted on viewer's-left hind paw, viewer's-right hind leg lifted & tucking inward, arms in diagonal seesaw (left arm low-left, right arm sweeping high up-right). "
        "Row 2 Col 1 (R2C1): NARROW C-CURVE (\\) + ARMS UP — hind feet gathered tight & front foot crossing forward-left, torso bent in a jaunty C-curve (hips bumped right, head leaned left), both arms raised UP high overhead. "
        "Row 2 Col 2 (R2C2): DIAGONAL '/' LEAN + FOREHEAD X-CROSS — hind feet tightly X-crossed, entire straight body tilted ~22° diagonally UP-RIGHT (/), BOTH front paws crossed sharply in an X over the forehead with flared elbows, deadpan round 'O' mouth (😮)! "
        "Row 2 Col 3 (R2C3): SIGNATURE DIAGONAL '/' LEAN + SLANTED FLOPPY T-POSE — holds the rigid ~25° diagonal UP-RIGHT (/) body lean on crossed hind feet while flinging both arms into a slanted wide T-pose (left arm up-left, right arm out-right) with LIMP DROOPING WRISTS/PAWS, intense wide eyes + round 'O' mouth (😮)! "
        "Row 2 Col 4 (R2C4): SHIFT RIGHT STEP-OUT — pushing off right with viewer's-right hind leg stepping wide out right while viewer's-left foot skips off floor, arms seesaw up-right launching back into R1C1!"
    )


def make_wanderer_kick_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow, NO physical soccer ball or tennis ball prop), "
        "faithfully transfer the EXACT 6 bipedal front-facing swaggering folk-dance mimed ball-kick poses ('浪子踢球') shown in the 3-column by 2-row pose reference grid in Image 2! "
        "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 3 columns by 2 rows grid "
        "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO human, NO studio background, NO soccer ball, generous transparent margin in every cell). "
        "CRITICAL CONSISTENCY RULES: "
        "1) The character's HEAD SIZE and STANDING TORSO SCALE must be 100% IDENTICAL across all 6 cells (do NOT shrink the character in wide-arm poses!). "
        "2) Strictly BIPEDAL standing on hind legs facing FRONT toward the camera in ALL 6 cells, with the standing hind foot planted solidly on the exact same floor baseline. "
        "Row 1 Col 1 (R1C1 — 起势 Arm-Open Prep): Upright bipedal facing camera, hind feet planted neatly together, BOTH front paws flung wide outward-upward in a joyful open Y/T (~105°), bright eager eyes straight ahead. "
        "Row 1 Col 2 (R1C2 — 蹲身蓄势 Deep Diagonal Crouch): Body crouched low (~15% lower), both hind knees bent deeply & angled diagonally toward viewer's right, both front paws arched wide downward like eagle wings (left paw lower near hip, right paw extended wider), head tilted down-right with eyes LOCKED DOWNWARD at the floor! "
        "Row 1 Col 3 (R1C3 — 后勾腿蓄力 Coiled Rear-Hook Chamber): Balanced on viewer's-right hind paw (knee bent flat on floor), viewer's-left hind leg lifted & bent sharply 90° out/behind to viewer's LEFT in midair! Both front paws arched wide downward like eagle wings, head still looking intensely down-right at the floor! "
        "Row 2 Col 1 (R2C1 — 扫腿撇踢 Explosive Whip Kick): Dynamic transition! Body rising, viewer's-left hind leg whipping downward & forward right past the standing hind ankle just above the floor (include a tiny crisp 2-3px pixel-art white motion-swoosh arc beside the kicking paw!), front paws snapping upward through horizontal, head lifting toward camera. "
        "Row 2 Col 2 (R2C2 — 浪子亮相 HERO SHOWSTOPPER CROSS-KICK + 'W' ARMS): Standing hind leg planted straight on floor, kicking hind leg CROSSED DIAGONALLY IN FRONT to viewer's bottom-right forming a crisp unmistakable X-cross with kicking paw hovering slightly off floor! Torso proud & upright with jaunty swagger lean back-left, BOTH front paws raised high in a triumphant open 'W' cheer pose beside cheeks/ears with paw pads open! Head straight at camera with a super cool smug beaming grin! "
        "Row 2 Col 3 (R2C3 — 收势 Step-Down Recovery): Upright graceful recovery facing camera, kicking hind leg uncrossing back toward viewer's left just about to touch down, both front paws sweeping gently downward ~45° at sides, happy satisfied expression."
    )


def make_roll_prompt(species_desc: str) -> str:
    return (
        f"Using the EXACT SAME 32-bit retro pixel art pet character from Image 1 ({species_desc}, "
        "crisp dark pixel outline, NO anti-aliasing blur, NO background, NO floor shadow), "
        "create a 1024x1024 transparent-background 2-column by 2-row sprite sheet (4 equal cells of 512x512, "
        "NO grid lines, NO borders, NO text, generous transparent margin in every cell) showing an ADORABLE continuous "
        "4-frame 360-degree curled-up SOMERSAULT / BARREL ROLL cycle rolling toward the LEFT (counter-clockwise tumble across a window top bar)! "
        "CRITICAL CONSISTENCY RULES: "
        "1) The curled fluffy ball silhouette should keep a consistent compact round diameter across all 4 frames so cycling Frame 1 -> 2 -> 3 -> 4 -> 1 looks like a super smooth, bouncy, continuous rolling ball of fur! "
        "2) Expressive chibi pixel-art charm — show tucked ears, fluffy round back, cute paw pads, and playful face! "
        "Row 1 Col 1 (Frame 1 — 0° Tuck Dive Left): Facing LEFT, curled tight into a plump round ball diving head-first down-left to start the roll, chin tucked toward chest, round fluffy back arched high, paws tucked snugly in, cute determined/excited eyes. "
        "Row 1 Col 2 (Frame 2 — 90° Nose-Down Roll): Rolled 90° counter-clockwise! Head and ears tucked down-right near the bottom, plump round fluffy back and cute tail curling over the top-left, paws tucked tightly into the curled furry sphere. "
        "Row 2 Col 1 (Frame 3 — 180° Upside-Down Belly-Up): Rolled completely UPSIDE-DOWN resting on its round fluffy back! Upside-down happy grinning head on the right side, plump belly facing UP, all four stubby paws with tiny pink paw pads sticking playfully UP in the air! "
        "Row 2 Col 2 (Frame 4 — 270° Tail-Over-Head Pop-Up): Rolled 270° counter-clockwise completing the flip! Head and perky ears popping back up on the left side, round rump and tail swinging up over the right side, front paws reaching down-left to catch the floor and keep rolling!"
    )


def slice_grid_height_locked(
    sheet_path: Path,
    cols: int,
    rows: int,
    canvas_w: int,
    canvas_h: int,
    out_prefix: str,
    out_dir: Path,
    ref_cell_idx: int = 0,
    center_vertical: bool = False,
) -> None:
    sheet = Image.open(sheet_path).convert("RGBA")
    cw, rh = sheet.width // cols, sheet.height // rows
    pad_y = 8

    cleaned_crops: list[Image.Image] = []
    total = cols * rows
    for idx in range(total):
        c, r = idx % cols, idx // cols
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

    if center_vertical:
        # For rolling ball: normalize max bounding dimension across all 4 cells so the ball stays perfectly round & constant diameter!
        max_dim = max(max(c.width, c.height) for c in cleaned_crops)
        target_dim = min(canvas_w, canvas_h) - 18
        uniform_scale = target_dim / max(1, max_dim)
    else:
        ref_h = max(1, cleaned_crops[ref_cell_idx].height)
        base_scale = (canvas_h - pad_y * 2) / ref_h
        max_w = max(c.width for c in cleaned_crops)
        max_h = max(c.height for c in cleaned_crops)
        uniform_scale = min(base_scale, (canvas_w - 8) / max_w, (canvas_h - 8) / max_h)

    for idx, crop in enumerate(cleaned_crops):
        nw = max(1, int(round(crop.width * uniform_scale)))
        nh = max(1, int(round(crop.height * uniform_scale)))
        resized = crop.resize((nw, nh), resample=Image.Resampling.NEAREST)
        out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        paste_x = (canvas_w - nw) // 2
        paste_y = (canvas_h - nh) // 2 if center_vertical else (canvas_h - nh - 4)
        out.paste(resized, (paste_x, paste_y), resized)
        dest = out_dir / f"{out_prefix}_{idx + 1}.png"
        out.save(dest)
        print(f"[SPRITE] Saved {dest.name} ({canvas_w}x{canvas_h}, content={nw}x{nh}, scale={uniform_scale:.3f})", flush=True)


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

    bear_ref = build_pose_grid(
        raw_dir / "狗熊哆嗦毛.gif", BEAR_SHAKE_FRAMES, 4, 2,
        raw_dir / "bear_shake_8f_pose_ref.png", trim_x_frac=0.14,
    )
    kick_ref = build_pose_grid(
        raw_dir / "浪子踢球.gif", WANDERER_KICK_FRAMES, 3, 2,
        raw_dir / "wanderer_kick_6f_pose_ref.png", trim_x_frac=0.06,
    )

    jobs = [
        ("westie_bear_shake", FLARE_DEPLOYMENT, [out_dir / "westie_sit_tilt.png", bear_ref], make_bear_shake_prompt(WESTIE_DESC), raw_dir / "westie_bear_shake_8f_sheet.png", "1536x1024", 4, 2, 192, 128, 0, False),
        ("cat_bear_shake", SUNBURST_DEPLOYMENT, [out_dir / "cat_sit_tilt.png", bear_ref], make_bear_shake_prompt(CAT_DESC), raw_dir / "cat_bear_shake_8f_sheet.png", "1536x1024", 4, 2, 192, 128, 0, False),
        ("westie_wanderer_kick", FLARE_DEPLOYMENT, [out_dir / "westie_sit_tilt.png", kick_ref], make_wanderer_kick_prompt(WESTIE_DESC), raw_dir / "westie_wanderer_kick_6f_sheet.png", "1536x1024", 3, 2, 192, 128, 0, False),
        ("cat_wanderer_kick", SUNBURST_DEPLOYMENT, [out_dir / "cat_sit_tilt.png", kick_ref], make_wanderer_kick_prompt(CAT_DESC), raw_dir / "cat_wanderer_kick_6f_sheet.png", "1536x1024", 3, 2, 192, 128, 0, False),
        ("westie_roll", FLARE_DEPLOYMENT, [out_dir / "westie_sit_tilt.png", out_dir / "westie_loaf_calm.png"], make_roll_prompt(WESTIE_DESC), raw_dir / "westie_roll_4f_sheet.png", "1024x1024", 2, 2, 128, 128, 0, True),
        ("cat_roll", SUNBURST_DEPLOYMENT, [out_dir / "cat_sit_tilt.png", out_dir / "cat_loaf_calm.png"], make_roll_prompt(CAT_DESC), raw_dir / "cat_roll_4f_sheet.png", "1024x1024", 2, 2, 128, 128, 0, True),
    ]

    if args.force:
        for job in jobs:
            job[4].unlink(missing_ok=True)

    print("=== Generating all 6 sprite sheets (36 new sprites) concurrently ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futs = [
            (job, pool.submit(edit_image_multi_ref, endpoint, api_key, job[1], job[2], job[3], job[4], job[5], "high"))
            for job in jobs
        ]
        for job, fut in futs:
            fut.result()

    for prefix, _, _, _, sheet_path, _, cols, rows, cw, ch, ref_idx, center_v in jobs:
        slice_grid_height_locked(sheet_path, cols, rows, cw, ch, prefix, out_dir, ref_idx, center_v)

    print("=== DONE generating & slicing all 36 new effect sprites! ===", flush=True)


if __name__ == "__main__":
    main()
