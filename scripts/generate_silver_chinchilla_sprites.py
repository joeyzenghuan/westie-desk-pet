#!/usr/bin/env python3
"""
Generate 100% full-parity pixel-art sprite suite (67 transparent PNGs, prefix `chinchilla2_`)
for the 5th pet option: Friend's Real Silver-White Chinchilla Persian Cat (`❄️ 银白金吉拉`),
strictly matching `assets_raw/friend_chinchilla_reference.png`:

SIGNATURE TRAITS (MUST BE PRESERVED IN EVERY SINGLE SPRITE):
- EARS: ZERO PINK INSIDE THE EARS!! Pure snowy-white and soft cool silver-grey ears ONLY,
  with prominent LONG WISPY SNOWY-WHITE EAR FURNISHING TUFTS (长白耳毛) brushing right across
  the front of each ear opening! STRICTLY TWO symmetrical cat ears (NEVER three ears, NEVER pink inner ear!).
- EYES: Large expressive ICY SEAFOAM-AQUA / PALE BLUE-GREEN eyes framed by DRAMATIC CRISP BLACK
  "CAT-EYE" EYELINER rims (slightly regal/cool noble gaze, NOT plain dark green!).
- NOSE: Cute warm TERRACOTTA / PEACH-TAN button nose neatly outlined in thin crisp black liner.
- COAT: Ultra-long, flowing, silky PURE SNOWY-WHITE fur with huge majestic fluffy white mane/ruff,
  faint cool silver-grey forehead wisps & soft ash-grey shading on lower flanks/back, and a grand
  flowing snowy-white plume tail with subtle silver-grey feathering (NO collar, NO hat!).

Phase 1 (anchor): `chinchilla2_companion_sheet.png` -> idle, sit_tilt, sleep, dangling (WITH human hand!), loaf_calm, holding_ball
Phase 2 (10 sheets concurrently, max_workers=4 across Flare + Sunburst):
  - chinchilla2_peek_sheet.png          -> peek_calm, peek_hover, chin_ledge, badge_icon, eat_1 (dried fish), eat_2
  - chinchilla2_walk_cycle_4f_sheet.png -> walk_1..4
  - chinchilla2_climb_yawn_sheet.png    -> top_peek_center/left/right, climb_up, yawn, drowsy
  - chinchilla2_hop_look_sheet.png      -> hop_crouch/air/land, look_left_head_left/center/right
  - chinchilla2_tennis_sheet.png        -> tennis_ready/run/swing/dive, victory
  - chinchilla2_flash_step_8f_sheet.png -> flash_step_1..8 (192x128 height-locked)
  - chinchilla2_bear_shake_8f_sheet.png -> bear_shake_1..8 (192x128 height-locked)
  - chinchilla2_wanderer_kick_6f_sheet.png -> wanderer_kick_1..6 (192x128 height-locked)
  - chinchilla2_head_tilt_6f_sheet.png  -> head_tilt_1..6 (128x128 height-locked)
  - chinchilla2_belly_roll_6f_sheet.png -> belly_roll_1..6 (128x128, pose-locked to QA-passed cat_belly_roll_1..6!)
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
from generate_chinchilla_sprites import build_cat_belly_roll_ref_grid
from generate_flash_step_v2 import make_prompt as make_flash_step_prompt
from generate_flash_step_v2 import slice_4x2_height_locked
from generate_head_tilt_and_fixes import make_head_tilt_prompt
from generate_new_effects_sprites import (
    make_bear_shake_prompt,
    make_wanderer_kick_prompt,
    slice_grid_height_locked,
)
from generate_peek_sprites import normalize_right_edge_peek
from process_sprites import clean_and_normalize_sprite


CHIN2_DESC = (
    "the EXACT regal long-haired snowy-white Silver Chinchilla Persian cat from Image 1 (银白金吉拉): "
    "PURE SNOWY-WHITE silky long flowing fur with a big fluffy white chest mane and soft cool silver-grey shading on the lower flanks and subtle crown wisps, "
    "CRITICAL EAR RULE: STRICTLY TWO cat ears that are PURE WHITE AND SOFT SILVER-GREY WITH ZERO PINK INSIDE THE EARS (NEVER draw pink inner ear triangles!), "
    "with prominent LONG WISPY SNOWY-WHITE FUR TUFTS (ear furnishings) sticking out right in front of the ear openings covering the front of the ears! "
    "CRITICAL EYE & NOSE RULE: Large expressive ICY SEAFOAM-AQUA / PALE BLUE-GREEN eyes outlined with crisp dramatic BLACK CAT-EYE EYELINER, "
    "tiny warm TERRACOTTA / PEACH-TAN button nose neatly rimmed with a thin black outline, delicate white muzzle, "
    "luxurious long flowing white-and-silver plume tail, NO collar, NO hat, crisp dark pixel outline, "
    "32-bit retro pixel art matching the exact aesthetic of a desktop pet (NO anti-aliasing blur, NO drop shadows)"
)

CHIN2_COMPANION_PROMPT = (
    f"Transform the real snowy-white Silver Chinchilla cat shown in the 3-panel photo in Image 1 into {CHIN2_DESC}, "
    "strictly matching the 32-bit pixel art line weight, shading style, and chibi desktop-pet proportions of Image 2 and the human scruff-carry hand of Image 3. "
    "Create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO boxes, NO text, NO drop shadows, generous transparent margin). "
    "REMINDER: ZERO PINK INSIDE THE EARS in ANY cell — ears are white/soft cool-grey with LONG WISPY WHITE EAR TUFTS in front of the ears, ICY PALE BLUE-GREEN BLACK-LINED EYES, terracotta black-rimmed nose! "
    "Row 1 Col 1 (top-left): IDLE STANDING (side-profile facing RIGHT) — silky long-haired snowy-white Chinchilla standing neatly on four paws, huge flowing white mane, soft cool-grey lower flank shading, icy aqua eyeliner eyes alert, grand fluffy white-silver plume tail curled up. "
    "Row 1 Col 2 (top-center): CALM SITTING SMILE (front-facing 3/4) — regal fluffy snowy-white Chinchilla sitting neatly facing camera with slight curious head tilt, white wispy tufts across front of white/grey ears (NO pink ears!), sparkling icy blue-green black-lined eyes, terracotta black-rimmed nose, fluffy white chest mane. "
    "Row 1 Col 3 (top-right): SLEEPING CLOUD BALL (side view facing RIGHT) — curled up flat and cozy on its belly fast asleep like a snowy white cloud, eyes peacefully closed, huge fluffy plume tail wrapped around body, zero Zzz text. "
    "Row 2 Col 1 (bottom-left): DANGLING SCRUFF CARRY (WITH HUMAN HAND!) — matching Image 3's exact cute cartoon pixel-art HUMAN HAND coming from above gently pinching the fluffy scruff behind the cat's neck so the snowy-white Chinchilla dangles helplessly in mid-air with wide cute icy-aqua eyes, wispy white ear tufts (NO pink ears!), and four fluffy paws dangling down! "
    "Row 2 Col 2 (bottom-center): CALM LOAF (side view facing RIGHT) — lying flat in a super fluffy snowy-white cat-loaf posture facing right, paws tucked under big white neck ruff, icy blue-green eyeliner eyes calmly watching. "
    "Row 2 Col 3 (bottom-right): HOLDING TENNIS BALL (facing right/front) — sitting excitedly holding a bright green-yellow pixel tennis ball inviting the owner to play!"
)

CHIN2_PEEK_AND_EAT_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/cool-grey ears with wispy long white fur tufts across the front of the ears!) and icy pale blue-green black-eyeliner eyes in ALL 6 cells! "
    "Create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): EDGE PEEK CALM — hiding behind an invisible vertical wall on the RIGHT edge of this cell, ONLY its snowy-white fluffy head, white/silver-grey ears with long white front tufts (NO pink!), icy blue-green eyeliner eyes, terracotta black-rimmed nose, and two fluffy white paws gripping the straight vertical right edge are visible peeking LEFTWARD calmly. "
    "Row 1 Col 2 (top-center): EDGE PEEK HOVER — same vertical right-edge peeking pose looking LEFTWARD, leaning out slightly further with bright icy-aqua eyes, sweet smile, and one fluffy white paw raised in a gentle hello wave. "
    "Row 1 Col 3 (top-right): BIG HEAD LEDGE PEEK — close-up front view of its silky snowy-white head, wispy white ear tufts across non-pink white/grey ears, icy blue-green eyeliner eyes, and two fluffy paws resting cleanly on an invisible flat horizontal bottom line staring right at viewer. "
    "Row 2 Col 1 (bottom-left): MENU BAR BADGE ICON — crisp iconic square pixel-art head portrait of this snowy-white Chinchilla with non-pink white/silver tufted ears, icy blue-green black-lined eyes, and a tiny green tennis ball beside its fluffy cheek, bold dark outline. "
    "Row 2 Col 2 (bottom-center): EATING DRIED FISH FRAME 1 (CRUNCH) — matching Image 2's golden-brown DRIED FISH snack, sitting side-3/4 facing RIGHT happily chomping down on a golden dried fish held between its white paws! "
    "Row 2 Col 3 (bottom-right): EATING DRIED FISH FRAME 2 (BLISSFUL CHEW) — IDENTICAL sitting body & dried fish position as Row 2 Col 2, eyes closed in super happy '^ ^' arcs chewing blissfully!"
)

CHIN2_WALK_CYCLE_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/silver-grey ears with wispy white front tufts!) and icy aqua eyeliner eyes! "
    "Create a 1024x1024 transparent-background 4-frame SIDE-PROFILE WALK CYCLE sprite sheet in a strict 2 columns by 2 rows grid "
    "(4 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin). "
    "ALL 4 frames MUST face strictly RIGHT in clean side-profile with IDENTICAL head size, fluffy body length, and ground baseline, "
    "with CLEAR dark pixel outlines separating all four white paws: "
    "Row 1 Col 1: WALK FRAME 1 (WIDE STRIDE A) — front-right paw reaching FORWARD, front-left BACKWARD, back-left forward, back-right pushing backward. "
    "Row 1 Col 2: WALK FRAME 2 (PASSING A) — front-right planted straight down, front-left paw lifted bent forward, hind paws passing underneath, grand fluffy white plume tail swaying up. "
    "Row 2 Col 1: WALK FRAME 3 (WIDE STRIDE B, OPPOSITE) — front-left paw reaching FORWARD, front-right BACKWARD, back-right forward, back-left pushing backward. "
    "Row 2 Col 2: WALK FRAME 4 (PASSING B) — front-left planted straight down, front-right paw lifted bent forward, hind paws passing underneath, plume tail slightly lower."
)

CHIN2_CLIMB_YAWN_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/cool-grey ears with long wispy white fur tufts right in front of the ears!) and icy pale blue-green black-eyeliner eyes in ALL 6 cells! "
    "Create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO Zzz, generous transparent margin): "
    "Row 1 Col 1: TOP PEEK CENTER — only its snowy-white fluffy head, non-pink white/silver tufted ears, icy blue-green eyeliner eyes, and two fluffy white paws resting cleanly on a flat horizontal bottom line looking straight forward. "
    "Row 1 Col 2: TOP PEEK LEFT — IDENTICAL top-edge peeking head and two paws in same position & scale, head turned glancing LEFT. "
    "Row 1 Col 3: TOP PEEK RIGHT — IDENTICAL top-edge peeking head and two paws in same position & scale, head turned glancing RIGHT. "
    "Row 2 Col 1: CLIMBING UP OVER LEDGE — mid-climb facing right pulling its fluffy snowy-white body up onto flat floor. "
    "Row 2 Col 2: BIG CUTE YAWN — side-3/4 facing RIGHT sitting slightly hunched, eyes squinted happily, mouth open wide in a cute yawn. "
    "Row 2 Col 3: DROWSY HALF-ASLEEP LOAF — lying low and flat on belly facing RIGHT, chin resting on fluffy paws, heavy half-closed icy-aqua eyelids."
)

CHIN2_HOP_LOOK_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/cool-grey ears with wispy white front tufts!) and icy aqua eyeliner eyes! "
    "Create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "ROW 1 (3-frame joyful bouncy kitty hop cycle in clean side-profile facing RIGHT): "
    "Row 1 Col 1: HOP CROUCH (facing RIGHT) — playful crouch, fluffy chest lowered, hind legs coiled, silky white plume tail raised high. "
    "Row 1 Col 2: HOP MID-AIR LEAP (facing RIGHT) — joyful mid-air snowy-white kitty bound, body stretched in arc, clear air under belly. "
    "Row 1 Col 3: HOP LANDING (facing RIGHT) — soft front-paw landing cushion, hind legs trailing slightly behind. "
    "ROW 2 (Stationary standing body facing LEFT — ALL THREE CELLS MUST have IDENTICAL stationary body, plume tail & 4 planted paws facing LEFT, ONLY the head turns!): "
    "Row 2 Col 1: STANDING FACING LEFT, HEAD LOOKING LEFT. "
    "Row 2 Col 2: STANDING FACING LEFT, HEAD LOOKING CENTER (toward viewer). "
    "Row 2 Col 3: STANDING FACING LEFT, HEAD LOOKING RIGHT (back over shoulder)."
)

CHIN2_TENNIS_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/cool-grey tufted ears!) and icy blue-green eyeliner eyes, "
    "wearing a tiny sporty ice-blue-and-white sweatband and holding a tiny classic wooden/green pixel tennis racket, "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1: TENNIS READY — facing downward toward player, athletic ready stance gripping racket. "
    "Row 1 Col 2: TENNIS RUN — sprinting sideways chasing ball, fluffy plume tail streaming. "
    "Row 1 Col 3: TENNIS SWING — dynamic forehand racket follow-through swing hitting shot forward. "
    "Row 2 Col 1: TENNIS DIVE — dramatic horizontal diving save with entire racket unclipped inside margin! "
    "Row 2 Col 2: VICTORY CELEBRATION — jumping joyfully with both paws and racket raised high in victory! "
    "Row 2 Col 3: EXTRA HOLDING BALL — sitting holding bright neon-green tennis ball proudly."
)

CHIN2_BELLY_ROLL_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art snowy-white Silver Chinchilla cat from Image 1 ({CHIN2_DESC}), "
    "STRICTLY ZERO PINK INSIDE THE EARS (white/cool-grey ears with long wispy white front tufts!) and icy blue-green black-eyeliner eyes, "
    "faithfully transfer ALL 6 EXACT 4-PAW BELLY-UP ROLL-OVER POSES shown in the 3-column by 2-row pixel-art cat reference grid in Image 2! "
    "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin). "
    "CRITICAL ANATOMY LOCK: COUNT EVERY PAW IN CELLS 2, 3, 4, 5, 6 — EVERY SINGLE ONE OF CELLS 2..6 MUST HAVE EXACTLY FOUR (4) CLEAR SEPARATE PAWS (2 front + 2 hind — NEVER 3 paws, NEVER 5 paws!) AND THE FLUFFY WHITE-SILVER PLUME TAIL, AND ZERO PINK INSIDE THE EARS! "
    "Row 1 Col 1: Low side-flop entry/exit matching Image 2 R1C1. "
    "Row 1 Col 2: Belly-up waiting Pose A matching Image 2 R1C2 (EXACTLY 4 paws + plume tail!). "
    "Row 1 Col 3: Belly-up waiting Pose B happy grin matching Image 2 R1C3 (EXACTLY 4 paws + plume tail!). "
    "Row 2 Col 1: Roll-in wind-up matching Image 2 R2C1 (EXACTLY 4 paws + plume tail!). "
    "Row 2 Col 2: Supine dead-center apex matching Image 2 R2C2 (belly straight up, upside-down grinning face, EXACTLY 4 symmetric paws up + plume tail!). "
    "Row 2 Col 3: Roll-out quarter-tilt matching Image 2 R2C3 (EXACTLY 4 paws + plume tail!)."
)


def slice_base_sheet(raw_dir: Path, out_dir: Path) -> None:
    cc = Image.open(raw_dir / "chinchilla2_companion_sheet.png").convert("RGBA")
    cw, rh = cc.width // 3, cc.height // 2
    for col, row, name, balign in [
        (0, 0, "chinchilla2_idle", True),
        (1, 0, "chinchilla2_sit_tilt", True),
        (2, 0, "chinchilla2_sleep", True),
        (0, 1, "chinchilla2_dangling", False),
        (1, 1, "chinchilla2_loaf_calm", True),
        (2, 1, "chinchilla2_holding_ball", True),
    ]:
        cell = cc.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)


def slice_wave2_sheets(raw_dir: Path, out_dir: Path) -> None:
    pk = Image.open(raw_dir / "chinchilla2_peek_sheet.png").convert("RGBA")
    cw, rh = pk.width // 3, pk.height // 2
    for col, row, name in [(0, 0, "chinchilla2_peek_calm"), (1, 0, "chinchilla2_peek_hover")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        normalize_right_edge_peek(cell, canvas_size=128).save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (flush right-edge peek)", flush=True)
    for col, row, name, balign in [(2, 0, "chinchilla2_chin_ledge", True), (0, 1, "chinchilla2_badge_icon", False)]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, _ = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png", flush=True)
    eat_scale: float | None = None
    for col, row, name in [(1, 1, "chinchilla2_eat_1"), (2, 1, "chinchilla2_eat_2")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=eat_scale)
        if eat_scale is None:
            eat_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    slice_grid_height_locked(raw_dir / "chinchilla2_walk_cycle_4f_sheet.png", 2, 2, 128, 128, "chinchilla2_walk", out_dir, ref_cell_idx=0)

    cy = Image.open(raw_dir / "chinchilla2_climb_yawn_sheet.png").convert("RGBA")
    cw, rh = cy.width // 3, cy.height // 2
    p_sc: float | None = None
    for col, name in [(0, "chinchilla2_top_peek_center"), (1, "chinchilla2_top_peek_left"), (2, "chinchilla2_top_peek_right")]:
        cell = cy.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=p_sc)
        if p_sc is None:
            p_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    for col, name in [(0, "chinchilla2_climb_up"), (1, "chinchilla2_yawn"), (2, "chinchilla2_drowsy")]:
        cell = cy.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    hl = Image.open(raw_dir / "chinchilla2_hop_look_sheet.png").convert("RGBA")
    cw, rh = hl.width // 3, hl.height // 2
    h_sc: float | None = None
    for col, name in [(0, "chinchilla2_hop_crouch"), (1, "chinchilla2_hop_air"), (2, "chinchilla2_hop_land")]:
        cell = hl.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=h_sc)
        if h_sc is None:
            h_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    l_sc: float | None = None
    for col, name in [(0, "chinchilla2_look_left_head_left"), (1, "chinchilla2_look_left_head_center"), (2, "chinchilla2_look_left_head_right")]:
        cell = hl.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=l_sc)
        if l_sc is None:
            l_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    tn = Image.open(raw_dir / "chinchilla2_tennis_sheet.png").convert("RGBA")
    cw, rh = tn.width // 3, tn.height // 2
    for col, row, name in [
        (0, 0, "chinchilla2_tennis_ready"),
        (1, 0, "chinchilla2_tennis_run"),
        (2, 0, "chinchilla2_tennis_swing"),
        (0, 1, "chinchilla2_tennis_dive"),
        (1, 1, "chinchilla2_victory"),
    ]:
        cell = tn.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    slice_4x2_height_locked(raw_dir / "chinchilla2_flash_step_8f_sheet.png", "chinchilla2", out_dir)
    slice_grid_height_locked(raw_dir / "chinchilla2_bear_shake_8f_sheet.png", 4, 2, 192, 128, "chinchilla2_bear_shake", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla2_wanderer_kick_6f_sheet.png", 3, 2, 192, 128, "chinchilla2_wanderer_kick", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla2_head_tilt_6f_sheet.png", 3, 2, 128, 128, "chinchilla2_head_tilt", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla2_belly_roll_6f_sheet.png", 3, 2, 128, 128, "chinchilla2_belly_roll", out_dir, ref_cell_idx=1)


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

    photo_ref = raw_dir / "friend_chinchilla_reference.png"
    comp_sheet = raw_dir / "chinchilla2_companion_sheet.png"
    if args.force:
        comp_sheet.unlink(missing_ok=True)

    print("=== Phase 1: Generating Friend's Silver-White Chinchilla anchor (`chinchilla2_companion_sheet.png`) ===", flush=True)
    edit_image_multi_ref(
        endpoint, api_key, FLARE_DEPLOYMENT,
        [photo_ref, out_dir / "chinchilla_sit_tilt.png", out_dir / "westie_dangling.png"],
        CHIN2_COMPANION_PROMPT, comp_sheet, "1536x1024", "high",
    )
    slice_base_sheet(raw_dir, out_dir)

    cat_belly_ref = raw_dir / "cat_belly_roll_verified_6f_ref.png"
    if not cat_belly_ref.exists():
        build_cat_belly_roll_ref_grid(out_dir, cat_belly_ref)

    anchor = out_dir / "chinchilla2_sit_tilt.png"
    jobs = [
        (FLARE_DEPLOYMENT, [anchor, out_dir / "dried_fish_treat.png", photo_ref], CHIN2_PEEK_AND_EAT_PROMPT, raw_dir / "chinchilla2_peek_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "chinchilla2_idle.png"], CHIN2_WALK_CYCLE_PROMPT, raw_dir / "chinchilla2_walk_cycle_4f_sheet.png", "1024x1024"),
        (FLARE_DEPLOYMENT, [anchor, out_dir / "chinchilla_top_peek_center.png", photo_ref], CHIN2_CLIMB_YAWN_PROMPT, raw_dir / "chinchilla2_climb_yawn_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "chinchilla2_idle.png"], CHIN2_HOP_LOOK_PROMPT, raw_dir / "chinchilla2_hop_look_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, out_dir / "chinchilla_tennis_ready.png"], CHIN2_TENNIS_PROMPT, raw_dir / "chinchilla2_tennis_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "flash_step_8f_pose_ref.png"], make_flash_step_prompt(CHIN2_DESC), raw_dir / "chinchilla2_flash_step_8f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "bear_shake_8f_pose_ref.png"], make_bear_shake_prompt(CHIN2_DESC), raw_dir / "chinchilla2_bear_shake_8f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "wanderer_kick_6f_pose_ref.png"], make_wanderer_kick_prompt(CHIN2_DESC), raw_dir / "chinchilla2_wanderer_kick_6f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "head_tilt_6f_pose_ref.png"], make_head_tilt_prompt(CHIN2_DESC), raw_dir / "chinchilla2_head_tilt_6f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, cat_belly_ref], CHIN2_BELLY_ROLL_PROMPT, raw_dir / "chinchilla2_belly_roll_6f_sheet.png", "1536x1024"),
    ]
    if args.force:
        for job in jobs:
            job[3].unlink(missing_ok=True)

    print("=== Phase 2: Generating all 10 remaining Silver-White Chinchilla sheets concurrently (4 workers) ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futs = [
            pool.submit(edit_image_multi_ref, endpoint, api_key, dep, refs, prompt, out_p, sz, "high")
            for dep, refs, prompt, out_p, sz in jobs
        ]
        for fut in futs:
            fut.result()

    slice_wave2_sheets(raw_dir, out_dir)
    print("=== DONE generating & slicing all 67 Friend's Silver-White Chinchilla sprites! ===", flush=True)


if __name__ == "__main__":
    main()
