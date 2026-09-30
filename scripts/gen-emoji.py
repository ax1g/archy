#!/usr/bin/env python3
"""Regenerate data/emoji.txt, the list the SUPER+. picker searches.

The list is committed rather than generated at runtime, so the picker needs no
network access and no extra package on a machine that does not have Python.
That matters on a minimal system: an emoji picker is not worth a dependency.

Usage: python3 scripts/gen-emoji.py > data/emoji.txt

Filtering is by Unicode block plus name and general category, which is a
coarse approximation: a few dingbats and arrows that are not really emoji get
through, and nothing platform-specific is lost. It is good enough for a
searchable picker and it is honest about being generated rather than curated.
"""

import unicodedata

# The blocks Unicode emoji data occupies, plus the symbol blocks that carry the
# older pictographs.
RANGES = [
    (0x1F300, 0x1F5FF), (0x1F600, 0x1F64F), (0x1F680, 0x1F6FF),
    (0x1F700, 0x1F77F), (0x1F780, 0x1F7FF), (0x1F800, 0x1F8FF),
    (0x1F900, 0x1F9FF), (0x1FA00, 0x1FAFF), (0x2600, 0x26FF),
    (0x2700, 0x27BF), (0x2B00, 0x2BFF), (0x1F1E6, 0x1F1FF),
    (0x2190, 0x21FF), (0x3030, 0x3030), (0x303D, 0x303D),
    (0x00A9, 0x00A9), (0x00AE, 0x00AE), (0x203C, 0x2049),
    (0x2122, 0x2122), (0x2139, 0x2139), (0x24C2, 0x24C2),
    (0x25AA, 0x25AB), (0x25B6, 0x25B6), (0x25C0, 0x25C0),
    (0x25FB, 0x25FE), (0x2B50, 0x2B55), (0x2934, 0x2935),
    (0x2B05, 0x2B07), (0x2B1B, 0x2B1C), (0x3299, 0x3299),
]

# Blocks inside those ranges that are scripts, not pictographs.
SKIP_PREFIX = (
    "CJK", "HANGUL", "KANGXI", "TANGUT", "EGYPTIAN HIEROGLYPH",
    "CUNEIFORM", "LINEAR B", "BRAILLE", "ALCHEMICAL",
)


def collect():
    seen = set()
    found = []
    for lo, hi in RANGES:
        for cp in range(lo, hi + 1):
            ch = chr(cp)
            if ch in seen:
                continue
            try:
                name = unicodedata.name(ch)
                category = unicodedata.category(ch)
            except ValueError:
                continue
            if any(name.startswith(p) for p in SKIP_PREFIX):
                continue
            if category not in ("So", "Sk", "Sm", "Cs"):
                continue
            seen.add(ch)
            found.append((ch, name))
    return found


def main():
    found = collect()

    def sortkey(item):
        # Pictographs first, then symbols, then alphabetical by name, so the
        # unfiltered list starts with the things people reach for.
        ch, name = item
        return (0 if ord(ch[0]) >= 0x1F000 else 1, name)

    found.sort(key=sortkey)

    print("# archy: emoji list for the SUPER+. picker.")
    print("#")
    print("# Format: <emoji><TAB><unicode name>")
    print("#")
    print("# Generated from Python's unicodedata (%s), not fetched at runtime,"
          % unicodedata.unidata_version)
    print("# so the picker needs no network and no extra package. To refresh:")
    print("#   python3 scripts/gen-emoji.py > data/emoji.txt")
    print("#")
    for ch, name in found:
        print("%s\t%s" % (ch, name))


if __name__ == "__main__":
    main()
