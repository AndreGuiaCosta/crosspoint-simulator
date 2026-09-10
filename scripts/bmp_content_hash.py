#!/usr/bin/env python3
"""Hash a simulator screenshot's page content, ignoring the status bar.

Byte-exact screenshot comparison is what makes the pair harnesses able to say WHICH page a device
is showing rather than merely that two devices differ. It has one blind spot: the status bar is
part of those bytes, and it does not always say the same thing on a paired half as it does on the
solo reference walk the half is measured against.

Measured on 2026-09-10 with a controlled comparison -- a paired half and a solo reader at the same
position, from the same settings file, differing only in whether a peer is present. Exactly 14 rows
differ, always BMP rows 77-93 (BMPs are bottom-up, so screen y 386-402), and the page text is
identical to the pixel. The same 14 rows differ at spine 0 page 0 and at spine 1 page 0, on both
halves: it is peer presence in the status bar, not anything about position or timing. The reader
renders portrait on a landscape framebuffer, which is why the status bar is a band of ROWS rather
than a strip along the bottom of the image.

run_sim_pair_skip.sh re-measures this every run and prints the answer, so a change in the status
bar shows up as a changed observation line rather than as a mysterious harness failure.

So: hash everything except a band around that, and let the harness assert the page content while
staying silent about the chrome. The band is deliberately wider than the measured difference; the
body text does not reach into it.

Usage:
    python3 bmp_content_hash.py <file.bmp>     -> prints an md5 of the content region
"""

import hashlib
import struct
import sys

# BMP rows to leave out, as [first, last], in file order (bottom-up). Wider than the measured
# 77-93 on purpose; the body text does not reach into it.
STATUS_BAND = (60, 110)


def content_hash(path):
    data = open(path, "rb").read()
    if len(data) < 26 or data[:2] != b"BM":
        raise ValueError("%s: not a BMP" % path)
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    row_bytes = ((width + 31) // 32) * 4

    digest = hashlib.md5()
    digest.update(b"%d:%d:" % (width, height))
    for row in range(height):
        if STATUS_BAND[0] <= row <= STATUS_BAND[1]:
            continue
        start = pixel_offset + row * row_bytes
        digest.update(data[start:start + row_bytes])
    return digest.hexdigest()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: bmp_content_hash.py <file.bmp>\n")
        raise SystemExit(2)
    print(content_hash(sys.argv[1]))
