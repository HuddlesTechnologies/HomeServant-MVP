"""Builds the PDF guides in docs/ from the HTML sources in this folder.

    python3 docs/guides/build.py

Each <name>.html here holds only the document body; this script wraps it
in the shared page template/stylesheet below and prints it to
docs/<Title>.pdf with headless Chromium (the same engine a browser's
"Save as PDF" uses). Edit the .html, re-run, commit both.
"""

import datetime
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)

GUIDES = [
    ("admin_guide.html", "Admin Guide", "How to run the HomeServant admin console"),
    ("frontend_guide.html", "Frontend Developer Guide", "How the HomeServant Flutter app is built"),
    ("backend_guide.html", "Backend Developer Guide", "How the HomeServant API is built"),
]

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
* { box-sizing: border-box; }
body { font-family: 'DejaVu Sans', 'Liberation Sans', Arial, sans-serif; color: #14213d; font-size: 10.2pt; line-height: 1.5; margin: 0; }
.cover { height: 250mm; display: flex; flex-direction: column; justify-content: center; page-break-after: always; }
.cover .brand { color: #c9a227; font-weight: 700; letter-spacing: 3px; font-size: 11pt; text-transform: uppercase; }
.cover h1 { font-size: 34pt; margin: 8px 0 6px; color: #14213d; border: none; page-break-before: auto; }
.cover .sub { font-size: 14pt; color: #4a5568; }
.cover .meta { margin-top: 40px; font-size: 9.5pt; color: #6b7280; }
.cover .bar { width: 80px; height: 6px; background: #c9a227; margin: 18px 0; border-radius: 3px; }
h1 { font-size: 19pt; color: #14213d; border-bottom: 3px solid #c9a227; padding-bottom: 4px; margin: 0 0 12px; page-break-before: always; }
h1.first { page-break-before: auto; }
h2 { font-size: 13.5pt; color: #14213d; margin: 20px 0 6px; page-break-after: avoid; }
h3 { font-size: 11pt; color: #1f3a68; margin: 14px 0 4px; page-break-after: avoid; }
p { margin: 5px 0 8px; }
ul, ol { margin: 4px 0 10px; padding-left: 20px; }
li { margin: 2px 0; }
code { font-family: 'DejaVu Sans Mono', 'Liberation Mono', monospace; font-size: 8.8pt; background: #f1f3f7; padding: 1px 4px; border-radius: 3px; color: #1f2a44; }
pre { font-family: 'DejaVu Sans Mono', 'Liberation Mono', monospace; font-size: 8.4pt; background: #0f1b33; color: #e8edf7; padding: 10px 12px; border-radius: 6px; white-space: pre-wrap; word-break: break-word; page-break-inside: avoid; }
pre code { background: none; color: inherit; padding: 0; }
table { width: 100%; border-collapse: collapse; margin: 6px 0 12px; font-size: 9pt; page-break-inside: auto; }
tr { page-break-inside: avoid; }
th { background: #14213d; color: #ffffff; text-align: left; padding: 5px 7px; font-weight: 600; }
td { border-bottom: 1px solid #dde2ea; padding: 5px 7px; vertical-align: top; }
tr:nth-child(even) td { background: #f7f8fb; }
.yes { color: #13733f; font-weight: 700; }
.no { color: #b42318; font-weight: 700; }
.ro { color: #9a6700; font-weight: 700; }
.note, .warn, .tip { border-radius: 6px; padding: 8px 12px; margin: 10px 0; page-break-inside: avoid; }
.note { background: #eef3fb; border-left: 4px solid #1f3a68; }
.tip { background: #edf8f1; border-left: 4px solid #13733f; }
.warn { background: #fdf1ef; border-left: 4px solid #b42318; }
.toc { page-break-after: always; }
.toc h1 { page-break-before: auto; }
.toc ol { font-size: 11pt; line-height: 1.9; }
.small { font-size: 8.8pt; color: #4a5568; }
.step { font-weight: 700; color: #1f3a68; }
"""

TEMPLATE = """<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<style>{css}</style></head><body>
<div class="cover">
  <div class="brand">HomeServant</div>
  <div class="bar"></div>
  <h1>{title}</h1>
  <div class="sub">{subtitle}</div>
  <div class="meta">Version of {date}. Written from the code in the HomeServant-MVP repository.<br>
  Source: <code>docs/guides/{source}</code> — rebuild with <code>python3 docs/guides/build.py</code>.</div>
</div>
{body}
</body></html>"""


def find_chrome() -> str:
    for candidate in (
        os.environ.get("CHROME"),
        "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
        shutil.which("chromium"),
        shutil.which("google-chrome"),
        shutil.which("chrome"),
    ):
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit("No Chromium found: set CHROME=/path/to/chrome")


def main() -> None:
    chrome = find_chrome()
    today = datetime.date.today().strftime("%d %B %Y")
    only = set(sys.argv[1:])  # optional: build just these sources, e.g. admin_guide.html
    for source, title, subtitle in GUIDES:
        if only and source not in only:
            continue
        with open(os.path.join(HERE, source), encoding="utf-8") as f:
            body = f.read()
        html = TEMPLATE.format(title=title, subtitle=subtitle, css=CSS, body=body, date=today, source=source)
        with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
            tmp.write(html)
            tmp_path = tmp.name
        out = os.path.join(DOCS, f"{title}.pdf")
        subprocess.run(
            [
                chrome,
                "--headless",
                "--no-sandbox",
                "--disable-gpu",
                "--no-pdf-header-footer",
                f"--print-to-pdf={out}",
                f"file://{tmp_path}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.unlink(tmp_path)
        print(f"wrote {out}")


if __name__ == "__main__":
    main()
