import sys
from pathlib import Path

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE

src = Path(sys.argv[1])
out = Path(sys.argv[2])
img_dir = out / "pptx_images"
img_dir.mkdir(parents=True, exist_ok=True)

prs = Presentation(src)
lines = []


def walk(shapes, slide_no, depth=0):
    for sh in shapes:
        pad = "  " * depth
        if sh.shape_type == MSO_SHAPE_TYPE.GROUP:
            lines.append(f"{pad}[group {sh.name}]")
            walk(sh.shapes, slide_no, depth + 1)
            continue
        if sh.shape_type == MSO_SHAPE_TYPE.PICTURE:
            ext = sh.image.ext
            name = f"slide{slide_no:02d}_{sh.shape_id}.{ext}"
            (img_dir / name).write_bytes(sh.image.blob)
            lines.append(f"{pad}[image {name}]")
        if sh.has_text_frame and sh.text_frame.text.strip():
            lines.append(pad + sh.text_frame.text.replace("\n", " / "))
        if getattr(sh, "has_table", False) and sh.has_table:
            for row in sh.table.rows:
                lines.append(pad + "| " + " | ".join(c.text.replace("\n", " / ") for c in row.cells) + " |")


for i, slide in enumerate(prs.slides, 1):
    lines.append(f"\n=== SLIDE {i} ===")
    walk(slide.shapes, i)
    if slide.has_notes_slide and slide.notes_slide.notes_text_frame.text.strip():
        lines.append("NOTES: " + slide.notes_slide.notes_text_frame.text)

(out / "pptx.txt").write_text("\n".join(lines), encoding="utf-8")
print(len(prs.slides), "slides")
