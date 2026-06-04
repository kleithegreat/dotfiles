#!/usr/bin/env python3
"""Point Discord's voice module at the deployed Nix-managed Krisp module."""

import json
import sys
from pathlib import Path


SETUP_KRISP = """VoiceEngine.setupKrispPath = function () {
    const krispPath = discordNative?.nativeModules?.getModulePath('discord_krisp');
    if (krispPath != null) {
        VoiceEngine.setKrispPath(krispPath);
    }
};"""


def patch_voice(path: Path, runtime_path_js: str) -> None:
    text = path.read_text(encoding="utf-8")
    replacement = f"""const nixKrispPath = {runtime_path_js};
try {{
    require(nixKrispPath);
}}
catch (e) {{
    console.warn('Failed to initialize Krisp via Nix module before voice engine setup:', e);
}}
VoiceEngine.setKrispPath(nixKrispPath);
VoiceEngine.setupKrispPath = function () {{
    VoiceEngine.setKrispPath(nixKrispPath);
}};"""
    if SETUP_KRISP not in text:
        raise SystemExit(f"could not find Krisp setup hook in {path}")
    path.write_text(text.replace(SETUP_KRISP, replacement), encoding="utf-8")


def patch_build_info(path: Path, modules_root: str) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    data["localModulesRoot"] = modules_root
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            f"Usage: {sys.argv[0]} <voice-index.js> <runtime-path-js> <build-info.json> <modules-root>"
        )

    patch_voice(Path(sys.argv[1]), sys.argv[2])
    patch_build_info(Path(sys.argv[3]), sys.argv[4])


if __name__ == "__main__":
    main()
