#!/usr/bin/env python3
"""Generate a multi-chapter EPUB fixture for the simulator harnesses.

`fs_/` is gitignored in the firmware repo, so a fixture book cannot be committed there. This
script is the committed form of it: run it and the book appears.

It exists because the only book in `fs_/books/` is `test_tables.epub`, whose spine is
cover + title page + two chapters of a few hundred bytes each. That is enough for a harness that
turns one page at a time and no more. Anything that has to cross a chapter boundary and land
somewhere -- a long-press chapter skip, a page-turn regression that wants a back-step to have
somewhere to come back from -- runs off the end of that book instead of testing what it claims.
`sim_page_turn.script` passes today for exactly that reason and asserts nothing.

The text is deterministic and numbered down to the sentence. That is not decoration: the pair
harnesses compare screenshots byte-for-byte against a solo reference walk, so two different pages
must never render identically, and the same generator input must produce the same page breaks on
every run.

Usage (from the firmware repo root):
    python <sim>/scripts/make_test_chapters_epub.py [out=fs_/books/test_chapters.epub]
"""

import os
import sys
import zipfile

TITLE = "Chapters? In CrossPoint?"
UUID = "urn:uuid:0c9b6f1e-3a5d-4f7c-9f2b-6d41a2c7e8b0"
DATE = "2026-09-10"

CHAPTERS = 6
PARAGRAPHS_PER_CHAPTER = 9
SENTENCES_PER_PARAGRAPH = 6

# Roughly 4,500 characters per chapter, which lays out to about five pages at the default font and
# margins. Long enough that a cold build of one is visible in a log; short enough that a harness
# that walks several of them still finishes inside its timeout.
SENTENCE = ("This is chapter {c}, paragraph {p}, sentence {s}, written out at a length that fills "
            "a line or two of the display so the page breaks land somewhere stable.")

CSS = """\
body { margin: 0; padding: 0; }
h1 { font-size: 1.4em; margin: 0.6em 0; }
p { margin: 0 0 0.6em 0; text-align: left; }
"""

CHAPTER_XHTML = """\
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en-US" xml:lang="en-US">
<head>
  <meta charset="utf-8" />
  <title>ch{num:03d}.xhtml</title>
  <link rel="stylesheet" type="text/css" href="../styles/stylesheet1.css" />
</head>
<body epub:type="bodymatter">
<section id="chapter-{num}" class="level1">
<h1>Chapter {num}</h1>
{body}
</section>
</body>
</html>
"""


def chapter_body(num):
    paragraphs = []
    for p in range(1, PARAGRAPHS_PER_CHAPTER + 1):
        sentences = [SENTENCE.format(c=num, p=p, s=s) for s in range(1, SENTENCES_PER_PARAGRAPH + 1)]
        paragraphs.append("<p>" + " ".join(sentences) + "</p>")
    return "\n".join(paragraphs)


def content_opf():
    manifest = [
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml" />',
        '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />',
        '    <item id="stylesheet1" href="styles/stylesheet1.css" media-type="text/css" />',
    ]
    spine = []
    for n in range(1, CHAPTERS + 1):
        manifest.append(
            '    <item id="ch{n:03d}_xhtml" href="text/ch{n:03d}.xhtml" '
            'media-type="application/xhtml+xml" />'.format(n=n))
        spine.append('    <itemref idref="ch{n:03d}_xhtml" />'.format(n=n))
    return """\
<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" xml:lang="en-US" unique-identifier="epub-id-1">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="epub-id-1">{uuid}</dc:identifier>
    <dc:title id="epub-title-1">{title}</dc:title>
    <meta refines="#epub-title-1" property="title-type">main</meta>
    <dc:date id="epub-date">{date}</dc:date>
    <dc:language>en-US</dc:language>
    <meta property="dcterms:modified">{date}T00:00:00Z</meta>
  </metadata>
  <manifest>
{manifest}
  </manifest>
  <spine toc="ncx">
{spine}
  </spine>
</package>
""".format(uuid=UUID, title=TITLE, date=DATE,
           manifest="\n".join(manifest), spine="\n".join(spine))


def toc_ncx():
    points = []
    for n in range(1, CHAPTERS + 1):
        points.append("""\
    <navPoint id="navPoint-{n}">
      <navLabel>
        <text>Chapter {n}</text>
      </navLabel>
      <content src="text/ch{n:03d}.xhtml#chapter-{n}" />
    </navPoint>""".format(n=n))
    return """\
<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="{uuid}" />
    <meta name="dtb:depth" content="1" />
    <meta name="dtb:totalPageCount" content="0" />
    <meta name="dtb:maxPageNumber" content="0" />
  </head>
  <docTitle>
    <text>{title}</text>
  </docTitle>
  <navMap>
{points}
  </navMap>
</ncx>
""".format(uuid=UUID, title=TITLE, points="\n".join(points))


def nav_xhtml():
    items = "".join(
        '<li id="toc-li-{n}"><a href="text/ch{n:03d}.xhtml#chapter-{n}">Chapter {n}</a></li>'.format(n=n)
        for n in range(1, CHAPTERS + 1))
    return """\
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en-US" xml:lang="en-US">
<head>
  <meta charset="utf-8" />
  <title>{title}</title>
  <link rel="stylesheet" type="text/css" href="styles/stylesheet1.css" />
</head>
<body epub:type="frontmatter">
<nav epub:type="toc" role="doc-toc" id="toc"><h1 id="toc-title">{title}</h1><ol class="toc">{items}</ol></nav>
</body>
</html>
""".format(title=TITLE, items=items)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "fs_/books/test_chapters.epub"
    parent = os.path.dirname(out)
    if parent:
        os.makedirs(parent, exist_ok=True)

    # Deterministic archive: a fixed timestamp on every entry so two runs of this script produce
    # byte-identical books. The book's path is what the cache hash is taken from, not its bytes, but
    # a fixture that changes under a harness is a debugging trap nobody needs.
    stamp = (2026, 9, 10, 0, 0, 0)

    def write(z, name, data, compress=zipfile.ZIP_DEFLATED):
        info = zipfile.ZipInfo(name, date_time=stamp)
        info.compress_type = compress
        info.external_attr = 0o644 << 16
        z.writestr(info, data)

    with zipfile.ZipFile(out, "w") as z:
        # The mimetype entry must be first and stored uncompressed.
        write(z, "mimetype", "application/epub+zip", zipfile.ZIP_STORED)
        write(z, "META-INF/container.xml", """\
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml" />
  </rootfiles>
</container>
""")
        write(z, "EPUB/content.opf", content_opf())
        write(z, "EPUB/toc.ncx", toc_ncx())
        write(z, "EPUB/nav.xhtml", nav_xhtml())
        write(z, "EPUB/styles/stylesheet1.css", CSS)
        for n in range(1, CHAPTERS + 1):
            write(z, "EPUB/text/ch{n:03d}.xhtml".format(n=n),
                  CHAPTER_XHTML.format(num=n, body=chapter_body(n)))

    size = os.path.getsize(out)
    print("wrote {} ({} bytes, {} spine items)".format(out, size, CHAPTERS))


if __name__ == "__main__":
    main()
