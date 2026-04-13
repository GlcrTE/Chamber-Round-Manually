"""
Extract Charge animation from Attach_Empty animation.

Strategy:
  - Source_Animation  = Magazine_Attach_Empty  (the full visual animation in the weapon Rig scene)
  - Target_Animation  = Charge                  (the new animation we create, stored as a .tres)
  - Subtraction_Sound = $WeaponName_Charge.wav  (its duration tells us where to cut)

Cut-point formula:
  start_time = source_length - charge_sound_duration - BUFFER_SECONDS
  target_length = source_length - start_time   (= charge_sound_duration + BUFFER_SECONDS)

The target animation is the TAIL of the source animation, re-timed so it starts at t=0.

Usage:
  python extract_charge_animation.py [WeaponName]
  python extract_charge_animation.py Colt_1911
"""

import re
import sys
import wave
import contextlib
import os

# ── Configuration ──────────────────────────────────────────────────────────────
WEAPON_NAME        = sys.argv[1] if len(sys.argv) > 1 else "Colt_1911"
SOURCE_ANIM_NAME   = f"{WEAPON_NAME}_Magazine_Attach_Empty"  # Source_Animation
TARGET_ANIM_NAME   = f"{WEAPON_NAME}_Charge"                  # Target_Animation
BUFFER_SECONDS     = 0.2                                      # 200 ms upfront buffer

BASE_GAME_ROOT     = "D:/Mods/road to vostok"
WEAPON_DIR         = f"{BASE_GAME_ROOT}/Items/Weapons/{WEAPON_NAME}"
RIG_TSCN           = f"{WEAPON_DIR}/{WEAPON_NAME}_Rig.tscn"
CHARGE_WAV         = f"{WEAPON_DIR}/Audio/{WEAPON_NAME}_Charge.wav"
OUTPUT_DIR         = os.path.dirname(os.path.abspath(__file__))
OUTPUT_TRES        = os.path.join(OUTPUT_DIR, f"{TARGET_ANIM_NAME}.tres")

# ── Track element width per type ───────────────────────────────────────────────
# PackedFloat32Array layout: time, transition, values...
#   position_3d  → (time, trans, x, y, z)           = 5 floats/keyframe
#   rotation_3d  → (time, trans, x, y, z, w)        = 6 floats/keyframe
#   scale_3d     → (time, trans, x, y, z)            = 5 floats/keyframe
#   bezier       → (time, trans, value, ?, ?, ?, ?)  = 7 floats/keyframe (value+handles)
#   value        → (time, trans, value)               = 3 floats/keyframe  (scalar)
FLOATS_PER_KEY = {
    "position_3d": 5,
    "rotation_3d": 6,
    "scale_3d":    5,
    "bezier":      7,
    "value":       3,
    "method":      0,  # method tracks are different; skip
}

# ── Helpers ────────────────────────────────────────────────────────────────────

def wav_duration(path: str) -> float:
    with contextlib.closing(wave.open(path, "r")) as wf:
        return wf.getnframes() / float(wf.getframerate())


def parse_packed_float32(raw: str) -> list[float]:
    """Parse 'PackedFloat32Array(a, b, c, ...)' → [a, b, c, ...]."""
    inner = re.search(r"PackedFloat32Array\((.+)\)", raw, re.DOTALL)
    if not inner:
        return []
    return [float(x.strip()) for x in inner.group(1).split(",")]


def filter_and_retime_keys(floats: list[float], step: int,
                           start_time: float) -> tuple[list[float], int]:
    """
    Keep only keyframes with time >= start_time, subtract start_time from each.
    Returns (new_floats, count_dropped).
    """
    new_floats: list[float] = []
    dropped = 0
    i = 0
    while i + step <= len(floats):
        t = floats[i]
        if t < start_time - 1e-6:
            dropped += 1
        else:
            new_floats.append(round(t - start_time, 7))
            new_floats.extend(floats[i + 1: i + step])
        i += step
    return new_floats, dropped


def fmt_float(v: float) -> str:
    """Format a float the way Godot writes it (no unnecessary trailing zeros)."""
    s = f"{v:.7g}"
    return s


def packed_float32_str(floats: list[float]) -> str:
    """Serialize back to Godot's PackedFloat32Array(...)  literal."""
    return "PackedFloat32Array(" + ", ".join(fmt_float(v) for v in floats) + ")"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    # 1. Measure charge sound duration
    charge_duration = wav_duration(CHARGE_WAV)
    print(f"[{WEAPON_NAME}] Charge WAV duration   : {charge_duration:.4f}s")
    print(f"              Buffer                 : {BUFFER_SECONDS:.3f}s")

    # 2. Read the full Rig scene
    print(f"              Reading Rig scene      : {RIG_TSCN}")
    with open(RIG_TSCN, "r", encoding="utf-8") as fh:
        lines = fh.readlines()
    print(f"              Scene lines            : {len(lines)}")

    # 3. Find the Magazine_Attach_Empty animation block
    source_start_line = None
    source_end_line   = None
    source_length     = None

    in_source = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not in_source:
            if stripped.startswith("[sub_resource") or stripped.startswith("[resource"):
                in_source = False  # reset
            if f'resource_name = "{SOURCE_ANIM_NAME}"' in stripped:
                # The sub_resource header is one line above
                # Walk back to find it
                for back in range(idx, max(idx - 5, 0), -1):
                    if lines[back].strip().startswith("[sub_resource"):
                        source_start_line = back
                        break
                in_source = True
            continue
        # Inside the source animation block
        if stripped.startswith("[sub_resource") or stripped.startswith("[resource") or stripped.startswith("[node"):
            source_end_line = idx
            break
        if stripped.startswith("length ="):
            source_length = float(stripped.split("=")[1].strip())

    if source_start_line is None:
        raise RuntimeError(f"Could not find animation '{SOURCE_ANIM_NAME}' in {RIG_TSCN}")
    if source_end_line is None:
        source_end_line = len(lines)

    anim_block = lines[source_start_line:source_end_line]
    print(f"              Source anim lines      : {source_start_line} – {source_end_line}")
    print(f"              Source anim length     : {source_length}s")

    # 4. Calculate cut-point
    start_time    = source_length - charge_duration - BUFFER_SECONDS
    target_length = source_length - start_time          # = charge_duration + BUFFER_SECONDS
    print(f"              Cut start_time         : {start_time:.4f}s  "
          f"(= {source_length} - {charge_duration:.4f} - {BUFFER_SECONDS})")
    print(f"              Target anim length     : {target_length:.4f}s")

    if start_time < 0:
        raise ValueError(
            f"start_time ({start_time:.4f}s) is negative – "
            "charge sound + buffer is longer than the source animation!")

    # 5. Parse tracks and filter keyframes
    # Build a representation of the track properties
    track_data: list[dict] = []
    current_track: dict | None = None
    current_track_idx: int | None = None

    for line in anim_block:
        stripped = line.rstrip("\n")

        # Detect resource_name / length (animation-level properties)
        m_name = re.match(r'^resource_name\s*=\s*"(.+)"', stripped)
        if m_name:
            continue  # we'll write our own

        m_len = re.match(r'^length\s*=\s*(.+)', stripped)
        if m_len:
            continue  # we'll write our own

        # Detect new track header: tracks/N/type = "..."
        m_type = re.match(r'^(tracks/(\d+))/type\s*=\s*"(.+)"', stripped)
        if m_type:
            current_track_idx = int(m_type.group(2))
            current_track = {
                "index":      current_track_idx,
                "type":       m_type.group(3),
                "props":      {},   # other string props
                "keys_raw":   None,
            }
            track_data.append(current_track)
            continue

        if current_track is not None:
            # Keys line
            m_keys = re.match(r'^tracks/\d+/keys\s*=\s*(PackedFloat32Array\(.+\))', stripped)
            if m_keys:
                current_track["keys_raw"] = m_keys.group(1)
                continue

            # Other track properties
            m_prop = re.match(r'^(tracks/\d+/\w+)\s*=\s*(.+)', stripped)
            if m_prop:
                key_name = m_prop.group(1).split("/", 2)[2]  # strip "tracks/N/"
                current_track["props"][key_name] = m_prop.group(2)

    # 6. Retime each track
    print(f"\n  Processing {len(track_data)} tracks…")
    for td in track_data:
        track_type = td["type"]
        step = FLOATS_PER_KEY.get(track_type, 0)

        if step == 0 or td["keys_raw"] is None:
            print(f"    Track {td['index']:2d}  {track_type:15s} -> skipping (unsupported or empty)")
            td["new_keys_raw"] = td["keys_raw"]
            continue

        floats = parse_packed_float32(td["keys_raw"])
        total_keys = len(floats) // step
        new_floats, dropped = filter_and_retime_keys(floats, step, start_time)
        kept = len(new_floats) // step
        td["new_keys_raw"] = packed_float32_str(new_floats)
        path = td["props"].get("path", "")
        print(f"    Track {td['index']:2d}  {track_type:15s}  path={path}  "
              f"keys: {total_keys} -> {kept} (dropped {dropped})")

    # 7. Write the new .tres file
    lines_out: list[str] = []
    lines_out.append(f'[gd_resource type="Animation" format=3]\n')
    lines_out.append("\n")
    lines_out.append("[resource]\n")
    lines_out.append(f'resource_name = "{TARGET_ANIM_NAME}"\n')
    lines_out.append(f"length = {round(target_length, 7)}\n")

    for td in track_data:
        idx = td["index"]
        lines_out.append(f'tracks/{idx}/type = "{td["type"]}"\n')
        for prop_key, prop_val in td["props"].items():
            lines_out.append(f"tracks/{idx}/{prop_key} = {prop_val}\n")
        if td.get("new_keys_raw") is not None:
            lines_out.append(f"tracks/{idx}/keys = {td['new_keys_raw']}\n")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_TRES, "w", encoding="utf-8") as fh:
        fh.writelines(lines_out)

    print(f"\n  Written -> {OUTPUT_TRES}")
    print(f"\n  Summary")
    print(f"    Weapon              : {WEAPON_NAME}")
    print(f"    Source_Animation    : {SOURCE_ANIM_NAME}  ({source_length}s)")
    print(f"    Subtraction_Sound   : {WEAPON_NAME}_Charge.wav  ({charge_duration:.4f}s)")
    print(f"    Buffer              : {BUFFER_SECONDS * 1000:.0f} ms")
    print(f"    Cut point           : {start_time:.4f}s into source")
    print(f"    Target_Animation    : {TARGET_ANIM_NAME}  ({target_length:.4f}s)")
    print(f"    Output              : {OUTPUT_TRES}")


if __name__ == "__main__":
    main()
