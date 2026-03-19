"""Target registry — auto-discovers all target modules in this package."""

from __future__ import annotations

import importlib
from pathlib import Path
from types import ModuleType

_TARGETS_DIR = Path(__file__).parent

# Registry: TARGET_NAME -> module
REGISTRY: dict[str, ModuleType] = {}


def _discover() -> None:
    """Import every .py file in this directory and register modules with TARGET_NAME."""
    for py in sorted(_TARGETS_DIR.glob("*.py")):
        if py.name.startswith("_"):
            continue
        mod = importlib.import_module(f".{py.stem}", __package__)
        name = getattr(mod, "TARGET_NAME", None)
        if name is None:
            continue
        if name in REGISTRY:
            raise RuntimeError(
                f"Duplicate TARGET_NAME '{name}': "
                f"{REGISTRY[name].__name__} and {mod.__name__}"
            )
        REGISTRY[name] = mod


_discover()
