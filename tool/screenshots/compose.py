"""Turns the raw captures into the images the README links to.

`test/screenshots/screens_test.dart` writes full-resolution frames to
`docs/images/raw`, which is deliberately not committed: it is eight megabytes of
PNG, most of it intermediate. This script is the second half of that pipeline. It
produces everything under `docs/images` -- rounded phone shots, the labelled grid
of the eight steps, the animations, and a strip of real pages from the generated
PDF -- at sizes that keep the repository small enough to clone comfortably.

Run it from the project root, after the capture:

    flutter test test/screenshots --dart-define=capture=true
    python tool/screenshots/compose.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "docs" / "images" / "raw"
OUT = ROOT / "docs" / "images"

# The capture is a 390x844 logical phone at a device pixel ratio of 2.
SHOT = (780, 1688)

INK = (26, 32, 36)
MUTED = (91, 103, 112)
EDGE = (205, 216, 221)
BRAND = (20, 108, 122)
PAPER = (244, 249, 251)


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #


def load(name: str) -> Image.Image:
    path = RAW / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"missing capture: {path}\nRun the capture test first.")
    return Image.open(path).convert("RGB")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """A real font, falling back to Pillow's bitmap one if none is installed."""
    candidates = (
        ["arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"]
        if bold
        else ["arial.ttf", "segoeui.ttf", "DejaVuSans.ttf"]
    )
    for name in candidates:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def phone(
    image: Image.Image,
    width: int,
    *,
    crop: tuple[float, float] | None = None,
    shadow: bool = True,
) -> Image.Image:
    """A screenshot as a rounded phone, on transparency so either theme suits it.

    [crop] takes a fraction of the height, as (top, bottom), for the shots where
    only one card matters.
    """
    if crop:
        top, bottom = crop
        image = image.crop(
            (0, int(image.height * top), image.width, int(image.height * bottom))
        )

    height = round(width * image.height / image.width)
    image = image.resize((width, height), Image.LANCZOS)

    radius = max(8, round(width * 0.055))
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width - 1, height - 1), radius=radius, fill=255
    )

    rounded = Image.new("RGBA", (width, height))
    rounded.paste(image, (0, 0), mask)
    ImageDraw.Draw(rounded).rounded_rectangle(
        (0, 0, width - 1, height - 1), radius=radius, outline=EDGE + (255,), width=2
    )
    if not shadow:
        return rounded

    pad = max(6, width // 26)
    canvas = Image.new("RGBA", (width + 2 * pad, height + 2 * pad), (0, 0, 0, 0))
    blur = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(blur).rounded_rectangle(
        (pad, pad + pad // 3, pad + width, pad + height + pad // 3),
        radius=radius,
        fill=(15, 40, 46, 58),
    )
    canvas.alpha_composite(blur.filter(ImageFilter.GaussianBlur(pad / 2.2)))
    canvas.alpha_composite(rounded, (pad, pad))
    return canvas


def row(images: list[Image.Image], gap: int = 28) -> Image.Image:
    width = sum(i.width for i in images) + gap * (len(images) - 1)
    height = max(i.height for i in images)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = 0
    for image in images:
        canvas.alpha_composite(image, (x, (height - image.height) // 2))
        x += image.width + gap
    return canvas


def save(image: Image.Image, name: str) -> None:
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f"  {name:<34} {path.stat().st_size / 1024:7.0f} kB  {image.size}")


# --------------------------------------------------------------------------- #
# the pieces
# --------------------------------------------------------------------------- #


def singles() -> None:
    """One screenshot per file, named and sized the way the README asks for it.

    Keyed by the name the capture wrote, mapped to the published name and width.
    Only what the README actually uses is produced: an image nobody links to is
    weight in every clone for nothing.
    """
    wanted = {
        "onboarding": ("onboarding", 260),
        "consent": ("consent", 260),
        "checkin": ("checkin", 260),
        "dashboard-start": ("dashboard-start", 260),
        "dashboard": ("dashboard", 260),
        "dashboard-change": ("dashboard-change", 260),
        "results-card-open": ("results-card-open", 260),
        "metric-detail": ("compare-chart", 300),
        "metric-detail-2": ("compare-three-ways", 300),
        "trends-change": ("trends-change", 300),
        "trends-3": ("trends-areas", 260),
        "every-test": ("every-test", 260),
        "report-options": ("report-options", 260),
        "report-contents": ("report-contents", 260),
        "privacy": ("privacy", 260),
        "profile": ("profile", 260),
    }
    print("screenshots")
    for name, (published, width) in wanted.items():
        save(phone(load(name), width), f"{published}.png")


def hero() -> None:
    """Three phones: where you start, what a step looks like, what it tells you."""
    print("hero")
    save(
        row(
            [
                phone(load("dashboard"), 290),
                phone(load("step-4-spiral"), 290),
                phone(load("trends-change"), 290),
            ],
            gap=24,
        ),
        "hero.png",
    )


STEPS = [
    ("step-1-words", "1 · Word memory", "Eight words, typed back twice"),
    ("step-2-reaction-go", "2 · Reaction time", "Tap the moment the circle turns"),
    ("step-3-speech", "3 · Speech", "Describe a picture aloud for 20 seconds"),
    ("step-4-spiral", "4 · Spiral tracing", "Follow the guide with one finger"),
    ("step-5-typing", "5 · Typing rhythm", "Nothing to do: timed while you type"),
    ("step-6-trail-active", "6 · Trail making", "1, A, 2, B, 3, C, in order"),
    ("step-7-tapping-active", "7 · Finger tapping", "Two buttons in turn for 10 seconds"),
    ("step-8-fluency-active", "8 · Verbal fluency", "As many animals as you can"),
]


def wrap(draw, text, typeface, width):
    """Breaks [text] into lines that fit [width]."""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=typeface) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def eight_steps() -> None:
    """The whole test as one labelled grid, on the app's own background."""
    print("the eight steps")
    cell_w, cols, gap, pad = 230, 4, 26, 30
    shots = [phone(load(name), cell_w, shadow=False) for name, _, _ in STEPS]
    shot_h = shots[0].height
    title_f, sub_f = font(19, bold=True), font(15)
    caption_h = 66
    rows = (len(STEPS) + cols - 1) // cols

    width = cols * cell_w + (cols - 1) * gap + 2 * pad
    height = rows * (shot_h + caption_h) + (rows - 1) * gap + 2 * pad
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(canvas).rounded_rectangle(
        (0, 0, width - 1, height - 1), radius=18, fill=PAPER + (255,)
    )
    draw = ImageDraw.Draw(canvas)

    for index, (shot, (_, title, subtitle)) in enumerate(zip(shots, STEPS)):
        x = pad + (index % cols) * (cell_w + gap)
        y = pad + (index // cols) * (shot_h + caption_h + gap)
        draw.text((x, y), title, font=title_f, fill=BRAND)
        for line_no, line in enumerate(wrap(draw, subtitle, sub_f, cell_w)[:2]):
            draw.text((x, y + 25 + line_no * 19), line, font=sub_f, fill=MUTED)
        canvas.alpha_composite(shot, (x, y + caption_h))

    save(canvas, "eight-steps.png")


def animations() -> None:
    """The recorded frame sequences, as GIFs small enough to sit in a README."""
    wanted = {
        # name: (width, milliseconds per frame, milliseconds on the last frame)
        "full-test": (300, 1100, 2200),
        "spiral": (300, 160, 1400),
        "trail": (300, 420, 1200),
        "reaction": (300, 420, 1200),
        "results": (300, 420, 1600),
    }
    print("animations")
    for name, (width, each, last) in wanted.items():
        folder = RAW / "frames" / name
        files = sorted(folder.glob("*.png"))
        if not files:
            print(f"  (no frames for {name})")
            continue

        frames = []
        for file in files:
            image = Image.open(file).convert("RGB")
            height = round(width * image.height / image.width)
            frames.append(
                image.resize((width, height), Image.LANCZOS).quantize(
                    colors=128, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG
                )
            )

        durations = [each] * len(frames)
        durations[-1] = last
        path = OUT / f"{name}.gif"
        frames[0].save(
            path,
            save_all=True,
            append_images=frames[1:],
            duration=durations,
            loop=0,
            optimize=True,
        )
        print(f"  {name + '.gif':<34} {path.stat().st_size / 1024:7.0f} kB  "
              f"{len(frames)} frames  {frames[0].size}")


def report_pages() -> None:
    """Real pages from the PDF the app generated during the capture."""
    pdf = RAW / "report.pdf"
    if not pdf.exists():
        print("report pages: no report.pdf, skipping")
        return
    try:
        import fitz  # PyMuPDF
    except ImportError:
        print("report pages: PyMuPDF is not installed, skipping")
        return

    print("report pages")
    document = fitz.open(pdf)
    wanted = [0, 2, 4, 7]
    pages = []
    for index in wanted:
        if index >= len(document):
            continue
        pixmap = document[index].get_pixmap(dpi=110)
        page = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
        width = 250
        height = round(width * page.height / page.width)
        page = page.resize((width, height), Image.LANCZOS)
        framed = Image.new("RGBA", (width, height))
        framed.paste(page, (0, 0))
        ImageDraw.Draw(framed).rectangle(
            (0, 0, width - 1, height - 1), outline=EDGE + (255,), width=2
        )
        pages.append(framed)

    save(row(pages, gap=18), "report-pages.png")


def main() -> int:
    if not RAW.exists():
        print(
            "No captures found. Run:\n"
            "  flutter test test/screenshots --dart-define=capture=true",
            file=sys.stderr,
        )
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    singles()
    hero()
    eight_steps()
    animations()
    report_pages()

    total = sum(f.stat().st_size for f in OUT.glob("*") if f.is_file())
    print(f"\n{total / 1024 / 1024:.1f} MB in docs/images")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
