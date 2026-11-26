#!/usr/bin/env python3
"""
Generate complete Golden Shaded British Shorthair (金渐层) pixel-art sprite parity
(all 30 pet sprites + cat badge icon + 5 Flash-Step frames) AND Westie's 5 Flash-Step frames
using Azure OpenAI GPT-Image-2.5 (Flare + Sunburst concurrent /images/edits).

Phase 1 (parallel):
  - cat_companion_sheet.png     (from friend's real Golden Shaded BSH photo + Westie pixel style ref)
  - westie_flash_step_sheet.png (from westie_sit_tilt.png + user's 5-step 闪身步 pose ref)

Phase 2 (parallel, locked to cat_companion_sheet.png):
  - cat_peek_sheet.png          (peek_calm, peek_hover, loaf_calm, chin_ledge, dangling, badge_icon)
  - cat_walk_cycle_4f_sheet.png (walk_1, walk_2, walk_3, walk_4)
  - cat_climb_yawn_sheet.png    (top_peek_center, top_peek_left, top_peek_right, climb_up, yawn, drowsy)
  - cat_hop_look_sheet.png      (hop_crouch, hop_air, hop_land, look_left_head_left, look_left_head_center, look_left_head_right)
  - cat_tennis_sheet.png        (holding_ball, tennis_ready, tennis_run, tennis_swing, tennis_dive, victory)
  - cat_flash_step_sheet.png    (flash_step_1_stance, flash_step_2_right, flash_step_3_stop, flash_step_4_ready, flash_step_5_left)
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_assets import API_VERSION, FLARE_DEPLOYMENT, SUNBURST_DEPLOYMENT, load_api_key
from generate_peek_sprites import normalize_right_edge_peek
from process_sprites import clean_and_normalize_sprite


CAT_CHAR_DESC = (
    "an adorable chubby Golden Shaded British Shorthair cat (金渐层, British Shorthair ny11/ny25) matching the exact cat in Image 1: "
    "super round plump golden-cream cheeks, soft warm golden-apricot and silvery-grey tipped fur on forehead and back, "
    "fluffy creamy-white chest and belly, big round sparkling EMERALD-GREEN eyes with delicate dark eyeliner, "
    "tiny pink-brown button nose, STRICTLY TWO neat triangular rounded cat ears (NEVER three ears, NO hat, NO collar), "
    "thick fluffy ringed golden-grey tail with a dark brown-black tip, crisp dark pixel outline, "
    "32-bit retro pixel art matching the exact crisp pixel-art aesthetic of a desktop pet (NO anti-aliasing blur, NO drop shadows)"
)


def edit_image_multi_ref(
    endpoint: str,
    api_key: str,
    deployment: str,
    ref_images: list[Path],
    prompt: str,
    out_path: Path,
    size: str = "1536x1024",
    quality: str = "high",
) -> Path:
    if out_path.exists() and out_path.stat().st_size > 4096:
        print(f"[SKIP] {out_path.name} already exists.", flush=True)
        return out_path
    url = f"{endpoint}/openai/deployments/{deployment}/images/edits?api-version={API_VERSION}"
    t0 = time.perf_counter()
    for attempt in range(4):
        with tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as tf_resp:
            resp_path = tf_resp.name
        try:
            curl_cfg = f'header = "api-key: {api_key}"\n'
            cmd = [
                "/usr/bin/curl",
                "-sS",
                "--max-time", "180",
                "-K", "-",
                "-X", "POST",
            ]
            for img_p in ref_images:
                cmd += ["-F", f"image[]=@{img_p};type=image/png"]
            cmd += [
                "-F", f"prompt={prompt}",
                "-F", f"size={size}",
                "-F", f"quality={quality}",
                "-F", "n=1",
                "-F", "output_format=png",
                "-F", "background=transparent",
                "-o", resp_path,
                "-w", "%{http_code}",
                url,
            ]
            proc = subprocess.run(cmd, input=curl_cfg, text=True, capture_output=True)
            status_code = int(proc.stdout.strip() or "0")
            if proc.returncode != 0 or status_code == 0:
                print(f"[WARN] {deployment} {out_path.name} curl error ({proc.stderr.strip()}), retry {attempt + 1}/4...", flush=True)
                time.sleep(4 * (attempt + 1))
                continue
            if status_code == 429 and attempt < 3:
                print(f"[429] {deployment} {out_path.name} rate-limited, sleeping 40s...", flush=True)
                time.sleep(40)
                continue
            resp_bytes = Path(resp_path).read_bytes()
            if status_code >= 400:
                raise RuntimeError(f"HTTP {status_code} from {deployment} on {out_path.name}: {resp_bytes.decode('utf-8', 'replace')[:400]}")
            data = json.loads(resp_bytes)
            img_bytes = base64.b64decode(data["data"][0]["b64_json"])
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_bytes(img_bytes)
            elapsed = time.perf_counter() - t0
            print(f"[OK] Generated {out_path.name} via {deployment} in {elapsed:.1f}s", flush=True)
            return out_path
        finally:
            Path(resp_path).unlink(missing_ok=True)
    raise RuntimeError(f"Failed to generate {out_path.name} after retries")


def prepare_clean_cat_photo(src_photo: Path, out_clean: Path) -> Path:
    """Paint neutral soft floor color over the tiny bottom-left meme inset so GPT-Image-2.5 focuses purely on the real cat."""
    img = Image.open(src_photo).convert("RGBA")
    w, h = img.size
    # The tiny blue-bordered meme inset occupies roughly x: 10%..38%, y: 66%..99% of Attachment 1
    out = img.copy()
    px = out.load()
    # Sample floor beige color near (w*0.5, h*0.92)
    sample = px[int(w * 0.5), int(h * 0.92)]
    x0, x1 = int(w * 0.11), int(w * 0.38)
    y0, y1 = int(h * 0.67), h
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[x, y] = sample
    out_clean.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_clean)
    return out_clean


# ---------------- Prompts ----------------

CAT_COMPANION_PROMPT = (
    f"Transform the real Golden Shaded British Shorthair cat from Image 1 into {CAT_CHAR_DESC}, "
    "strictly matching the crisp 32-bit pixel art line weight, shading style, and proportions of the pixel pet sprite sheet in Image 2. "
    "Create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO boxes, NO text labels, NO drop shadows, generous transparent margin around each sprite). "
    "Consistent plump cat body & head size across all 6 cells: "
    "Row 1 Col 1 (top-left): IDLE STANDING (side-profile facing RIGHT) — plump golden shaded cat standing neatly on all four paws, big emerald eyes alert, fluffy ringed tail curled cheerfully upward. "
    "Row 1 Col 2 (top-center): CALM SITTING SMILE (front-facing 3/4) — chubby golden shaded cat sitting neatly facing the camera with an adorable slight head tilt, gentle cute cat smile (:3), fluffy white chest, neat front paws together. "
    "Row 1 Col 3 (top-right): SLEEPING BALL (side view facing RIGHT) — curled up flat and cozy on its belly fast asleep, eyes peacefully closed, fluffy ringed tail tucked neatly around body, zero Zzz text. "
    "Row 2 Col 1 (bottom-left): DANGLING SCRUFF CARRY — being gently lifted up by the scruff in mid-air, round chubby face looking cute and slightly surprised, all four soft paws dangling downward. "
    "Row 2 Col 2 (bottom-center): CALM LOAF (side view facing RIGHT) — lying flat in a cozy cat-loaf posture on its belly facing right, front paws tucked neatly under chin, big emerald eyes open calmly watching. "
    "Row 2 Col 3 (bottom-right): HOLDING TENNIS BALL (facing right/front) — sitting excitedly with a bright green-yellow pixel tennis ball held in its mouth/paws inviting the owner to play."
)

WESTIE_FLASH_STEP_PROMPT = (
    "Using the EXACT SAME fluffy white pixel-art Westie puppy from Image 1 (same white fur, STRICTLY TWO symmetrical pointed pink-lined ears, "
    "round black eyes, black nose, light-blue collar with silver tag, crisp dark pixel outline, 32-bit retro pixel art), "
    "recreate the EXACT 5-pose hilarious upright bipedal side-step dance ('闪身步') shown in Image 2! "
    "Create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO background room, generous transparent margin, IDENTICAL character height and ground baseline across all cells): "
    "Row 1 Col 1 (top-left): POSE 1 STANCE ('起势') — Westie standing upright on two hind legs facing camera, right front paw raised playfully outward to viewer's left, left front paw bent near chest, cheeky confident look (matching panel 1 of Image 2). "
    "Row 1 Col 2 (top-center): POSE 2 DODGE RIGHT ('往右闪') — Westie standing upright on two wide-planted hind legs leaning & sidestepping briskly to the RIGHT (viewer's right), head tilted slightly, front paws swinging rightward with swagger (matching panel 2 of Image 2). "
    "Row 1 Col 3 (top-right): POSE 3 STOP ('停') — Westie snapped straight upright facing camera at attention, hind legs neat and straight together, both white front paws hanging down cleanly in front of tummy, deadpan cute expression (matching panel 3 of Image 2). "
    "Row 2 Col 1 (bottom-left): POSE 4 READY ('准备') — Westie standing upright facing camera with hind legs widening slightly and tail flicked out to the side, poised to juke left, eyes focused forward (matching panel 4 of Image 2). "
    "Row 2 Col 2 (bottom-center): POSE 5 DODGE LEFT ('再往左闪') — Westie standing upright on wide-planted hind legs leaning & sidestepping briskly to the LEFT (viewer's left), front paws swinging leftward with cheeky swagger (matching panel 5 of Image 2). "
    "Row 2 Col 3 (bottom-right): HAPPY TA-DA FINISH — Westie standing upright facing camera with both little front paws raised cheerfully and tiny pink tongue smile."
)

CAT_FLASH_STEP_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same round golden-cream cheeks, "
    "grey-brown shading, sparkling emerald-green eyes, pink-brown nose, STRICTLY TWO rounded cat ears, ringed tail, NO hat, NO collar, crisp dark pixel outline, 32-bit retro pixel art), "
    "recreate the EXACT 5-pose hilarious upright bipedal side-step dance ('闪身步') shown in Image 2! "
    "Create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO background room, generous transparent margin, IDENTICAL character height and ground baseline across all cells): "
    "Row 1 Col 1 (top-left): POSE 1 STANCE ('起势') — chubby golden cat standing upright on two hind legs facing camera, one front paw raised playfully outward to viewer's left, other paw curled near chest, cheeky confident emerald eyes (matching panel 1 of Image 2). "
    "Row 1 Col 2 (top-center): POSE 2 DODGE RIGHT ('往右闪') — chubby golden cat standing upright on wide-planted hind legs leaning & sidestepping briskly to the RIGHT (viewer's right), torso shifted right, front paws swinging rightward with hilarious swagger (matching panel 2 of Image 2). "
    "Row 1 Col 3 (top-right): POSE 3 STOP ('停') — chubby golden cat snapped straight upright facing camera at attention, hind legs neat together, both front paws dangling adorably in front of its fluffy white belly, deadpan cute face (matching panel 3 of Image 2). "
    "Row 2 Col 1 (bottom-left): POSE 4 READY ('准备') — chubby golden cat standing upright facing camera with hind legs braced slightly wide and fluffy ringed tail flicked out to the side, coiled to juke left (matching panel 4 of Image 2). "
    "Row 2 Col 2 (bottom-center): POSE 5 DODGE LEFT ('再往左闪') — chubby golden cat standing upright on wide-planted hind legs leaning & sidestepping briskly to the LEFT (viewer's left), torso shifted left, front paws swinging leftward with swagger (matching panel 5 of Image 2). "
    "Row 2 Col 3 (bottom-right): HAPPY TA-DA FINISH — chubby golden cat standing upright facing camera with both paws raised proudly and cute :3 smile."
)

CAT_PEEK_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same round golden-cream cheeks, "
    "grey-brown shading, sparkling emerald-green eyes, pink-brown nose, STRICTLY TWO cat ears, NO hat, NO collar, crisp dark pixel outline, 32-bit retro pixel art), "
    "create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): EDGE PEEK CALM — the chubby golden cat hiding behind an invisible vertical wall on the right side of this cell, ONLY its round head, two ears, and two chubby cream front paws gripping the straight vertical right edge are visible, peeking LEFTWARD calmly (no wall drawn). "
    "Row 1 Col 2 (top-center): EDGE PEEK HOVER — same vertical right-edge peeking pose looking LEFTWARD, leaning out slightly further with happy bright emerald eyes, cute :3 smile, and one chubby front paw raised in a gentle hello wave (cut cleanly along straight vertical right edge, no wall drawn). "
    "Row 1 Col 3 (top-right): BIG HEAD LEDGE PEEK ('大头趴窗盯镜头') — close-up front view of the chubby golden cat's super round adorable head and two fluffy front paws resting cleanly on an invisible flat horizontal bottom line, staring right at the viewer with big curious emerald eyes. "
    "Row 2 Col 1 (bottom-left): MENU BAR BADGE ICON — clean crisp iconic square pixel-art head portrait of this golden shaded cat with a tiny green tennis ball beside its cheek, bold dark outline, readable at 18x18px. "
    "Row 2 Col 2 (bottom-center): EXTRA CALM SIT — chubby golden cat sitting front-facing neatly with calm expression. "
    "Row 2 Col 3 (bottom-right): EXTRA SLEEPY BALL — chubby golden cat curled neatly asleep."
)

CAT_WALK_CYCLE_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same golden-cream and grey-brown shaded fur, "
    "sparkling emerald-green eyes, STRICTLY TWO rounded cat ears, thick ringed tail, NO hat, NO collar, crisp dark pixel outline, 32-bit retro pixel art), "
    "create a 1024x1024 transparent-background 4-frame SIDE-PROFILE WALK CYCLE sprite sheet in a strict 2 columns by 2 rows grid "
    "(4 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin). "
    "ALL 4 frames MUST face strictly RIGHT in clean side-profile with IDENTICAL head size, body length, and ground baseline, "
    "with CLEAR dark pixel outlines separating all four legs so the legs stepping forward and backward are unmistakably readable even at 66px! "
    "Row 1 Col 1 (top-left): WALK FRAME 1 (WIDE STRIDE A) — front-right leg reaching clearly FORWARD, front-left leg angled BACKWARD, back-left leg forward under belly, back-right leg pushing backward (clear scissors gap!). "
    "Row 1 Col 2 (top-right): WALK FRAME 2 (PASSING A) — front-right leg planted straight down, front-left paw lifted bent forward off the ground, hind legs passing close underneath, ringed tail swaying up. "
    "Row 2 Col 1 (bottom-left): WALK FRAME 3 (WIDE STRIDE B, OPPOSITE) — front-left leg reaching clearly FORWARD, front-right leg angled BACKWARD, back-right leg forward under belly, back-left leg pushing backward (opposite scissors gap!). "
    "Row 2 Col 2 (bottom-right): WALK FRAME 4 (PASSING B) — front-left leg planted straight down, front-right paw lifted bent forward off the ground, hind legs passing close underneath, tail slightly lower."
)

CAT_CLIMB_YAWN_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same round golden-cream cheeks, "
    "grey-brown back shading, emerald-green eyes, STRICTLY TWO rounded cat ears — NEVER three ears, ringed tail, NO hat, NO collar, crisp dark pixel outline, 32-bit retro pixel art), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO Zzz, generous transparent margin): "
    "Row 1 Col 1 (top-left): TOP PEEK CENTER — only the chubby golden cat's cute round head, two ears, and two white-cream front paws resting cleanly on a flat invisible horizontal bottom line, looking straight forward curiously. "
    "Row 1 Col 2 (top-center): TOP PEEK LEFT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing LEFT curiously. "
    "Row 1 Col 3 (top-right): TOP PEEK RIGHT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing RIGHT curiously. "
    "Row 2 Col 1 (bottom-left): CLIMBING UP OVER LEDGE — mid-climb pose facing right: chubby golden cat pulling its body up onto the flat horizontal floor, front paws planted forward, hind legs scrambling up, STRICTLY TWO ears. "
    "Row 2 Col 2 (bottom-center): BIG CUTE YAWN — full-body chubby golden cat in side-3/4 view facing RIGHT, sitting slightly hunched with eyes tightly squinted in a sleepy happy curve, mouth open wide showing a cute little pink yawn, ears relaxed back. "
    "Row 2 Col 3 (bottom-right): DROWSY HALF-ASLEEP LOAF — full-body chubby golden cat lying low and flat on its belly facing RIGHT (matching the exact compact loaf silhouette of sleeping pose), chin lowering onto front paws, eyelids heavy and half-closed just before falling asleep."
)

CAT_HOP_LOOK_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same golden-cream and grey-brown shaded fur, "
    "emerald-green eyes, STRICTLY TWO rounded cat ears — NEVER three ears, fluffy ringed tail, NO hat, NO collar, crisp dark pixel outline, 32-bit retro pixel art), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "ROW 1 (3-frame joyful bouncy cat hop/pounce cycle in clean side-profile facing RIGHT): "
    "Row 1 Col 1 (top-left): HOP CROUCH (facing RIGHT) — playful pounce crouch before leaping: chest lowered, front paws bent low, hind legs coiled ready to spring, ringed tail raised high. "
    "Row 1 Col 2 (top-center): HOP MID-AIR LEAP (facing RIGHT) — authentic joyful mid-air kitty bound: body stretched in a lively airborne arc, both front paws reaching forward-up, both hind legs extended backward-down with clear air under belly. "
    "Row 1 Col 3 (top-right): HOP LANDING (facing RIGHT) — soft front-paw landing cushion, front paws touching down forward absorbing the jump, hind legs trailing slightly behind. "
    "ROW 2 (Stationary standing body facing LEFT — ALL THREE CELLS in Row 2 MUST have the EXACT SAME stationary standing body, ringed tail, and 4 planted paws facing LEFT, ONLY the cat's round head turns!): "
    "Row 2 Col 1 (bottom-left): STANDING FACING LEFT, HEAD LOOKING LEFT — golden cat standing quietly side-profile facing LEFT, all 4 paws planted steadily, head peering curiously LEFT. "
    "Row 2 Col 2 (bottom-center): STANDING FACING LEFT, HEAD LOOKING CENTER — IDENTICAL stationary body, ringed tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the round head is turned toward the front viewer curiously. "
    "Row 2 Col 3 (bottom-right): STANDING FACING LEFT, HEAD LOOKING RIGHT — IDENTICAL stationary body, ringed tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the round head is turned back over the shoulder peering curiously RIGHT!"
)

CAT_TENNIS_PROMPT = (
    "Using the EXACT SAME chubby Golden Shaded British Shorthair pixel-art cat from Image 1 (same round golden-cream cheeks, "
    "grey-brown shading, emerald-green eyes, STRICTLY TWO rounded cat ears, ringed tail, crisp dark pixel outline, 32-bit GBA Mario Tennis pixel art), "
    "wearing a tiny sporty red-and-white sweatband around its wrist/forehead and holding a tiny classic wooden/green pixel tennis racket, "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): TENNIS READY — facing downward toward the player, athletic ready stance gripping mini tennis racket, determined cute emerald eyes. "
    "Row 1 Col 2 (top-center): TENNIS RUN — sprinting sideways to chase a tennis ball, paws stretched running, racket held out ready. "
    "Row 1 Col 3 (top-right): TENNIS SWING — dynamic forehand racket follow-through swing hitting a shot forward, energetic cute expression. "
    "Row 2 Col 1 (bottom-left): TENNIS DIVE — dramatic horizontal full-stretch diving save reaching out with racket extended! "
    "Row 2 Col 2 (bottom-center): VICTORY CELEBRATION — jumping joyfully with both paws and racket raised high in victory, super happy sparkling smile! "
    "Row 2 Col 3 (bottom-right): HOLDING BALL — sitting holding a bright neon-green tennis ball proudly."
)


def slice_and_save_all(raw_dir: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Westie Flash Step (5 frames locked to identical scale!)
    wf_sheet = Image.open(raw_dir / "westie_flash_step_sheet.png").convert("RGBA")
    cw, rh = wf_sheet.width // 3, wf_sheet.height // 2
    ref_scale: float | None = None
    for col, row, name in [
        (0, 0, "westie_flash_step_1"),
        (1, 0, "westie_flash_step_2"),
        (2, 0, "westie_flash_step_3"),
        (0, 1, "westie_flash_step_4"),
        (1, 1, "westie_flash_step_5"),
    ]:
        cell = wf_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=ref_scale)
        if ref_scale is None:
            ref_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 2. Cat Companion Core
    cc_sheet = Image.open(raw_dir / "cat_companion_sheet.png").convert("RGBA")
    cw, rh = cc_sheet.width // 3, cc_sheet.height // 2
    for col, row, name, balign in [
        (0, 0, "cat_idle", True),
        (1, 0, "cat_sit_tilt", True),
        (2, 0, "cat_sleep", True),
        (0, 1, "cat_dangling", False),
        (1, 1, "cat_loaf_calm", True),
        (2, 1, "cat_holding_ball", True),
    ]:
        cell = cc_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 3. Cat Peek & Badge
    cp_sheet = Image.open(raw_dir / "cat_peek_sheet.png").convert("RGBA")
    cw, rh = cp_sheet.width // 3, cp_sheet.height // 2
    normalize_right_edge_peek(cp_sheet.crop((0, 0, cw, rh)), canvas_size=128).save(out_dir / "cat_peek_calm.png")
    print("[SPRITE] Saved cat_peek_calm.png (flush-right)", flush=True)
    normalize_right_edge_peek(cp_sheet.crop((cw, 0, 2 * cw, rh)), canvas_size=128).save(out_dir / "cat_peek_hover.png")
    print("[SPRITE] Saved cat_peek_hover.png (flush-right)", flush=True)
    spr, _ = clean_and_normalize_sprite(cp_sheet.crop((2 * cw, 0, 3 * cw, rh)), canvas_size=128, bottom_align=True)
    spr.save(out_dir / "cat_chin_ledge.png")
    print("[SPRITE] Saved cat_chin_ledge.png", flush=True)
    badge, _ = clean_and_normalize_sprite(cp_sheet.crop((0, rh, cw, 2 * rh)), canvas_size=128, bottom_align=False)
    badge.save(out_dir / "cat_badge_icon.png")
    print("[SPRITE] Saved cat_badge_icon.png", flush=True)

    # 4. Cat 4-Frame Walk Cycle
    cw_sheet = Image.open(raw_dir / "cat_walk_cycle_4f_sheet.png").convert("RGBA")
    cw2, rh2 = cw_sheet.width // 2, cw_sheet.height // 2
    walk_ref: float | None = None
    for col, row, name in [
        (0, 0, "cat_walk_1"),
        (1, 0, "cat_walk_2"),
        (0, 1, "cat_walk_3"),
        (1, 1, "cat_walk_4"),
    ]:
        cell = cw_sheet.crop((col * cw2, row * rh2, (col + 1) * cw2, (row + 1) * rh2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=walk_ref)
        if walk_ref is None:
            walk_ref = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 5. Cat Climb, Look & Yawn
    cy_sheet = Image.open(raw_dir / "cat_climb_yawn_sheet.png").convert("RGBA")
    cw, rh = cy_sheet.width // 3, cy_sheet.height // 2
    peek_ref: float | None = None
    for col, row, name in [
        (0, 0, "cat_top_peek_center"),
        (1, 0, "cat_top_peek_left"),
        (2, 0, "cat_top_peek_right"),
    ]:
        cell = cy_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=peek_ref)
        if peek_ref is None:
            peek_ref = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    for col, row, name in [
        (0, 1, "cat_climb_up"),
        (1, 1, "cat_yawn"),
        (2, 1, "cat_drowsy"),
    ]:
        cell = cy_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 6. Cat Hop & Stationary-Body Look
    ch_sheet = Image.open(raw_dir / "cat_hop_look_sheet.png").convert("RGBA")
    cw, rh = ch_sheet.width // 3, ch_sheet.height // 2
    hop_ref: float | None = None
    for col, row, name in [(0, 0, "cat_hop_crouch"), (1, 0, "cat_hop_air"), (2, 0, "cat_hop_land")]:
        cell = ch_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=hop_ref)
        if hop_ref is None:
            hop_ref = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    look_ref: float | None = None
    for col, row, name in [
        (0, 1, "cat_look_left_head_left"),
        (1, 1, "cat_look_left_head_center"),
        (2, 1, "cat_look_left_head_right"),
    ]:
        cell = ch_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=look_ref)
        if look_ref is None:
            look_ref = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 7. Cat Tennis
    ct_sheet = Image.open(raw_dir / "cat_tennis_sheet.png").convert("RGBA")
    cw, rh = ct_sheet.width // 3, ct_sheet.height // 2
    for col, row, name, balign in [
        (0, 0, "cat_tennis_ready", True),
        (1, 0, "cat_tennis_run", True),
        (2, 0, "cat_tennis_swing", True),
        (0, 1, "cat_tennis_dive", False),
        (1, 1, "cat_victory", True),
    ]:
        cell = ct_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 8. Cat Flash Step (5 frames locked to identical scale!)
    cf_sheet = Image.open(raw_dir / "cat_flash_step_sheet.png").convert("RGBA")
    cw, rh = cf_sheet.width // 3, cf_sheet.height // 2
    cf_ref: float | None = None
    for col, row, name in [
        (0, 0, "cat_flash_step_1"),
        (1, 0, "cat_flash_step_2"),
        (2, 0, "cat_flash_step_3"),
        (0, 1, "cat_flash_step_4"),
        (1, 1, "cat_flash_step_5"),
    ]:
        cell = cf_sheet.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=cf_ref)
        if cf_ref is None:
            cf_ref = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-ini", required=True)
    parser.add_argument("--cat-photo", required=True)
    parser.add_argument("--flash-ref", required=True)
    parser.add_argument("--raw-dir", default=str(Path(__file__).resolve().parent.parent / "assets_raw"))
    parser.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent / "Sources" / "WestieDeskPet" / "Resources" / "Sprites"),
    )
    args = parser.parse_args()

    endpoint, api_key = load_api_key(args.config_ini)
    raw_dir = Path(args.raw_dir)
    out_dir = Path(args.out_dir)

    clean_cat_photo = prepare_clean_cat_photo(Path(args.cat_photo), raw_dir / "cat_photo_clean_ref.png")
    flash_ref = Path(args.flash_ref)
    westie_sheet_ref = raw_dir / "westie_companion_sheet.png"
    westie_sit_ref = out_dir / "westie_sit_tilt.png"

    cat_core_sheet = raw_dir / "cat_companion_sheet.png"
    westie_flash_sheet = raw_dir / "westie_flash_step_sheet.png"

    print("=== Phase 1: Generating Cat Core Sheet + Westie Flash-Step Sheet in parallel ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(
            edit_image_multi_ref,
            endpoint, api_key, FLARE_DEPLOYMENT,
            [clean_cat_photo, westie_sheet_ref],
            CAT_COMPANION_PROMPT,
            cat_core_sheet,
            "1536x1024", "high",
        )
        f2 = pool.submit(
            edit_image_multi_ref,
            endpoint, api_key, SUNBURST_DEPLOYMENT,
            [westie_sit_ref, flash_ref],
            WESTIE_FLASH_STEP_PROMPT,
            westie_flash_sheet,
            "1536x1024", "high",
        )
        f1.result()
        f2.result()

    print("=== Phase 2: Generating remaining 6 Golden Cat sheets in parallel (Flare + Sunburst) ===", flush=True)
    phase2_jobs = [
        (FLARE_DEPLOYMENT, [cat_core_sheet], CAT_PEEK_PROMPT, raw_dir / "cat_peek_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [cat_core_sheet], CAT_WALK_CYCLE_PROMPT, raw_dir / "cat_walk_cycle_4f_sheet.png", "1024x1024"),
        (FLARE_DEPLOYMENT, [cat_core_sheet], CAT_CLIMB_YAWN_PROMPT, raw_dir / "cat_climb_yawn_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [cat_core_sheet], CAT_HOP_LOOK_PROMPT, raw_dir / "cat_hop_look_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [cat_core_sheet], CAT_TENNIS_PROMPT, raw_dir / "cat_tennis_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [cat_core_sheet, flash_ref], CAT_FLASH_STEP_PROMPT, raw_dir / "cat_flash_step_sheet.png", "1536x1024"),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futs = [
            pool.submit(edit_image_multi_ref, endpoint, api_key, dep, refs, prompt, out_p, sz, "high")
            for (dep, refs, prompt, out_p, sz) in phase2_jobs
        ]
        for fut in futs:
            fut.result()

    print("=== Phase 3: Slicing & normalizing all 41 new sprites ===", flush=True)
    slice_and_save_all(raw_dir, out_dir)
    print("=== ALL DONE! ===", flush=True)


if __name__ == "__main__":
    main()
