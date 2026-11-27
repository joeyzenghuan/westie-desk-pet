#!/usr/bin/env python3
"""
Generate 100% full-parity pixel-art sprite suite (67 transparent PNGs) for the
Cream-Yellow Labrador Retriever (`🐶 拉布拉多`) matching the user's real reference photo
(`assets_raw/labrador_reference.png`):

- Smooth short creamy ivory / light butter-yellow coat
- Floppy drooping triangular warm honey-apricot / golden-biscuit ears (STRICTLY TWO ears!)
- Thick otter tail in cream fading to a warm golden-caramel tip
- Expressive dark-brown eyes, pinkish-brown Dudley nose with dark rim, happy Labrador smile
- Soft pale sage-grey / mint patterned collar (NO leash, NO hat)

Phase 1 (anchor): `lab_companion_sheet.png` -> lab_idle, lab_sit_tilt, lab_sleep, lab_dangling, lab_loaf_calm, lab_holding_ball
Phase 2 (10 sheets concurrently across Flare + Sunburst):
  - lab_peek_sheet.png          -> lab_peek_calm, lab_peek_hover, lab_chin_ledge, lab_badge_icon, lab_eat_1, lab_eat_2
  - lab_walk_cycle_4f_sheet.png -> lab_walk_1..4
  - lab_climb_yawn_sheet.png    -> lab_top_peek_center/left/right, lab_climb_up, lab_yawn, lab_drowsy
  - lab_hop_look_sheet.png      -> lab_hop_crouch/air/land, lab_look_left_head_left/center/right
  - lab_tennis_sheet.png        -> lab_tennis_ready/run/swing/dive, lab_victory
  - lab_flash_step_8f_sheet.png -> lab_flash_step_1..8 (192x128 height-locked)
  - lab_bear_shake_8f_sheet.png -> lab_bear_shake_1..8 (192x128 height-locked)
  - lab_wanderer_kick_6f_sheet.png -> lab_wanderer_kick_1..6 (192x128 height-locked)
  - lab_head_tilt_6f_sheet.png  -> lab_head_tilt_1..6 (128x128 height-locked)
  - lab_belly_roll_6f_sheet.png -> lab_belly_roll_1..6 (128x128 height-locked)
"""
from __future__ import annotations

import argparse
import concurrent.futures
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_assets import FLARE_DEPLOYMENT, SUNBURST_DEPLOYMENT, load_api_key
from generate_belly_roll_sprites import make_belly_roll_prompt
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


LAB_DESC = (
    "an adorable chubby cream-yellow Labrador Retriever puppy (拉布拉多) matching the exact dog in Image 1: "
    "smooth short creamy-ivory / light butter-yellow coat, soft FLOPPY drooping triangular WARM HONEY-APRICOT / GOLDEN-BISCUIT colored ears "
    "(distinctly warmer golden-tan than the creamy-ivory body — STRICTLY TWO symmetrical floppy ears, NEVER three ears, NEVER upright pointy ears!), "
    "expressive dark-brown eyes, cute pinkish-brown Dudley nose with dark rim, cheerful friendly Labrador smile, "
    "thick otter-style cream tail fading to a warm golden-caramel tip, thin soft pale mint-grey patterned collar (NO leash, NO hat), "
    "crisp dark pixel outline, 32-bit retro pixel art matching the exact aesthetic of a desktop pet (NO anti-aliasing blur, NO drop shadows)"
)

LAB_COMPANION_PROMPT = (
    f"Transform the real cream-yellow Labrador Retriever in Image 1 into {LAB_DESC}, "
    "strictly matching the crisp 32-bit pixel art line weight, shading style, and chibi desktop-pet proportions of Image 2. "
    "Create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO boxes, NO text, NO leash, NO drop shadows, generous transparent margin around each sprite). "
    "Consistent cute Labrador body & head scale across all 6 cells: "
    "Row 1 Col 1 (top-left): IDLE STANDING (side-profile facing RIGHT) — friendly cream Labrador standing neatly on all four paws, warm honey-gold floppy ears, dark eyes alert, cream-and-gold-tipped otter tail wagging happily. "
    "Row 1 Col 2 (top-center): CALM SITTING SMILE (front-facing 3/4) — cream Labrador sitting neatly facing the camera with an adorable slight head tilt, warm happy smile with tiny pink tongue, honey-apricot floppy ears, neat pale mint-grey collar. "
    "Row 1 Col 3 (top-right): SLEEPING CURL (side view facing RIGHT) — curled up flat and cozy on its belly fast asleep, eyes peacefully closed, golden-tipped tail tucked neatly beside body, zero Zzz text. "
    "Row 2 Col 1 (bottom-left): DANGLING SCRUFF CARRY — being gently lifted up by the scruff in mid-air, cute round Labrador face looking slightly surprised, honey ears drooping, all four paws dangling downward. "
    "Row 2 Col 2 (bottom-center): CALM LOAF (side view facing RIGHT) — lying flat in a relaxed dog-loaf posture on its belly facing right, chin resting calmly above tucked front paws, warm dark eyes open watching peacefully. "
    "Row 2 Col 3 (bottom-right): HOLDING TENNIS BALL (facing right/front) — sitting excitedly holding a bright neon green-yellow pixel tennis ball in its mouth inviting the owner to play!"
)

LAB_PEEK_AND_EAT_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art cream-yellow Labrador puppy from Image 1 ({LAB_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet arranged in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): EDGE PEEK CALM — the cream Labrador hiding behind an invisible vertical wall on the RIGHT edge of this cell, ONLY its friendly head, honey-apricot floppy ears, and two cream front paws gripping the straight vertical right edge are visible, peeking LEFTWARD calmly (no wall drawn). "
    "Row 1 Col 2 (top-center): EDGE PEEK HOVER — same vertical right-edge peeking pose looking LEFTWARD, leaning out slightly further with a big joyful Labrador smile, pink tongue peek, and one cream front paw raised in a friendly hello wave (cut cleanly along straight vertical right edge, no wall drawn). "
    "Row 1 Col 3 (top-right): BIG HEAD LEDGE PEEK ('大头趴窗盯镜头') — close-up front view of the cream Labrador's adorable smiling head, honey-apricot floppy ears, and two front paws resting cleanly on an invisible flat horizontal bottom line, staring right at the viewer! "
    "Row 2 Col 1 (bottom-left): MENU BAR BADGE ICON — clean crisp iconic square pixel-art head portrait of this cream Labrador with honey-apricot floppy ears and a tiny green tennis ball beside its cheek, bold dark outline, readable at 18x18px. "
    "Row 2 Col 2 (bottom-center): EATING BONE FRAME 1 (CRUNCH) — cream Labrador sitting side-3/4 facing RIGHT, happily chomping down on a cute white dog bone treat held between its front paws, mouth open wide biting the bone! "
    "Row 2 Col 3 (bottom-right): EATING BONE FRAME 2 (BLISSFUL CHEW) — IDENTICAL sitting body & bone position as Row 2 Col 2, eyes closed in super happy '^ ^' curved arcs chewing blissfully with puffy cheeks!"
)

LAB_WALK_CYCLE_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art cream-yellow Labrador puppy from Image 1 ({LAB_DESC}), "
    "create a 1024x1024 transparent-background 4-frame SIDE-PROFILE WALK CYCLE sprite sheet in a strict 2 columns by 2 rows grid "
    "(4 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin). "
    "ALL 4 frames MUST face strictly RIGHT in clean side-profile with IDENTICAL head size, body length, and ground baseline, "
    "with CLEAR dark pixel outlines separating all four legs so the stepping legs are unmistakably readable even at 66px! "
    "Row 1 Col 1 (top-left): WALK FRAME 1 (WIDE STRIDE A) — front-right leg reaching clearly FORWARD, front-left leg angled BACKWARD, back-left leg forward under belly, back-right leg pushing backward (clear scissors gap!). "
    "Row 1 Col 2 (top-right): WALK FRAME 2 (PASSING A) — front-right leg planted straight down, front-left paw lifted bent forward off ground, hind legs passing close underneath, golden-tipped otter tail swaying up. "
    "Row 2 Col 1 (bottom-left): WALK FRAME 3 (WIDE STRIDE B, OPPOSITE) — front-left leg reaching clearly FORWARD, front-right leg angled BACKWARD, back-right leg forward under belly, back-left leg pushing backward. "
    "Row 2 Col 2 (bottom-right): WALK FRAME 4 (PASSING B) — front-left leg planted straight down, front-right paw lifted bent forward off ground, hind legs passing close underneath, tail slightly lower."
)

LAB_CLIMB_YAWN_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art cream-yellow Labrador puppy from Image 1 ({LAB_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, NO Zzz, generous transparent margin): "
    "Row 1 Col 1 (top-left): TOP PEEK CENTER — only the cream Labrador's cute head, honey-apricot floppy ears, and two cream front paws resting cleanly on a flat invisible horizontal bottom line, looking straight forward curiously. "
    "Row 1 Col 2 (top-center): TOP PEEK LEFT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing LEFT curiously. "
    "Row 1 Col 3 (top-right): TOP PEEK RIGHT — the EXACT same top-edge peeking head and two paws in identical position & scale as Row 1 Col 1, head gently turned glancing RIGHT curiously. "
    "Row 2 Col 1 (bottom-left): CLIMBING UP OVER LEDGE — mid-climb pose facing right: cream Labrador pulling its body up onto the flat horizontal floor, front paws planted forward, hind legs scrambling up. "
    "Row 2 Col 2 (bottom-center): BIG CUTE YAWN — full-body cream Labrador in side-3/4 view facing RIGHT, sitting slightly hunched with eyes tightly squinted in a sleepy happy curve, mouth open wide showing a cute pink tongue yawn. "
    "Row 2 Col 3 (bottom-right): DROWSY HALF-ASLEEP LOAF — full-body cream Labrador lying low and flat on its belly facing RIGHT (matching the compact loaf silhouette of sleeping pose), chin resting on paws, heavy half-closed eyelids."
)

LAB_HOP_LOOK_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art cream-yellow Labrador puppy from Image 1 ({LAB_DESC}), "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "ROW 1 (3-frame joyful bouncy Labrador puppy hop cycle in clean side-profile facing RIGHT): "
    "Row 1 Col 1 (top-left): HOP CROUCH (facing RIGHT) — playful puppy play-bow crouch before leaping, chest lowered, front paws bent low, hind legs coiled, golden-tipped tail wagging high. "
    "Row 1 Col 2 (top-center): HOP MID-AIR LEAP (facing RIGHT) — joyful mid-air puppy bound, body stretched in lively airborne arc, honey ears bouncing up, front paws reaching forward-up, hind legs extended backward-down with clear air under belly. "
    "Row 1 Col 3 (top-right): HOP LANDING (facing RIGHT) — soft front-paw landing cushion, front paws touching down forward absorbing the jump, hind legs trailing slightly behind. "
    "ROW 2 (Stationary standing body facing LEFT — ALL THREE CELLS in Row 2 MUST have the EXACT SAME stationary standing body, tail, and 4 planted paws facing LEFT, ONLY the head turns!): "
    "Row 2 Col 1 (bottom-left): STANDING FACING LEFT, HEAD LOOKING LEFT — cream Labrador standing quietly side-profile facing LEFT, all 4 paws planted steadily, head peering curiously LEFT. "
    "Row 2 Col 2 (bottom-center): STANDING FACING LEFT, HEAD LOOKING CENTER — IDENTICAL stationary body & 4 planted paws facing LEFT as Row 2 Col 1, ONLY the head is turned toward the front viewer curiously. "
    "Row 2 Col 3 (bottom-right): STANDING FACING LEFT, HEAD LOOKING RIGHT — IDENTICAL stationary body & 4 planted paws facing LEFT as Row 2 Col 1, ONLY the head is turned back over its shoulder peering curiously RIGHT!"
)

LAB_TENNIS_PROMPT = (
    f"Using the EXACT SAME 32-bit pixel-art cream-yellow Labrador puppy from Image 1 ({LAB_DESC}), "
    "wearing a tiny sporty blue-and-white tennis sweatband around its wrist/forehead and holding a tiny classic wooden/green pixel tennis racket, "
    "create a 1536x1024 transparent-background sprite sheet in a strict 3 columns by 2 rows grid "
    "(6 equal cells of 512x512, NO grid lines, NO borders, NO text, generous transparent margin): "
    "Row 1 Col 1 (top-left): TENNIS READY — facing downward toward the player, athletic ready stance gripping mini tennis racket, determined cute dark eyes, honey ears perked. "
    "Row 1 Col 2 (top-center): TENNIS RUN — sprinting sideways to chase a tennis ball, paws stretched running, honey ears streaming back, racket held out ready. "
    "Row 1 Col 3 (top-right): TENNIS SWING — dynamic forehand racket follow-through swing hitting a shot forward, energetic happy Labrador expression. "
    "Row 2 Col 1 (bottom-left): TENNIS DIVE — dramatic horizontal full-stretch diving save reaching out with racket extended! "
    "Row 2 Col 2 (bottom-center): VICTORY CELEBRATION — jumping joyfully with both paws and racket raised high in victory, huge happy open-mouth Labrador grin! "
    "Row 2 Col 3 (bottom-right): EXTRA HOLDING BALL — sitting holding a bright neon-green tennis ball proudly."
)


def slice_lab_base_sheets(raw_dir: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Companion core (6)
    cc = Image.open(raw_dir / "lab_companion_sheet.png").convert("RGBA")
    cw, rh = cc.width // 3, cc.height // 2
    for col, row, name, balign in [
        (0, 0, "lab_idle", True),
        (1, 0, "lab_sit_tilt", True),
        (2, 0, "lab_sleep", True),
        (0, 1, "lab_dangling", False),
        (1, 1, "lab_loaf_calm", True),
        (2, 1, "lab_holding_ball", True),
    ]:
        cell = cc.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)


def slice_lab_wave2_sheets(raw_dir: Path, out_dir: Path) -> None:
    # 2. Peek + Badge + Eat (6)
    pk = Image.open(raw_dir / "lab_peek_sheet.png").convert("RGBA")
    cw, rh = pk.width // 3, pk.height // 2
    for col, row, name in [(0, 0, "lab_peek_calm"), (1, 0, "lab_peek_hover")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr = normalize_right_edge_peek(cell, canvas_size=128)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (flush right-edge peek)", flush=True)
    for col, row, name, balign in [
        (2, 0, "lab_chin_ledge", True),
        (0, 1, "lab_badge_icon", False),
    ]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, _ = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=balign, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png", flush=True)
    eat_ref_scale: float | None = None
    for col, row, name in [(1, 1, "lab_eat_1"), (2, 1, "lab_eat_2")]:
        cell = pk.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=eat_ref_scale)
        if eat_ref_scale is None:
            eat_ref_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 3. Walk cycle (4, locked uniform scale!)
    slice_grid_height_locked(raw_dir / "lab_walk_cycle_4f_sheet.png", 2, 2, 128, 128, "lab_walk", out_dir, ref_cell_idx=0)

    # 4. Climb & Yawn (6, top_peek 3 frames locked together!)
    cy = Image.open(raw_dir / "lab_climb_yawn_sheet.png").convert("RGBA")
    cw, rh = cy.width // 3, cy.height // 2
    peek_scale: float | None = None
    for col, name in [(0, "lab_top_peek_center"), (1, "lab_top_peek_left"), (2, "lab_top_peek_right")]:
        cell = cy.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=peek_scale)
        if peek_scale is None:
            peek_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    for col, name in [(0, "lab_climb_up"), (1, "lab_yawn"), (2, "lab_drowsy")]:
        cell = cy.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 5. Hop & Look (6, row 1 & row 2 each uniform!)
    hl = Image.open(raw_dir / "lab_hop_look_sheet.png").convert("RGBA")
    cw, rh = hl.width // 3, hl.height // 2
    hop_scale: float | None = None
    for col, name in [(0, "lab_hop_crouch"), (1, "lab_hop_air"), (2, "lab_hop_land")]:
        cell = hl.crop((col * cw, 0, (col + 1) * cw, rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=hop_scale)
        if hop_scale is None:
            hop_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)
    look_scale: float | None = None
    for col, name in [(0, "lab_look_left_head_left"), (1, "lab_look_left_head_center"), (2, "lab_look_left_head_right")]:
        cell = hl.crop((col * cw, rh, (col + 1) * cw, rh * 2))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8, fixed_scale=look_scale)
        if look_scale is None:
            look_scale = sc
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 6. Tennis (5)
    tn = Image.open(raw_dir / "lab_tennis_sheet.png").convert("RGBA")
    cw, rh = tn.width // 3, tn.height // 2
    for col, row, name in [
        (0, 0, "lab_tennis_ready"),
        (1, 0, "lab_tennis_run"),
        (2, 0, "lab_tennis_swing"),
        (0, 1, "lab_tennis_dive"),
        (1, 1, "lab_victory"),
    ]:
        cell = tn.crop((col * cw, row * rh, (col + 1) * cw, (row + 1) * rh))
        spr, sc = clean_and_normalize_sprite(cell, canvas_size=128, bottom_align=True, padding=8)
        spr.save(out_dir / f"{name}.png")
        print(f"[SPRITE] Saved {name}.png (scale={sc:.3f})", flush=True)

    # 7..11. All 5 Effect Suites (Flash-Step 8f, Bear-Shake 8f, Wanderer-Kick 6f, Head-Tilt 6f, Belly-Roll 6f)
    slice_4x2_height_locked(raw_dir / "lab_flash_step_8f_sheet.png", "lab", out_dir)
    slice_grid_height_locked(raw_dir / "lab_bear_shake_8f_sheet.png", 4, 2, 192, 128, "lab_bear_shake", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "lab_wanderer_kick_6f_sheet.png", 3, 2, 192, 128, "lab_wanderer_kick", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "lab_head_tilt_6f_sheet.png", 3, 2, 128, 128, "lab_head_tilt", out_dir, ref_cell_idx=0)
    slice_grid_height_locked(raw_dir / "lab_belly_roll_6f_sheet.png", 3, 2, 128, 128, "lab_belly_roll", out_dir, ref_cell_idx=1)


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

    lab_photo = raw_dir / "labrador_reference.png"
    comp_sheet = raw_dir / "lab_companion_sheet.png"
    if args.force:
        comp_sheet.unlink(missing_ok=True)

    print("=== Phase 1: Generating Labrador pixel-art identity anchor (`lab_companion_sheet.png`) ===", flush=True)
    edit_image_multi_ref(
        endpoint, api_key, FLARE_DEPLOYMENT,
        [lab_photo, out_dir / "westie_sit_tilt.png"],
        LAB_COMPANION_PROMPT, comp_sheet, "1536x1024", "high",
    )
    slice_lab_base_sheets(raw_dir, out_dir)

    anchor = out_dir / "lab_sit_tilt.png"
    jobs = [
        (FLARE_DEPLOYMENT, [anchor, lab_photo], LAB_PEEK_AND_EAT_PROMPT, raw_dir / "lab_peek_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "lab_idle.png"], LAB_WALK_CYCLE_PROMPT, raw_dir / "lab_walk_cycle_4f_sheet.png", "1024x1024"),
        (FLARE_DEPLOYMENT, [anchor, lab_photo], LAB_CLIMB_YAWN_PROMPT, raw_dir / "lab_climb_yawn_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, out_dir / "lab_idle.png"], LAB_HOP_LOOK_PROMPT, raw_dir / "lab_hop_look_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, out_dir / "westie_tennis_ready.png"], LAB_TENNIS_PROMPT, raw_dir / "lab_tennis_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "flash_step_8f_pose_ref.png"], make_flash_step_prompt(LAB_DESC), raw_dir / "lab_flash_step_8f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "bear_shake_8f_pose_ref.png"], make_bear_shake_prompt(LAB_DESC), raw_dir / "lab_bear_shake_8f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "wanderer_kick_6f_pose_ref.png"], make_wanderer_kick_prompt(LAB_DESC), raw_dir / "lab_wanderer_kick_6f_sheet.png", "1536x1024"),
        (FLARE_DEPLOYMENT, [anchor, raw_dir / "head_tilt_6f_pose_ref.png"], make_head_tilt_prompt(LAB_DESC), raw_dir / "lab_head_tilt_6f_sheet.png", "1536x1024"),
        (SUNBURST_DEPLOYMENT, [anchor, raw_dir / "belly_roll_6f_pose_ref.png"], make_belly_roll_prompt(LAB_DESC), raw_dir / "lab_belly_roll_6f_sheet.png", "1536x1024"),
    ]
    if args.force:
        for job in jobs:
            job[3].unlink(missing_ok=True)

    print("=== Phase 2: Generating all 10 remaining Labrador sprite sheets concurrently ===", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futs = [
            pool.submit(edit_image_multi_ref, endpoint, api_key, dep, refs, prompt, out_p, sz, "high")
            for dep, refs, prompt, out_p, sz in jobs
        ]
        for fut in futs:
            fut.result()

    slice_lab_wave2_sheets(raw_dir, out_dir)
    print("=== DONE generating & slicing all 67 Cream-Yellow Labrador sprites! ===", flush=True)


if __name__ == "__main__":
    main()
