#!/usr/bin/env python3
"""
Generate 100% full-parity pixel-art sprite suite (67 transparent PNGs) for the
Silver Chinchilla Persian Cat (`🐈 金吉拉小猫`):

- Ultra-fluffy long-haired cloud-like pure snowy-white coat with delicate cool silver-grey tipping on back & head
- Big fluffy Persian neck ruff / mane & luxurious plume-like silver-tipped fluffy white tail
- Iconic huge round sparkling emerald-green eyes with crisp black eyeliner rims
- Cute brick-red / rosy-pink button nose outlined in black, sweet `:3` cat smile
- STRICTLY TWO small rounded fluffy cat ears (NEVER three ears, NO hat, NO collar)
- Feeds on dried fish (`dried_fish_treat.png`, shared with Golden Shaded Cat)

Phase 1 (anchor): `chinchilla_companion_sheet.png` -> idle, sit_tilt, sleep, dangling (WITH human hand!), loaf_calm, holding_ball
Phase 2 (10 sheets concurrently, max_workers=4 across Flare + Sunburst):
  - chinchilla_peek_sheet.png          -> peek_calm, peek_hover, chin_ledge, badge_icon, eat_1 (dried fish!), eat_2
  - chinchilla_walk_cycle_4f_sheet.png -> walk_1..4
  - chinchilla_climb_yawn_sheet.png    -> top_peek_center/left/right, climb_up, yawn, drowsy
  - chinchilla_hop_look_sheet.png      -> hop_crouch/air/land, look_left_head_left/center/right
  - chinchilla_tennis_sheet.png        -> tennis_ready/run/swing/dive, victory
  - chinchilla_flash_step_8f_sheet.png -> flash_step_1..8 (192x128 height-locked)
  - chinchilla_bear_shake_8f_sheet.png -> bear_shake_1..8 (192x128 height-locked)
  - chinchilla_wanderer_kick_6f_sheet.png -> wanderer_kick_1..6 (192x128 height-locked)
  - chinchilla_head_tilt_6f_sheet.png  -> head_tilt_1..6 (128x128 height-locked)
  - chinchilla_belly_roll_6f_sheet.png -> belly_roll_1..6 (128x128, pose-locked to QA-passed cat_belly_roll_1..6!)
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


CHIN_DESC = (
    "an adorable ultra-fluffy Silver Chinchilla Persian cat (银色金吉拉猫): "
    "plump long-haired cloud-like PURE SNOWY-WHITE coat with delicate cool SILVER-GREY tipping along the crown and back, "
    "luxurious fluffy white neck ruff/mane, huge round sparkling EMERALD-GREEN eyes outlined with crisp black eyeliner rims, "
    "tiny rosy brick-pink button nose with black rim, sweet cute ':3' cat mouth, "
    "STRICTLY TWO small low-set rounded fluffy white cat ears with soft pink inner tufts (NEVER three ears, NO hat, NO collar), "
    "extra fluffy plume-like white-and-silver Persian feather tail, crisp dark pixel outline, "
    "32-bit retro pixel art matching the exact crisp aesthetic of a desktop pet (NO anti-aliasing blur, NO drop shadows)"
)

CHIN_COMPANION_PROMPT = (
    f"Create {CHIN_DESC}, strictly matching the exact 32-bit pixel art line weight, shading style, and chibi desktop-pet proportions "
    "of the pixel cat in Image 1 and the scruff-carry human hand in Image 2. "
    "Create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO boxes, NO text, NO drop shadows, generous transparent margin around each sprite). "
    "Consistent ultra-fluffy Chinchilla Persian body & head size across all 6 cells: "
    "Row 1 Col 1 (top-left): IDLE STANDING (side-profile facing RIGHT) — cloud-fluffy snowy-white silver-tipped Chinchilla cat standing neatly on all four paws, sparkling green eyeliner eyes alert, big luxurious fluffy white-silver plume tail curled gracefully upward. "
    "Row 1 Col 2 (top-center): CALM SITTING SMILE (front-facing 3/4) — fluffy Chinchilla cat sitting neatly facing camera with a super sweet slight head tilt, huge emerald eyeliner eyes, cute ':3' smile, cloud-fluffy white chest ruff, neat white front paws together. "
    "Row 1 Col 3 (top-right): SLEEPING CLOUD BALL (side view facing RIGHT) — curled up flat and cozy on its belly fast asleep like a fluffy white snow-cloud, eyes peacefully closed, huge fluffy plume tail wrapped around body, zero Zzz text. "
    "Row 2 Col 1 (bottom-left): DANGLING SCRUFF CARRY (WITH HUMAN HAND!) — matching Image 2's exact cute cartoon pixel-art HUMAN HAND coming from above gently pinching the fluffy scruff behind the Chinchilla cat's neck so the fluffy white kitten dangles helplessly and adorably in mid-air with wide cute surprised emerald eyes and all four fluffy paws dangling downward! "
    "Row 2 Col 2 (bottom-center): CALM LOAF (side view facing RIGHT) — lying flat in a super fluffy cloud-like cat-loaf posture facing right, white paws tucked under fluffy neck ruff, big emerald eyes calmly watching. "
    "Row 2 Col 3 (bottom-right): HOLDING TENNIS BALL (facing right/front) — sitting excitedly holding a bright green-yellow pixel tennis ball in its paws/mouth inviting the owner to play!"
)

CHIN_PEEK_AND_EAT_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): EDGE PEEK CALM — the fluffy white-silver Chinchilla cat hiding behind an invisible vertical wall on the RIGHT edge of this cell, ONLY its round fluffy head, two small rounded ears, huge emerald eyeliner eyes, and two fluffy white paws gripping the straight vertical right edge are visible, peeking LEFTWARD calmly (no wall drawn). "
    "Row 1 Col 2 (top-center): EDGE PEEK HOVER — same vertical right-edge peeking pose looking LEFTWARD, leaning out slightly further with bright happy emerald eyes, sweet ':3' smile, and one fluffy white paw raised in a friendly hello wave (cut cleanly along straight vertical right edge, no wall drawn). "
    "Row 1 Col 3 (top-right): BIG HEAD LEDGE PEEK — close-up front view of the Chinchilla cat's ultra-fluffy round white-silver head and two fluffy paws resting cleanly on an invisible flat horizontal bottom line, staring right at the viewer with huge sparkling emerald eyeliner eyes. "
    "Row 2 Col 1 (bottom-left): MENU BAR BADGE ICON — clean crisp iconic square pixel-art head portrait of this white-silver Chinchilla cat with huge emerald green eyes and a tiny green tennis ball beside its fluffy cheek, bold dark outline, readable at 18x18px. "
    "Row 2 Col 2 (bottom-center): EATING DRIED FISH FRAME 1 (CRUNCH) — matching Image 2's cute golden-brown DRIED FISH snack (`小鱼干`), Chinchilla cat sitting side-3/4 facing RIGHT happily chomping down on a golden dried fish held between its fluffy white paws, mouth open biting the fish! "
    "Row 2 Col 3 (bottom-right): EATING DRIED FISH FRAME 2 (BLISSFUL CHEW) — IDENTICAL sitting body & dried fish position as Row 2 Col 2, eyes closed in super happy '^ ^' arcs chewing the dried fish blissfully with puffy fluffy cheeks!"
)

CHIN_WALK_CYCLE_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "create a 1024x1024 transparent-background 4-frame SIDE-PROFILE WALK CYCLE sprite sheet in a strict 2 columns by 2 rows grid "
    "(4 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin). "
    "ALL 4 frames MUST face strictly RIGHT in clean side-profile with IDENTICAL head size, fluffy body length, and ground baseline, "
    "with CLEAR dark pixel outlines separating all four white paws so the stepping stride is unmistakably readable even at 66px! "
    "Row 1 Col 1 (top-left): WALK FRAME 1 (WIDE STRIDE A) — front-right paw reaching clearly FORWARD, front-left paw angled BACKWARD, back-left paw forward under belly, back-right paw pushing backward (clear scissors gap!). "
    "Row 1 Col 2 (top-right): WALK FRAME 2 (PASSING A) — front-right paw planted straight down, front-left paw lifted bent forward off ground, hind paws passing close underneath, big fluffy plume tail swaying up. "
    "Row 2 Col 1 (bottom-left): WALK FRAME 3 (WIDE STRIDE B, OPPOSITE) — front-left paw reaching clearly FORWARD, front-right paw angled BACKWARD, back-right paw forward under belly, back-left paw pushing backward. "
    "Row 2 Col 2 (bottom-right): WALK FRAME 4 (PASSING B) — front-left paw planted straight down, front-right paw lifted bent forward off ground, hind paws passing close underneath, fluffy plume tail slightly lower."
)

CHIN_CLIMB_YAWN_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO Zzz, generous transparent margin): "
    "Row 1 Col 1 (top-left): TOP PEEK CENTER — only the fluffy Chinchilla cat's round white-silver head, two small rounded ears, emerald eyes, and two fluffy white front paws resting cleanly on a flat invisible horizontal bottom line, looking straight forward curiously. "
    "Row 1 Col 2 (top-center): TOP PEEK LEFT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing LEFT curiously. "
    "Row 1 Col 3 (top-right): TOP PEEK RIGHT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing RIGHT curiously. "
    "Row 2 Col 1 (bottom-left): CLIMBING UP OVER LEDGE — mid-climb pose facing right: fluffy Chinchilla cat pulling its cloud-like body up onto the flat horizontal floor, front paws planted forward, hind legs scrambling up. "
    "Row 2 Col 2 (bottom-center): BIG CUTE YAWN — full-body Chinchilla cat in side-3/4 view facing RIGHT, sitting slightly hunched with eyes tightly squinted in a sleepy happy curve, mouth open wide showing a cute pink yawn. "
    "Row 2 Col 3 (bottom-right): DROWSY HALF-ASLEEP LOAF — full-body fluffy Chinchilla cat lying low and flat on its belly facing RIGHT (matching compact loaf silhouette of sleeping pose), chin resting on fluffy paws, heavy half-closed emerald eyelids."
)

CHIN_HOP_LOOK_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "ROW 1 (3-frame joyful bouncy kitty pounce/hop cycle in clean side-profile facing RIGHT): "
    "Row 1 Col 1 (top-left): HOP CROUCH (facing RIGHT) — playful kitty crouch before leaping, fluffy chest lowered, front paws bent low, hind legs coiled, plume tail raised high. "
    "Row 1 Col 2 (top-center): HOP MID-AIR LEAP (facing RIGHT) — joyful mid-air fluffy cloud kitty bound, body stretched in lively airborne arc, front paws reaching forward-up, hind paws extended backward-down with clear air under belly. "
    "Row 1 Col 3 (top-right): HOP LANDING (facing RIGHT) — soft front-paw landing cushion, front paws touching down forward absorbing the jump, hind legs trailing slightly behind. "
    "ROW 2 (Stationary standing body facing LEFT — ALL THREE CELLS in Row 2 MUST have the EXACT SAME stationary standing body, fluffy plume tail, and 4 planted paws facing LEFT, ONLY the head turns!): "
    "Row 2 Col 1 (bottom-left): STANDING FACING LEFT, HEAD LOOKING LEFT — Chinchilla cat standing quietly side-profile facing LEFT, all 4 paws planted steadily, head peering curiously LEFT. "
    "Row 2 Col 2 (bottom-center): STANDING FACING LEFT, HEAD LOOKING CENTER — IDENTICAL stationary body, plume tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the round fluffy head is turned toward the front viewer curiously. "
    "Row 2 Col 3 (bottom-right): STANDING FACING LEFT, HEAD LOOKING RIGHT — IDENTICAL stationary body, plume tail, and 4 planted paws facing LEFT as Row 2 Col 1, ONLY the round fluffy head is turned back over its shoulder peering curiously RIGHT!"
)

CHIN_TENNIS_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "wearing a tiny sporty mint-green-and-white sweatband around its wrist/forehead and holding a tiny classic wooden/green pixel tennis racket, "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): TENNIS READY — facing downward toward player, athletic ready stance gripping mini tennis racket, determined cute sparkling emerald eyes. "
    "Row 1 Col 2 (top-center): TENNIS RUN — sprinting sideways to chase a tennis ball, fluffy paws stretched running, plume tail streaming, racket held out ready. "
    "Row 1 Col 3 (top-right): TENNIS SWING — dynamic forehand racket follow-through swing hitting a shot forward, energetic cute expression. "
    "Row 2 Col 1 (bottom-left): TENNIS DIVE — dramatic horizontal full-stretch diving save reaching out with racket extended (keep entire racket unclipped inside margin!). "
    "Row 2 Col 2 (bottom-center): VICTORY CELEBRATION — jumping joyfully with both fluffy paws and racket raised high in victory, super happy sparkling smile! "
    "Row 2 Col 3 (bottom-right): EXTRA HOLDING BALL — sitting holding a bright neon-green tennis ball proudly."
)

CHIN_BELLY_ROLL_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art Silver Chinchilla Persian cat from Image 1 ({CHIN_DESC}), "
    "faithfully transfer ALL 6 EXACT 4-PAW BELLY-UP ROLL-OVER POSES shown in the 3-column by 2-row pixel-art cat reference grid in Image 2! "
    "Create a 1536x1024 transparent-background sprite sheet arranged in an EXACT 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin in every cell). "
    "CRITICAL ANATOMY LOCK (100% MATCH IMAGE 2'S EXACT 4-PAW COUNT!): "
    "1) Keep the exact same 6 poses, body angles, and fluffy tail positions as Image 2, swapping ONLY the breed to our ultra-fluffy snowy-white silver-tipped Chinchilla Persian cat with emerald eyeliner eyes! "
    "2) COUNT THE PAWS IN CELLS 2, 3, 4, 5, 6 — EVERY SINGLE ONE OF CELLS 2..6 MUST HAVE EXACTLY FOUR (4) CLEAR SEPARATE PAWS (2 front + 2 hind with tiny pink paw pads — NEVER 3 paws, NEVER 5 paws!) AND THE FLUFFY WHITE-SILVER PLUME TAIL! "
    "Row 1 Col 1: Low side-flop entry/exit matching Image 2 R1C1. "
    "Row 1 Col 2: Belly-up waiting Pose A matching Image 2 R1C2 (EXACTLY 4 paws + fluffy plume tail!). "
    "Row 1 Col 3: Belly-up waiting Pose B happy grin matching Image 2 R1C3 (EXACTLY 4 paws + fluffy plume tail!). "
    "Row 2 Col 1: Roll-in wind-up matching Image 2 R2C1 (EXACTLY 4 paws + fluffy plume tail!). "
    "Row 2 Col 2: Supine dead-center apex matching Image 2 R2C2 (belly straight up, upside-down grinning face, EXACTLY 4 symmetric paws kicked up in air + fluffy plume tail!). "
    "Row 2 Col 3: Roll-out quarter-tilt matching Image 2 R2C3 (EXACTLY 4 paws + fluffy plume tail!)."
)


def build_cat_belly_roll_ref_grid(sprites_dir: Path, out_path: Path) -> Path:
    grid = Image.new("RGB", (1536, 1024), (218, 226, 236))
    for i in range(6):
        c, r = i % 3, i // 3
        im = Image.open(sprites_dir / f"cat_belly_roll_{i + 1}.png").convert("RGBA")
        up = im.resize((448, 448), Image.Resampling.NEAREST)
        grid.paste(up, (c * 512 + 32, r * 512 + 32), up)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(out_path)
    print(f"[REF] Built 3x2 verified 4-paw cat_belly_roll ref grid -> {out_path.name}", flush=True)
    return out_path


def slice_base_sheet(raw_dir: Path, out_dir: Path) -> None:
    cc = Image.open(raw_dir / "chinchilla_companion_sheet.png").convert("RGBA")
    cw, rh = cc.width // 3, cc.height // 2
    for col, row, name, balign in [
        (0, 0, "chinchilla_idle", True),
        (1, 0, "chinchilla_sit_tilt", True),
        (2, 0, "chinchilla_sleep", True),
        (0, 1, "chinchilla_dangling", False),
        (1, 1, "chinchilla_loaf_calm", True),
        (2, 1, "chinchilla_holding_ball", True),
    ]:
        cell = cc.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)


def slice_wave2_sheets(raw_dir: Path, out_dir: Path) -> None:
    # Peek + Badge + Eat (6)
    pk = Image.open(raw_dir / "chinchilla_peek_sheet.png").convert("RGBA")
    cw, rh = pk.width // 3, pk.height // 2
    for col, row, name in [(0, 0, "chinchilla_peek_calm"), (1, 0, "chinchilla_peek_hover")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        normalize_right_edge_peek(cell, canvas_size=128).save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (flush right-edge peek)", flush=True)
    for col, row, name, balign in [(2, 0, "chinchilla_chin_ledge", True), (0, 1, "chinchilla_badge_icon", False)]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, _ = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png", flush=True)
    eat_scale: float | None = None
    for col, row, name in [(1, 1, "chinchilla_eat_1"), (2, 1, "chinchilla_eat_2")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=eat_scale)
        if eat_scale is None:
            eat_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # Walk (4)
    slice_grid_height_locked(raw_dir / "chinchilla_walk_cycle_4f_sheet.png", 2, 2, 128, 128, "chinchilla_walk", out_dir, ref_cell_idx=0)

    # Climb & Yawn (6)
    cy = Image.open(raw_dir / "chinchilla_climb_yawn_sheet.png").convert("RGBA")
    cw, rh = cy.width // 3, cy.height // 2
    p_sc: float | None = None
    for col, name in [(0, "chinchilla_top_peek_center"), (1, "chinchilla_top_peek_left"), (2, "chinchilla_top_peek_right")]:
        cell = cy.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=p_sc)
        if p_sc is None:
            p_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    for col, name in [(0, "chinchilla_climb_up"), (1, "chinchilla_yawn"), (2, "chinchilla_drowsy")]:
        cell = cy.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # Hop & Look (6)
    hl = Image.open(raw_dir / "chinchilla_hop_look_sheet.png").convert("RGBA")
    cw, rh = hl.width // 3, hl.height // 2
    h_sc: float | None = None
    for col, name in [(0, "chinchilla_hop_crouch"), (1, "chinchilla_hop_air"), (2, "chinchilla_hop_land")]:
        cell = hl.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=h_sc)
        if h_sc is None:
            h_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    l_sc: float | None = None
    for col, name in [(0, "chinchilla_look_left_head_left"), (1, "chinchilla_look_left_head_center"), (2, "chinchilla_look_left_head_right")]:
        cell = hl.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=l_sc)
        if l_sc is None:
            l_sc = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # Tennis (5)
    tn = Image.open(raw_dir / "chinchilla_tennis_sheet.png").convert("RGBA")
    cw, rh = tn.width // 3, tn.height // 2
    for col, row, name in [
        (0, 0, "chinchilla_tennis_ready"),
        (1, 0, "chinchilla_tennis_run"),
        (2, 0, "chinchilla_tennis_swing"),
        (0, 1, "chinchilla_tennis_dive"),
        (1, 1, "chinchilla_victory"),
    ]:
        cell = tn.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # All 5 Effect Suites (Flash-Step 8f, Bear-Shake 8f, Wanderer-Kick 6f, Head-Tilt 6f, Belly-Roll 6f)
    slice_4x2_height_locked(raw_dir / "chinchilla_flash_step_8f_sheet.png", "chinchilla", out_dir)
    slice_grid_height_locked(raw_dir / "chinchilla_bear_shake_8f_sheet.png", 4, 2, 192, 128, "chinchilla_bear_shake", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla_wanderer_kick_6f_sheet.png", 3, 2, 192, 128, "chinchilla_wanderer_kick", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla_head_tilt_6f_sheet.png", 3, 2, 128, 128, "chinchilla_head_tilt", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "chinchilla_belly_roll_6f_sheet.png", 3, 2, 128, 128, "chinchilla_belly_roll", out_dir, ref_cell_idx=1)


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

    comp_sheet = raw_dir / "chinchilla_companion_sheet.png"
    if args.force:
        comp_sheet.unlink(missing_ok=True)

    print("=== Phase 1: Generating Silver Chinchilla Persian anchor (`chinchilla_companion_sheet.png`) ===", flush=True)
    edit_image_multi_ref(
        endpoint, api_key, FLARE_DEPLOYMENT,
        [out_dir / "cat_sit_tilt.png", out_dir / "westie_dangling.png"],
        CHIN_COMPANION_PROMPT, comp_sheet, "1536x1024", "high",
    )
    slice_base_sheet(raw_dir, out_dir)

    cat_belly_ref = build_cat_belly_roll_ref_grid(out_dir, raw_dir / "cat_belly_roll_verified_6f_ref.png")
    anchor = out_dir / "chinchilla_sit_tilt.png"
    jobs = [
        (FLARE_DEPLOYMENT, [anchor, out_dir / "dried_fish_treat.png"], CHIN_PEEK_AND_EAT_PROMPT, raw_dir / "chinchilla_peek_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "chinchilla_idle.png"], CHIN_WALK_CYCLE_PROMPT, raw_dir / "chinchilla_walk_cycle_4f_sheet.png", "1024x1024"),
        (FLARE_DEPLOYMENT, [anchor, out_dir / "cat_top_peek_center.png"], CHIN_CLIMB_YAWN_PROMPT, raw_dir / "chinchilla_climb_yawn_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "chinchilla_idle.png"], CHIN_HOP_LOOK_PROMPT, raw_dir / "chinchilla_hop_look_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, out_dir / "cat_tennis_ready.png"], CHIN_TENNIS_PROMPT, raw_dir / "chinchilla_tennis_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "flash_step_8f_pose_ref.png"], make_flash_step_prompt(CHIN_DESC), raw_dir / "chinchilla_flash_step_8f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "bear_shake_8f_pose_ref.png"], make_bear_shake_prompt(CHIN_DESC), raw_dir / "chinchilla_bear_shake_8f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "wanderer_kick_6f_pose_ref.png"], make_wanderer_kick_prompt(CHIN_DESC), raw_dir / "chinchilla_wanderer_kick_6f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "head_tilt_6f_pose_ref.png"], make_head_tilt_prompt(CHIN_DESC), raw_dir / "chinchilla_head_tilt_6f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, cat_belly_ref], CHIN_BELLY_ROLL_PROMPT, raw_dir / "chinchilla_belly_roll_6f_sheet.png", "1536x1024"),
    ]
    if args.force:
        for job in jobs:
            job[3].unlink(missing_ok=True)

    print("=== Phase 2: Generating all 10 remaining Chinchilla sprite sheets concurrently (4 workers) ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futs = [
            pool.submit(edit_image_multi_ref, endpoint, api_key, dep, refs, prompt, out_p, sz, "high")
            for dep, refs, prompt, out_p, sz in jobs
        ]
        for fut in futs:
            fut.result()

    slice_wave2_sheets(raw_dir, out_dir)
    print("=== DONE generating & slicing all 67 Silver Chinchilla Persian sprites! ===", flush=True)


if __name__ == "__main__":
    main()
