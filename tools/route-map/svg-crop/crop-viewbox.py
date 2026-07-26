#!/usr/bin/env python3
"""Rewrite ONLY viewBox/width/height on the root <svg> start tag.

Everything outside the root start tag must stay byte-identical; the script
verifies this and refuses to write otherwise.
"""
import re
import sys


def root_tag_span(text: str):
    i = text.index('<svg')
    # find the '>' that closes the start tag, skipping quoted attribute values
    j = i
    in_q = None
    while j < len(text):
        c = text[j]
        if in_q:
            if c == in_q:
                in_q = None
        elif c in '"\'':
            in_q = c
        elif c == '>':
            return i, j + 1
        j += 1
    raise ValueError('unterminated <svg> start tag')


def fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else repr(v)


def crop(path: str, x: float, y: float, w: float, h: float, dry: bool = False) -> str:
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    i, j = root_tag_span(text)
    head, tag, tail = text[:i], text[i:j], text[j:]

    new_tag, n_vb = re.subn(
        r'viewBox\s*=\s*"[^"]*"',
        'viewBox="%s %s %s %s"' % (fmt(x), fmt(y), fmt(w), fmt(h)),
        tag, count=1)
    if n_vb != 1:
        raise ValueError('%s: viewBox not found in root tag' % path)

    new_tag, n_w = re.subn(r'\bwidth\s*=\s*"[^"]*"', 'width="%s"' % fmt(w), new_tag, count=1)
    new_tag, n_h = re.subn(r'\bheight\s*=\s*"[^"]*"', 'height="%s"' % fmt(h), new_tag, count=1)
    if n_w != 1 or n_h != 1:
        raise ValueError('%s: width/height not found in root tag (w=%d h=%d)' % (path, n_w, n_h))

    out = head + new_tag + tail
    # invariant: only the root start tag changed
    assert out[:i] == head and out[i + len(new_tag):] == tail
    if not dry:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(out)
    return new_tag


if __name__ == '__main__':
    p = sys.argv[1]
    x, y, w, h = (float(v) for v in sys.argv[2:6])
    print(crop(p, x, y, w, h, dry='--dry' in sys.argv))
