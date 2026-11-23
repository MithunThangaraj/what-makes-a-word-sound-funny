"""Build the EL161 report (Word + PDF) in the style of the course's Report Example.

Content comes from ../poster_outputs/report_content.json, written by analysis.R
(step 10), so every number comes from the analysis.

    python build_report.py [DATA_CODE_URL]

If no URL is given, "here" is shown with a highlighted placeholder.
Then: soffice --headless --convert-to pdf EL161_report_Mithun.docx
"""
import json
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_COLOR_INDEX
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.opc.constants import RELATIONSHIP_TYPE as RT
from docx.shared import Cm, Pt, RGBColor

HERE = Path(__file__).resolve().parent
CONTENT = HERE.parent / "poster_outputs" / "report_content.json"
OUT = HERE / "EL161_report_Mithun.docx"
URL = sys.argv[1] if len(sys.argv) > 1 else ""
FONT, SIZE, REF_SIZE = "Times New Roman", 11.5, 10.5


def style_run(run, size=SIZE, bold=False, italic=False):
    run.font.name = FONT
    run._element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
    run.font.size = Pt(size)
    run.bold, run.italic = bold, italic
    return run


def para(doc, align=WD_ALIGN_PARAGRAPH.JUSTIFY, after=4):
    p = doc.add_paragraph()
    p.alignment = align
    pf = p.paragraph_format
    pf.space_before, pf.space_after, pf.line_spacing = Pt(0), Pt(after), 1.0
    return p


def add_hyperlink(p, text, url):
    r_id = p.part.relate_to(url, RT.HYPERLINK, is_external=True)
    h = OxmlElement("w:hyperlink"); h.set(qn("r:id"), r_id)
    r = OxmlElement("w:r"); rpr = OxmlElement("w:rPr")
    for tag, val in (("w:rFonts", None), ("w:color", "0563C1"), ("w:u", "single"), ("w:sz", str(int(SIZE * 2)))):
        el = OxmlElement(tag)
        if tag == "w:rFonts":
            el.set(qn("w:ascii"), FONT); el.set(qn("w:hAnsi"), FONT)
        else:
            el.set(qn("w:val"), val)
        rpr.append(el)
    r.append(rpr)
    t = OxmlElement("w:t"); t.text = text; r.append(t)
    h.append(r); p._p.append(h)


def cell_borders(cell, top=None, bottom=None):
    tcPr = cell._tc.get_or_add_tcPr()
    b = OxmlElement("w:tcBorders")
    for edge, on in (("top", top), ("bottom", bottom), ("left", False), ("right", False)):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single" if on else "nil")
        if on:
            el.set(qn("w:sz"), "8"); el.set(qn("w:color"), "000000")
        b.append(el)
    tcPr.append(b)


def shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    sh = OxmlElement("w:shd"); sh.set(qn("w:val"), "clear"); sh.set(qn("w:color"), "auto"); sh.set(qn("w:fill"), fill)
    tcPr.append(sh)


def no_borders(table):
    tblPr = table._tbl.tblPr
    b = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}"); el.set(qn("w:val"), "nil"); b.append(el)
    tblPr.append(b)


def feature_table(cell, t):
    inner = cell.add_table(rows=1 + len(t["rows"]), cols=3)
    inner.alignment = WD_TABLE_ALIGNMENT.CENTER
    no_borders(inner)
    for j, h in enumerate(t["header"]):
        c = inner.cell(0, j); c.text = ""
        style_run(c.paragraphs[0].add_run(h), size=10.5, bold=True)
        c.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        shade(c, "D9D9D9"); cell_borders(c, top=True, bottom=True)
    for i, row in enumerate(t["rows"], start=1):
        for j, v in enumerate(row):
            c = inner.cell(i, j); c.text = ""
            style_run(c.paragraphs[0].add_run(v), size=10.5)
            c.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            cell_borders(c, bottom=(i == len(t["rows"])))
    cap = cell.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    cap.paragraph_format.space_before = Pt(3)
    label, rest = t["caption"].split(":", 1)
    style_run(cap.add_run(label + ":"), size=10, bold=True)
    style_run(cap.add_run(rest), size=10)
    # python-docx leaves an empty first paragraph in the cell; remove it
    first = cell.paragraphs[0]
    if not first.text.strip() and len(cell.paragraphs) > 1:
        first._element.getparent().remove(first._element)


def main():
    d = json.loads(CONTENT.read_text(encoding="utf-8"))
    doc = Document()
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
    sec.left_margin = sec.right_margin = Cm(2.3)
    sec.top_margin = sec.bottom_margin = Cm(2.0)
    normal = doc.styles["Normal"]; normal.font.name = FONT; normal.font.size = Pt(SIZE)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), FONT)
    normal.paragraph_format.space_after = Pt(0)
    normal.paragraph_format.space_before = Pt(0)
    normal.paragraph_format.line_spacing = 1.0

    p = para(doc, WD_ALIGN_PARAGRAPH.CENTER, after=2); style_run(p.add_run(d["title"]), size=13, bold=True)
    p = para(doc, WD_ALIGN_PARAGRAPH.CENTER, after=0); style_run(p.add_run(d["author"]))
    p = para(doc, WD_ALIGN_PARAGRAPH.CENTER, after=8); style_run(p.add_run(d["affiliation"]))

    for text in d["paragraphs"]:
        p = para(doc, after=6)
        if "{LINK}" in text:
            before, rest = text.split("{LINK}", 1)
            word, after = rest.split("{/LINK}", 1)
            style_run(p.add_run(before))
            if URL:
                add_hyperlink(p, word, URL)
            else:
                r = style_run(p.add_run(word + " [ADD OSF LINK]"))
                r.font.highlight_color = WD_COLOR_INDEX.YELLOW
            style_run(p.add_run(after))
        else:
            style_run(p.add_run(text))

    outer = doc.add_table(rows=1, cols=2)
    no_borders(outer)
    outer.autofit = False
    for c in outer.rows[0].cells:
        c.width = Cm(8.2)
    feature_table(outer.cell(0, 0), d["table1"])
    feature_table(outer.cell(0, 1), d["table2"])

    p = para(doc, WD_ALIGN_PARAGRAPH.LEFT, after=3)
    p.paragraph_format.space_before = Pt(8)
    style_run(p.add_run("References"), bold=True)
    for ref in d["references"]:
        p = para(doc, WD_ALIGN_PARAGRAPH.LEFT, after=1)
        p.paragraph_format.left_indent = Cm(0.9)
        p.paragraph_format.first_line_indent = Cm(-0.9)
        style_run(p.add_run(ref), size=REF_SIZE)

    cp = doc.core_properties
    cp.author = d["author"]; cp.title = d["title"]
    doc.save(str(OUT))
    print("saved", OUT.name)


if __name__ == "__main__":
    main()
