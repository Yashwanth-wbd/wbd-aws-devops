import sys
from pathlib import Path

import docx
import openpyxl

src = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

d = docx.Document(src / "wbd_mmm_ecs_final.docx")
lines = []
for block in d.element.body.iterchildren():
    tag = block.tag.split("}")[1]
    if tag == "p":
        p = docx.text.paragraph.Paragraph(block, d)
        if p.text.strip():
            style = p.style.name if p.style is not None else ""
            prefix = "#" * int(style[-1]) + " " if style.startswith("Heading") and style[-1].isdigit() else ""
            lines.append(prefix + p.text)
    elif tag == "tbl":
        t = docx.table.Table(block, d)
        for row in t.rows:
            cells = []
            for c in row.cells:
                txt = c.text.replace("\n", " / ").strip()
                if not cells or cells[-1] != txt:
                    cells.append(txt)
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
(out / "ecs_doc.txt").write_text("\n".join(lines), encoding="utf-8")

wb = openpyxl.load_workbook(src / "aws_resource_list.xlsx", data_only=True)
xl = []
for ws in wb.worksheets:
    xl.append(f"=== SHEET {ws.title} ({ws.max_row} rows) ===")
    for row in ws.iter_rows(values_only=True):
        if any(v is not None for v in row):
            xl.append(" | ".join("" if v is None else str(v).replace("\n", " / ") for v in row))
(out / "resources.txt").write_text("\n".join(xl), encoding="utf-8")
print("ok")
