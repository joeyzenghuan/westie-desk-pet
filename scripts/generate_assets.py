#!/usr/bin/env python3
"""
Generate pixel-art sprite sheets for WestieDeskPet using Azure OpenAI GPT-Image-2.5
(Flare + Sunburst) with native transparent PNG output.

Credentials are read strictly from environment variables or an optional external INI file
passed at runtime (--config-ini). Never hardcode keys in source code.
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import configparser
import os
import sys
import time
from pathlib import Path

import json
import subprocess
import tempfile

API_VERSION = "2025-04-01-preview"
DEFAULT_ENDPOINT = "https://jzdm-foundry-swn.openai.azure.com"
FLARE_DEPLOYMENT = "gpt-image-2.5-flare-globalstandard"
SUNBURST_DEPLOYMENT = "gpt-image-2.5-sunburst-globalstandard"


def load_api_key(config_ini: str | None) -> tuple[str, str]:
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", DEFAULT_ENDPOINT).rstrip("/")
    api_key = os.environ.get("AZURE_OPENAI_API_KEY", "").strip()
    if not api_key and config_ini:
        cfg = configparser.ConfigParser()
        cfg.read(config_ini)
        if "AOAIEndpoints" in cfg and "jzdm-foundry-swn" in cfg["AOAIEndpoints"]:
            api_key = cfg["AOAIEndpoints"]["jzdm-foundry-swn"].strip()
    if not api_key:
        raise RuntimeError(
            "Missing API key. Set AZURE_OPENAI_API_KEY or pass --config-ini /path/to/.config"
        )
    return endpoint, api_key


def generate_image(
    endpoint: str,
    api_key: str,
    deployment: str,
    prompt: str,
    out_path: Path,
    size: str = "1536x1024",
    quality: str = "high",
) -> Path:
    if out_path.exists() and out_path.stat().st_size > 4096:
        print(f"[SKIP] {out_path.name} already exists.", flush=True)
        return out_path
    url = f"{endpoint}/openai/deployments/{deployment}/images/generations?api-version={API_VERSION}"
    payload = {
        "prompt": prompt,
        "size": size,
        "quality": quality,
        "n": 1,
        "output_format": "png",
        "background": "transparent",
    }
    t0 = time.perf_counter()
    for attempt in range(4):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf_body, \
             tempfile.NamedTemporaryFile("wb", suffix=".json", delete=False) as tf_resp:
            json.dump(payload, tf_body)
            body_path = tf_body.name
            resp_path = tf_resp.name
        try:
            curl_cfg = f'header = "api-key: {api_key}"\nheader = "Content-Type: application/json"\n'
            proc = subprocess.run(
                [
                    "/usr/bin/curl",
                    "-sS",
                    "--max-time", "600",
                    "-K", "-",
                    "-X", "POST",
                    "--data-binary", f"@{body_path}",
                    "-o", resp_path,
                    "-w", "%{http_code}",
                    url,
                ],
                input=curl_cfg,
                text=True,
                capture_output=True,
            )
            status_code = int(proc.stdout.strip() or "0")
            if proc.returncode != 0 or status_code == 0:
                print(f"[WARN] {deployment} curl error ({proc.stderr.strip()}), retry {attempt + 1}/4...", flush=True)
                time.sleep(3 * (attempt + 1))
                continue
            if status_code == 429 and attempt < 3:
                print(f"[429] {deployment} rate-limited, sleeping 45s...", flush=True)
                time.sleep(45)
                continue
            resp_bytes = Path(resp_path).read_bytes()
            if status_code >= 400:
                raise RuntimeError(f"HTTP {status_code} from {deployment}: {resp_bytes.decode('utf-8', 'replace')[:400]}")
            data = json.loads(resp_bytes)
            img_bytes = base64.b64decode(data["data"][0]["b64_json"])
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_bytes(img_bytes)
            elapsed = time.perf_counter() - t0
            print(f"[OK] Generated {out_path.name} via {deployment} in {elapsed:.1f}s", flush=True)
            return out_path
        finally:
            Path(body_path).unlink(missing_ok=True)
            Path(resp_path).unlink(missing_ok=True)
    raise RuntimeError(f"Failed to generate {out_path.name} after retries")


def edit_image_with_reference(
    endpoint: str,
    api_key: str,
    deployment: str,
    ref_image: Path,
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
            proc = subprocess.run(
                [
                    "/usr/bin/curl",
                    "-sS",
                    "--max-time", "600",
                    "-K", "-",
                    "-X", "POST",
                    "-F", f"image[]=@{ref_image};type=image/png",
                    "-F", f"prompt={prompt}",
                    "-F", f"size={size}",
                    "-F", f"quality={quality}",
                    "-F", "n=1",
                    "-F", "output_format=png",
                    "-F", "background=transparent",
                    "-o", resp_path,
                    "-w", "%{http_code}",
                    url,
                ],
                input=curl_cfg,
                text=True,
                capture_output=True,
            )
            status_code = int(proc.stdout.strip() or "0")
            if proc.returncode != 0 or status_code == 0:
                print(f"[WARN] {deployment} edit curl error ({proc.stderr.strip()}), retry {attempt + 1}/4...", flush=True)
                time.sleep(3 * (attempt + 1))
                continue
            if status_code == 429 and attempt < 3:
                print(f"[429] {deployment} edit rate-limited, sleeping 45s...", flush=True)
                time.sleep(45)
                continue
            resp_bytes = Path(resp_path).read_bytes()
            if status_code >= 400:
                raise RuntimeError(f"HTTP {status_code} from {deployment} edit: {resp_bytes.decode('utf-8', 'replace')[:400]}")
            data = json.loads(resp_bytes)
            img_bytes = base64.b64decode(data["data"][0]["b64_json"])
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_bytes(img_bytes)
            elapsed = time.perf_counter() - t0
            print(f"[OK] Edited {out_path.name} via {deployment} in {elapsed:.1f}s", flush=True)
            return out_path
        finally:
            Path(resp_path).unlink(missing_ok=True)
    raise RuntimeError(f"Failed to edit {out_path.name} after retries")


WESTIE_COMPANION_PROMPT = (
    "A clean 32-bit retro pixel art game sprite sheet on a completely transparent background. "
    "Arrange EXACTLY 6 evenly spaced poses in an invisible 3 columns by 2 rows layout "
    "(NO grid lines, NO boxes, NO text labels, NO drop shadows, generous empty transparent margin around every pose). "
    "Character: an adorable fluffy white West Highland White Terrier (Westie) puppy with crisp dark pixel outlines, "
    "perky upright triangular white ears, shiny black button eyes, black button nose, wearing a tiny sky-blue collar, "
    "consistent body size across all 6 cells, facing right: "
    "Top-left (Col 1, Row 1): standing side-profile idle pose, cheerful alert posture, short white tail up. "
    "Top-middle (Col 2, Row 1): walking side-profile stride A, front-right and back-left paws stepping forward. "
    "Top-right (Col 3, Row 1): walking side-profile stride B, front-left and back-right paws stepping forward. "
    "Bottom-left (Col 1, Row 2): sitting facing front with a super cute head tilt, tiny pink tongue blep. "
    "Bottom-middle (Col 2, Row 2): curled up lying flat on belly sleeping peacefully, eyes closed. "
    "Bottom-right (Col 3, Row 2): being gently picked up from the scruff, dangling in mid-air with four stubby white paws hanging down and cute surprised expression."
)

TENNIS_PLAYER_PROPS_PROMPT = (
    "A clean 32-bit GBA Mario Tennis style pixel art game asset sheet on a completely transparent background. "
    "Arrange EXACTLY 6 evenly spaced separate items in an invisible 3 columns by 2 rows layout "
    "(NO grid lines, NO borders, NO text labels, NO ground shadows, generous empty transparent space between items, crisp dark pixel outlines): "
    "Top-left (Col 1, Row 1): cute chibi tennis player seen from behind (back 3/4 view facing UP toward top of screen), white sporty visor cap, forest-green polo shirt, white shorts, holding tennis racket in ready stance. "
    "Top-middle (Col 2, Row 1): same chibi tennis player seen from behind (facing UP) in energetic running stride with tennis racket. "
    "Top-right (Col 3, Row 1): same chibi tennis player seen from behind (facing UP) mid-forehand racket swing follow-through. "
    "Bottom-left (Col 1, Row 2): a single crisp pixel-art bright neon yellow-green tennis ball with white curved seam. "
    "Bottom-middle (Col 2, Row 2): a cute pixel-art white dog bone biscuit treat. "
    "Bottom-right (Col 3, Row 2): a cute pixel-art app badge icon of a fluffy white Westie puppy head wearing a green tennis headband holding a green tennis ball."
)

WESTIE_TENNIS_EDIT_PROMPT = (
    "Keep the EXACT same 32-bit pixel art West Highland White Terrier (Westie) character design, pixel style, proportions, "
    "sky-blue collar, and dark pixel outlines from the reference image. "
    "Create a new 6-pose sprite sheet on a completely transparent background arranged in an invisible 3 columns by 2 rows layout "
    "(NO grid lines, NO borders, NO text labels, NO ground shadows, generous transparent space around every pose): "
    "Top-left (Col 1, Row 1): Westie standing side-profile facing right, happily holding a bright neon-green tennis ball in its mouth, tail wagging. "
    "Top-middle (Col 2, Row 1): Westie facing front/downward (3/4 front view as top-of-court tennis opponent), wearing a tiny green tennis sweatband, holding a wooden-and-blue tennis racket in its mouth in ready stance. "
    "Top-right (Col 3, Row 1): same Westie with green headband facing front/downward, running fast side-to-side holding the tennis racket in its mouth. "
    "Bottom-left (Col 1, Row 2): same Westie with green headband facing front/downward, swinging the tennis racket in a dynamic forehand hit with a crisp pixel swing arc. "
    "Bottom-middle (Col 2, Row 2): same Westie with green headband diving sideways horizontally in mid-air to save a tough tennis shot. "
    "Bottom-right (Col 3, Row 2): same Westie jumping for joy on hind legs celebrating a point won."
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate WestieDeskPet pixel-art sprite sheets")
    parser.add_argument("--config-ini", help="Optional path to .config INI file")
    parser.add_argument(
        "--raw-dir",
        default=str(Path(__file__).resolve().parent.parent / "assets_raw"),
        help="Directory to write raw generated sheets",
    )
    args = parser.parse_args()

    endpoint, api_key = load_api_key(args.config_ini)
    raw_dir = Path(args.raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)

    companion_sheet = raw_dir / "westie_companion_sheet.png"
    player_props_sheet = raw_dir / "tennis_player_props_sheet.png"
    westie_tennis_sheet = raw_dir / "westie_tennis_sheet.png"

    print("Starting Pass 1 (parallel Flare + Sunburst generations)...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        fut_companion = pool.submit(
            generate_image,
            endpoint,
            api_key,
            FLARE_DEPLOYMENT,
            WESTIE_COMPANION_PROMPT,
            companion_sheet,
        )
        fut_player = pool.submit(
            generate_image,
            endpoint,
            api_key,
            SUNBURST_DEPLOYMENT,
            TENNIS_PLAYER_PROPS_PROMPT,
            player_props_sheet,
        )
        fut_companion.result()
        fut_player.result()

    print("Starting Pass 2 (reference-locked Westie tennis sheet on Flare)...", flush=True)
    edit_image_with_reference(
        endpoint,
        api_key,
        FLARE_DEPLOYMENT,
        companion_sheet,
        WESTIE_TENNIS_EDIT_PROMPT,
        westie_tennis_sheet,
    )
    print("All 3 raw pixel-art sprite sheets generated successfully!", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
