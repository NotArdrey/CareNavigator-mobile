from __future__ import annotations

from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent
FONT_PATH = Path(r"C:\Windows\Fonts\CascadiaMono.ttf")
if not FONT_PATH.exists():
    FONT_PATH = Path(r"C:\Windows\Fonts\consola.ttf")


PALETTE = {
    "bg": "#0B1220",
    "panel": "#111827",
    "bar": "#0F766E",
    "line": "#334155",
    "text": "#E5E7EB",
    "muted": "#94A3B8",
    "keyword": "#67E8F9",
    "string": "#A7F3D0",
    "number": "#FDE68A",
    "comment": "#94A3B8",
    "name": "#F8FAFC",
    "operator": "#F9A8D4",
}


def read_lines(relative: str, start: int, end: int) -> str:
    lines = (ROOT / relative).read_text(encoding="utf-8").splitlines()
    selected = lines[start - 1 : end]
    width = len(str(end))
    output = []
    for line_no, line in enumerate(selected, start=start):
        chunks = []
        remaining = line
        while len(remaining) > 104:
            cut = remaining.rfind(",", 48, 104)
            if cut < 0:
                cut = 104
            else:
                cut += 1
            chunks.append(remaining[:cut])
            indent = " " * (len(line) - len(line.lstrip()) + 4)
            remaining = indent + remaining[cut:].lstrip()
        chunks.append(remaining)
        output.append(f"{line_no:>{width}}  {chunks[0]}")
        output.extend(f"{'':>{width}}  {chunk}" for chunk in chunks[1:])
    return "\n".join(output)


KEYWORDS = {
    "abstract", "async", "await", "bool", "catch", "class", "const",
    "dynamic", "else", "extends", "factory", "false", "final", "for",
    "Future", "if", "implements", "import", "in", "interface", "List",
    "Map", "new", "null", "override", "required", "return", "Stream",
    "String", "throw", "true", "try", "var", "void", "while",
}


TOKEN_RE = re.compile(
    r"(//.*$|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|"
    r"\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b|[{}\[\]().,:;?=!<>+*/-]+)"
)


def lex_line(line: str):
    cursor = 0
    for match in TOKEN_RE.finditer(line):
        if match.start() > cursor:
            yield line[cursor : match.start()], PALETTE["text"]
        text = match.group(0)
        if text.startswith("//"):
            color = PALETTE["comment"]
        elif text.startswith(("'", '"')):
            color = PALETTE["string"]
        elif text[0].isdigit():
            color = PALETTE["number"]
        elif text in KEYWORDS:
            color = PALETTE["keyword"]
        elif re.fullmatch(r"[{}\[\]().,:;?=!<>+*/-]+", text):
            color = PALETTE["operator"]
        else:
            color = PALETTE["name"]
        yield text, color
        cursor = match.end()
    if cursor < len(line):
        yield line[cursor:], PALETTE["text"]


def render_code(
    title: str,
    subtitle: str,
    code: str,
    output: str,
    width: int = 1800,
) -> None:
    font = ImageFont.truetype(str(FONT_PATH), 25)
    title_font = ImageFont.truetype(str(FONT_PATH), 30)
    subtitle_font = ImageFont.truetype(str(FONT_PATH), 20)
    line_height = 38
    header_height = 112
    pad_x = 42
    pad_bottom = 38
    lines = code.splitlines() or [""]
    height = header_height + pad_bottom + line_height * len(lines)
    image = Image.new("RGB", (width, height), PALETTE["bg"])
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((18, 18, width - 18, height - 18), 18, fill=PALETTE["panel"], outline=PALETTE["line"], width=2)
    draw.rounded_rectangle((18, 18, width - 18, header_height), 18, fill=PALETTE["bar"])
    draw.rectangle((18, header_height - 18, width - 18, header_height), fill=PALETTE["bar"])
    draw.text((pad_x, 34), title, font=title_font, fill="#FFFFFF")
    draw.text((pad_x, 76), subtitle, font=subtitle_font, fill="#CCFBF1")

    y = header_height + 22
    for raw_line in lines:
        x = pad_x
        for text, color in lex_line(raw_line):
            draw.text((x, y), text, font=font, fill=color)
            x += draw.textlength(text, font=font)
        y += line_height
    image.save(OUT / output, dpi=(180, 180))


render_code(
    "HTTP GET request - Supabase hospital directory",
    "lib/src/repositories/hospital_repository.dart",
    read_lines("lib/src/repositories/hospital_repository.dart", 25, 43),
    "api_get_implementation.png",
)

render_code(
    "HTTP POST request - guest consultation creation",
    "lib/src/repositories/consultation_repository.dart",
    read_lines("lib/src/repositories/consultation_repository.dart", 223, 251),
    "api_post_implementation.png",
)

render_code(
    "JSON parsing and application model mapping",
    "lib/src/repositories/hospital_repository.dart",
    read_lines("lib/src/repositories/hospital_repository.dart", 192, 217),
    "json_processing_implementation.png",
)

render_code(
    "Live JSON response sample",
    "GET /rest/v1/hospitals - captured August 15, 2026",
    (OUT / "api_response_sample.json").read_text(encoding="utf-8"),
    "api_json_response.png",
    width=1550,
)
