"""Build the EL161 A0 poster from the Windsor template.

Text comes verbatim from ../poster_outputs/poster_text.md; figures from
../poster_outputs/. Run with a Python that has python-pptx installed:
    python build_poster.py
Output: EL161_poster_Mithun.pptx (in this folder).
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageFont
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Cm, Emu, Pt

HERE = Path(__file__).resolve().parent
OUTPUTS = HERE.parent / "poster_outputs"
TEMPLATE = HERE / "Template_Windsor.pptx"
OUT = HERE / "EL161_poster_Mithun.pptx"
DATA_URL = sys.argv[1] if len(sys.argv) > 1 else ""   # OSF view-only link for data and code

# ---- Style (template fonts and colours) -----------------------------------
HEAD_FONT, BODY_FONT = "Century Gothic", "Trebuchet MS"
BLUE = RGBColor(0x22, 0x5E, 0xAC)      # template section-header blue
INK = RGBColor(0x1F, 0x1F, 0x1F)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
TITLE_PT, AUTHOR_PT, COURSE_PT = 90, 46, 40
HEAD_PT, BODY_PT, CAP_PT, REF_PT = 50, 33, 26, 20
TAKE_PT = 36                           # take-home message
ACCENT = RGBColor(0xF2, 0xA9, 0x00)    # amber (template palette FFC000 family), highlights the take-home box
ACCENT_FILL = RGBColor(0xFF, 0xF6, 0xDB)
NAVY = RGBColor(0x1B, 0x2F, 0x6B)
BANNER_STOPS = ("1B2F6B", "225EAC")   # navy -> template blue, like the course example
LINE = 1.15                            # line spacing multiple
FONT_FILES = {
    BODY_FONT: "/System/Library/Fonts/Supplemental/Trebuchet MS.ttf",
    BODY_FONT + " Bold": "/System/Library/Fonts/Supplemental/Trebuchet MS Bold.ttf",
}

# ---- Geometry (cm), measured from the template's 3-column panels -----------
COLS = [(1.2, 25.6), (29.9, 24.6), (57.4, 25.6)]   # (left, width) of the text area
TOP, BOTTOM = 17.0, 114.6
GAP_SECTION, GAP_PARA = 1.0, 0.35


# ---- Parse poster_text.md --------------------------------------------------
def parse_poster_text(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    cols, refs, col, sec = {}, [], None, None
    for ln in lines:
        if ln.strip() == "---":
            break                                     # recommended-figures section follows
        m = re.match(r"^## COLUMN (\d)", ln)
        if m:
            col = int(m.group(1)); cols[col] = []; continue
        m = re.match(r"^### (.+)", ln)
        if m and col is not None:
            sec = m.group(1).strip()
            if sec == "References":
                col = "refs"
            else:
                cols[col].append([sec, []])
            continue
        if ln.startswith("- ") and col is not None:
            (refs if col == "refs" else cols[col][-1][1]).append(ln[2:].strip())
    return cols, refs


# ---- Text measurement (for layout) -----------------------------------------
_font_cache = {}
def font(name, pt):
    key = (name, pt)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(FONT_FILES[name], size=pt * 10)  # 10 px per pt
    return _font_cache[key]

def n_lines(text, pt, width_cm, bold=False):
    f = font(BODY_FONT + (" Bold" if bold else ""), pt)
    max_px = width_cm / 2.54 * 72 * 10                   # cm -> pt -> px
    words, lines, cur = text.replace("*", "").split(), 1, ""
    for w in words:
        trial = (cur + " " + w).strip()
        if f.getlength(trial) <= max_px:
            cur = trial
        else:
            lines += 1; cur = w
    return lines

def line_cm(pt, bold=False):
    """Line pitch = font's natural line height (ascent + descent) x LINE."""
    a, d = font(BODY_FONT + (" Bold" if bold else ""), pt).getmetrics()
    return (a + d) / 10 * LINE / 72 * 2.54


# ---- pptx helpers ------------------------------------------------------------
def set_run(run, text, size, fontname, color, bold=False, italic=False):
    run.text = text
    f = run.font
    f.size, f.name, f.bold, f.italic = Pt(size), fontname, bold, italic
    f.color.rgb = color

def add_rich(paragraph, text, size, fontname, color):
    """Add text with *italic* segments as separate runs."""
    for i, part in enumerate(re.split(r"\*", text)):
        if part:
            set_run(paragraph.add_run(), part, size, fontname, color, italic=(i % 2 == 1))

def bulletize(paragraph, size):
    pPr = paragraph._p.get_or_add_pPr()
    indent = int(Pt(size * 0.9))
    pPr.set("marL", str(indent)); pPr.set("indent", str(-indent))
    for tag in ("a:buNone", "a:buChar", "a:buFont"):
        for el in pPr.findall(qn(tag)):
            pPr.remove(el)
    buFont = pPr.makeelement(qn("a:buFont"), {"typeface": "Arial"})
    buChar = pPr.makeelement(qn("a:buChar"), {"char": "•"})
    pPr.append(buFont); pPr.append(buChar)

def line_spacing(paragraph, after_pt):
    paragraph.line_spacing = LINE
    paragraph.space_after = Pt(after_pt)
    paragraph.space_before = Pt(0)

def textbox(slide, left, top, width, height):
    tb = slide.shapes.add_textbox(Cm(left), Cm(top), Cm(width), Cm(height))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.auto_size = None
    return tb, tf


# ---- Build ---------------------------------------------------------------------
def main():
    cols, refs = parse_poster_text(OUTPUTS / "poster_text.md")
    prs = Presentation(str(TEMPLATE))

    # Remove template instructions/branding from every master: off-page guide
    # tables and the copyright text box.
    for master in prs.slide_masters:
        for sh in list(master.shapes):
            if sh.shape_type == 19 or (sh.has_text_frame and "PosterPresentations" in sh.text_frame.text):
                sh._element.getparent().remove(sh._element)

    # Drop image relationships that only the removed guide tables used
    for master in prs.slide_masters:
        xml = master._element.xml
        for rId, rel in list(master.part.rels.items()):
            if rel.reltype.endswith("/image") and f'"{rId}"' not in xml:
                master.part.drop_rel(rId)

    # Document properties
    cp = prs.core_properties
    cp.author = cp.last_modified_by = "Mithun Thangaraj"
    cp.title = "What Makes a Word Sound Funny? Sound Predicts Humor Beyond Frequency and Meaning"
    cp.subject = "EL161 Machine Learning for Linguistics"
    cp.comments = ""

    # Remove the layouts' prompt placeholders ("Click here to add title", ...)
    for master in prs.slide_masters:
        for lay in master.slide_layouts:
            for sh in list(lay.shapes):
                if sh.has_text_frame and re.search(r"click|Type in or paste", sh.text_frame.text, re.I):
                    sh._element.getparent().remove(sh._element)

    # Banner and bottom strip: blue gradient, square corners, no corner slabs
    lay3 = next(l for m in prs.slide_masters for l in m.slide_layouts if l.name == "3-column layout")
    master3 = lay3.slide_master
    def restyle(sp_el, full_width=None):
        for gs, col in zip(sp_el.iter(qn("a:gs")), BANNER_STOPS):
            for c in gs.iter(qn("a:srgbClr")):
                c.set("val", col)
        spPr = sp_el.find(qn("p:spPr"))
        for geo in [g for g in spPr if g.tag in (qn("a:prstGeom"), qn("a:custGeom"))]:
            idx = list(spPr).index(geo); spPr.remove(geo)
            new = spPr.makeelement(qn("a:prstGeom"), {"prst": "rect"})
            new.append(new.makeelement(qn("a:avLst"), {}))
            spPr.insert(idx, new)
    for sh in list(master3.shapes):
        if sh.shape_type == 6:                                   # banner group
            kids = list(sh.shapes)
            restyle(kids[0]._element)
            for k in kids[1:]:                                   # the two navy corner slabs
                k._element.getparent().remove(k._element)
        elif sh.name.startswith("Snip and Round") and sh.top > Cm(100):   # bottom strip
            restyle(sh._element)
            sh.rotation = 0
            sh.left, sh.width = 0, prs.slide_width

    # New slide on the 3-column layout; drop the template's 2-column slide.
    layout = next(l for m in prs.slide_masters for l in m.slide_layouts if l.name == "3-column layout")
    slide = prs.slides.add_slide(layout)
    first = prs.slides._sldIdLst[0]
    prs.part.drop_rel(first.rId); prs.slides._sldIdLst.remove(first)
    for ph in list(slide.placeholders):                 # remove all placeholder text boxes
        ph._element.getparent().remove(ph._element)

    # Thin gold accent lines under the banner and above the bottom strip
    for y_cm in (14.6, 115.45):
        line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, Cm(y_cm), prs.slide_width, Cm(0.35))
        line.fill.solid(); line.fill.fore_color.rgb = ACCENT; line.line.fill.background()

    # QR code to the data and code, on the right of the banner
    if DATA_URL:
        import qrcode
        qr_png = HERE / "qr_data_code.png"
        qrcode.make(DATA_URL, border=1).save(qr_png)
        bg = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Cm(72.3), Cm(1.0), Cm(9.4), Cm(9.4))
        bg.adjustments[0] = 0.08
        bg.fill.solid(); bg.fill.fore_color.rgb = WHITE; bg.line.fill.background()
        slide.shapes.add_picture(str(qr_png), Cm(72.8), Cm(1.5), Cm(8.4), Cm(8.4))
        _, tf = textbox(slide, 70.5, 10.8, 13.0, 1.6)
        tf.paragraphs[0].alignment = PP_ALIGN.CENTER
        set_run(tf.paragraphs[0].add_run(), "Data & code", COURSE_PT, HEAD_FONT, WHITE, bold=True)

    # Title banner
    _, tf = textbox(slide, 2.0, 0.9, 80.0, 9.6)
    tf.vertical_anchor = MSO_ANCHOR.TOP
    title_lines = ["What Makes a Word Sound Funny?", "Sound Predicts Humor Beyond", "Frequency and Meaning"]
    for i, t in enumerate(title_lines):
        para = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        para.line_spacing = 0.8; para.alignment = PP_ALIGN.CENTER
        set_run(para.add_run(), t, TITLE_PT, HEAD_FONT, WHITE, bold=True)
    _, tf = textbox(slide, 2.0, 10.8, 80.0, 1.8)
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER
    set_run(tf.paragraphs[0].add_run(), "Mithun Thangaraj", AUTHOR_PT, HEAD_FONT, WHITE, bold=True)
    _, tf = textbox(slide, 2.0, 12.7, 80.0, 1.6)
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER
    set_run(tf.paragraphs[0].add_run(), "EL161 Machine Learning for Linguistics", COURSE_PT, HEAD_FONT, WHITE)

    # Figures (file, column, caption) in reading order; positions decided below
    FIGS = {
        "sounds": ("poster_fig_sounds.png", "Sounds most linked to funnier (orange) and less funny (blue) words."),
        "models": ("poster_fig_models.png", "How well each model spots funny words it never saw; darker bars = funniest vs least funny 10%."),
        "svm": ("poster_fig_sound_vs_meaning.png", "The key test: the same words predicted with and without their sounds."),
        "resid": ("poster_fig_residual.png", "Sounds predict humor left over after meaning and frequency; shuffled sounds predict nothing."),
        "matters": ("poster_fig_what_matters.png", "What the meaning + sounds model relies on most, and in which direction."),
        "classes": ("poster_fig_sound_classes.png", "Kinds of sounds that push a word toward funnier (orange) or less funny (blue)."),
    }
    # Column plans
    res = cols[2][0][1]
    plan = {
        1: [("section", cols[1][0]), ("section", cols[1][1]), ("section", cols[1][2]),
            ("fig", "sounds"), ("fig", "models")],
        2: [("section", (cols[2][0][0], res[0:4])), ("fig", "svm"),
            ("bullets", res[4:5]), ("fig", "resid"),
            ("bullets", res[5:]), ("fig", "matters")],
        3: [("section", cols[3][0]), ("fig", "classes"), ("section", cols[3][1]),
            ("section", cols[3][2]), ("section", cols[3][3]), ("refs", refs)],
    }
    # Every bullet in poster_text.md must be placed exactly once
    placed = [b for c in plan.values() for kind, item in c if kind in ("section", "bullets", "takehome")
              for b in (item if kind == "bullets" else item[1])]
    expected = [b for c in (1, 2, 3) for _, bs in cols[c] for b in bs]
    assert sorted(placed) == sorted(expected), "poster text not fully placed"

    # Pass 1: measure every block; pass 2: place them, spreading leftover space
    def bullets_h(bs, pt=BODY_PT):
        return sum(n_lines(x, pt, COLS[0][1] - 0.9) * line_cm(pt) + GAP_PARA for x in bs)
    fig_no = 0
    report = []
    for c, items in plan.items():
        left, width = COLS[c - 1]
        blocks = []
        for kind, item in items:
            if kind == "takehome":
                tw = width - 1.6
                th = sum(n_lines(x, TAKE_PT, tw, bold=True) for x in item[1]) * line_cm(TAKE_PT, bold=True)
                blocks.append(("takehome", (item[0], item[1], th), 1.0 + 2.0 + th + 1.0))
            elif kind == "section":
                blocks.append(("head", item[0], 3.0))
                blocks.append(("bullets", item[1], sum(n_lines(x, BODY_PT, width - 0.9) * line_cm(BODY_PT) + GAP_PARA for x in item[1])))
            elif kind == "bullets":
                blocks.append(("bullets", item, sum(n_lines(x, BODY_PT, width - 0.9) * line_cm(BODY_PT) + GAP_PARA for x in item)))
            elif kind == "fig":
                fname, cap = FIGS[item]
                fig_no += 1
                w_px, h_px = Image.open(OUTPUTS / fname).size
                h = width * h_px / w_px
                cap_text = f"Figure {fig_no}. {cap}"
                # captions are italic (wider than the regular font measured): +0.5 line margin
                ch = (n_lines(cap_text, CAP_PT, width) + 0.5) * line_cm(CAP_PT)
                blocks.append(("fig", (fname, fig_no, cap, h, ch), h + 0.3 + ch))
            elif kind == "refs":
                blocks.append(("head", "References", 3.0))
                blocks.append(("refs", item, sum(n_lines(r, REF_PT, width - 0.9) * line_cm(REF_PT) + Pt(4).cm for r in item)))
        total = sum(h for _, _, h in blocks)
        # gaps go before each header and around figures (not between a header and its text)
        gap_slots = [i for i, (k, _, _) in enumerate(blocks) if i > 0 and k in ("head", "fig", "takehome") or
                     (i > 0 and blocks[i - 1][0] == "fig")]
        free = BOTTOM - TOP - total
        gap = free / max(1, len(gap_slots))
        if free < 0:
            print(f"WARNING column {c} overflows by {-free:.1f} cm")
        y = TOP
        for i, (k, item, h) in enumerate(blocks):
            if i in gap_slots:
                y += gap
            if k == "takehome":
                head, lines, th = item
                box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Cm(left - 0.3), Cm(y), Cm(width + 0.6), Cm(h))
                box.adjustments[0] = 0.08
                box.fill.solid(); box.fill.fore_color.rgb = ACCENT_FILL
                box.line.color.rgb = ACCENT; box.line.width = Pt(6)
                _, tf = textbox(slide, left + 0.5, y + 0.8, width - 1.0, 1.8)
                hp = tf.paragraphs[0]; hp.alignment = PP_ALIGN.CENTER
                set_run(hp.add_run(), head, HEAD_PT, HEAD_FONT, NAVY, bold=True)
                _, tf = textbox(slide, left + 0.5, y + 3.0, width - 1.6, th)
                for j, b in enumerate(lines):
                    para = tf.paragraphs[0] if j == 0 else tf.add_paragraph()
                    para.line_spacing = LINE; para.alignment = PP_ALIGN.CENTER
                    set_run(para.add_run(), b, TAKE_PT, BODY_FONT, INK, bold=True)
            elif k == "head":
                bar = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Cm(left - 0.3), Cm(y), Cm(width + 0.6), Cm(2.4))
                bar.adjustments[0] = 0.25
                bar.fill.solid(); bar.fill.fore_color.rgb = BLUE; bar.line.fill.background()
                btf = bar.text_frame
                btf.margin_top = btf.margin_bottom = 0
                btf.vertical_anchor = MSO_ANCHOR.MIDDLE
                bp = btf.paragraphs[0]; bp.alignment = PP_ALIGN.CENTER
                set_run(bp.add_run(), item, HEAD_PT, HEAD_FONT, WHITE, bold=True)
            elif k in ("bullets", "refs"):
                pt = BODY_PT if k == "bullets" else REF_PT
                after = GAP_PARA / 2.54 * 72 if k == "bullets" else 4
                _, tf = textbox(slide, left, y, width, h)
                for j, b in enumerate(item):
                    para = tf.paragraphs[0] if j == 0 else tf.add_paragraph()
                    line_spacing(para, after); bulletize(para, pt)
                    add_rich(para, b, pt, BODY_FONT, INK)
            elif k == "fig":
                fname, no, cap, fh, ch = item
                slide.shapes.add_picture(str(OUTPUTS / fname), Cm(left), Cm(y), Cm(width), Cm(fh))
                _, tf = textbox(slide, left, y + fh + 0.3, width, ch)
                p0 = tf.paragraphs[0]; p0.line_spacing = LINE
                set_run(p0.add_run(), f"Figure {no}. ", CAP_PT, BODY_FONT, INK, bold=True)
                set_run(p0.add_run(), cap, CAP_PT, BODY_FONT, INK, italic=True)
            y += h
        report.append((c, round(free, 1), round(gap, 2)))
    prs.save(str(OUT))
    for c, free, gap in report:
        print(f"column {c}: free space {free} cm, spread as {gap} cm gaps")


def _bullets(slide, bullets, left, width, y):
    h = sum(n_lines(b, BODY_PT, width - 0.9) * line_cm(BODY_PT) + GAP_PARA for b in bullets)
    _, tf = textbox(slide, left, y, width, h)
    for i, b in enumerate(bullets):
        para = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        line_spacing(para, GAP_PARA / 2.54 * 72)
        bulletize(para, BODY_PT)
        add_rich(para, b, BODY_PT, BODY_FONT, INK)
    return y + h


if __name__ == "__main__":
    main()
