#!/usr/bin/env python3
"""Validate the JSONC files in the repo.

fastfetch's config and Waybar's config are JSONC: JSON with // and /* */ comments.
A naive comment strip is not good enough to check them, because stripping "//"
textually also eats the "//" in a URL. The $schema key is a https:// link, so
that is not a hypothetical.

Usage: scripts/check-jsonc.py <file>...
Exits non-zero on the first file that does not parse.
"""

import json
import re
import sys


def strip_jsonc(text):
    """Remove // and /* */ comments that are not inside a JSON string."""
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        ch = text[i]

        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                # Escaped character inside the string, including an escaped
                # quote. Consume both so the quote does not end the string.
                out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue

        if ch == "/" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "/":
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if nxt == "*":
                end = text.find("*/", i + 2)
                if end == -1:
                    raise ValueError("unterminated block comment")
                i = end + 2
                continue

        out.append(ch)
        i += 1

    if in_string:
        raise ValueError("unterminated string")
    return "".join(out)


def check(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    try:
        return json.loads(strip_jsonc(text))
    except ValueError as err:
        raise ValueError(f"{path}: {err}")


def main(argv):
    if len(argv) < 2:
        print("usage: check-jsonc.py <file>...", file=sys.stderr)
        return 2

    failed = False
    for path in argv[1:]:
        try:
            data = check(path)
        except (ValueError, OSError) as err:
            print(f"  FAIL {err}")
            failed = True
            continue

        # A trailing comma before a closing brace is what people actually get
        # wrong in JSONC, and json.loads rejects it.
        keys = list(data.keys()) if isinstance(data, dict) else []
        print(f"  ok   {path} ({len(keys)} top-level keys, "
              f"{len(data.get('modules', []))} modules)"
              if isinstance(data, dict) else f"  ok   {path}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
