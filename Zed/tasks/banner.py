#!/usr/bin/env python3
import os
import sys
import subprocess
from pathlib import Path
from typing import cast
from io import TextIOWrapper

stdout = cast(TextIOWrapper, sys.stdout)
stdout.reconfigure(encoding="utf-8")

WIDTH = 80

# ----------------------------------------------------------------------
# Comment style detection
# ----------------------------------------------------------------------

COMMENT_PREFIXES = {
    ".py": "#",
    ".sh": "#",
    ".bash": "#",
    ".zsh": "#",
    ".yaml": "#",
    ".yml": "#",
    ".toml": "#",
    ".ini": "#",
    ".sql": "--",
    ".lua": "--",
}


def detect_prefix() -> str:
    file_path = os.environ.get("ZED_FILE", "")

    if file_path:
        ext = Path(file_path).suffix.lower()
        return COMMENT_PREFIXES.get(ext, "//")

    return "//"


# ----------------------------------------------------------------------
# Banner generation
# ----------------------------------------------------------------------


def make_banner(text: str, prefix: str, width: int = WIDTH) -> str:
    # Preserve indentation
    indent = text[: len(text) - len(text.lstrip())]
    clean = text.strip()

    if not clean:
        clean = "Header"

    start = f"{indent}{prefix} ─── {clean} "

    current = len(start)
    remaining = max(1, width - current)

    return start + ("─" * remaining)


# ----------------------------------------------------------------------
# Clipboard support
# ----------------------------------------------------------------------


def copy_to_clipboard(text: str) -> None:
    try:
        if sys.platform.startswith("win"):
            process = subprocess.Popen(
                ["clip"], stdin=subprocess.PIPE, shell=True
            )
            process.communicate(text.encode("utf-16le"))

        elif sys.platform == "darwin":
            process = subprocess.Popen(
                ["pbcopy"], stdin=subprocess.PIPE
            )
            process.communicate(text.encode("utf-8"))

        else:
            # Linux: try wl-copy first, then xclip
            for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard"]):
                try:
                    process = subprocess.Popen(cmd, stdin=subprocess.PIPE)
                    process.communicate(text.encode("utf-8"))
                    return
                except FileNotFoundError:
                    continue

    except Exception:
        pass


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------


def main():
    # Zed passes selected text as first argument
    text = sys.argv[1] if len(sys.argv) > 1 else ""

    prefix = detect_prefix()
    banner = make_banner(text, prefix)

    # Ensure UTF-8 output
    try:
        from io import TextIOWrapper
    
        if isinstance(sys.stdout, TextIOWrapper):
            sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    
    print(banner, end="")
    copy_to_clipboard(banner)


if __name__ == "__main__":
    main()
