"""Builds E:\\FPGA_Project\\docs\\AXI4_Viva_Presentation.pptx

Run:  python docs\\build_deck.py
Needs: python-pptx
"""
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "AXI4_Viva_Presentation.pptx")

# ---- palette (same roles as the block diagram) ---------------------------
NAVY, LIGHT, WHITE = "172033", "F5F7FA", "FFFFFF"
INK, MUTED, RULE = "1E2A3B", "4F5F74", "D5DCE6"
AMBER, AMBER_D, AMBER_F = "FFC845", "8F5C00", "FFE9A8"
BLUE, BLUE_F = "3B6FD0", "D6E6FF"
VIOLET, VIOLET_F = "7152C9", "E6DEFA"
GREEN, GREEN_F = "2E8B57", "D9F0E3"
ON_DARK, ON_DARK_M = "EEF2F8", "B7C3D6"

HEAD, BODY, MONO = "Cambria", "Calibri", "Consolas"
W, H = 13.333, 7.5
MX = 0.7


def rgb(h):
    return RGBColor.from_string(h)


prs = Presentation()
prs.slide_width = Inches(W)
prs.slide_height = Inches(H)
BLANK = prs.slide_layouts[6]
page_no = [0]


# ---- helpers --------------------------------------------------------------
def new_slide(bg=LIGHT, notes=""):
    s = prs.slides.add_slide(BLANK)
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = rgb(bg)
    if notes:
        s.notes_slide.notes_text_frame.text = notes
    page_no[0] += 1
    return s


def text(slide, x, y, w, h, paras, size=16, bold=False, color=INK, font=BODY,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, italic=False, name=None):
    """paras: str | list[str | dict(text,size,bold,color,font,after,italic)]"""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, p in enumerate(paras):
        d = {"text": p} if isinstance(p, str) else p
        para = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        para.alignment = d.get("align", align)
        run = para.add_run()
        run.text = d["text"]
        f = run.font
        f.size = Pt(d.get("size", size))
        f.bold = d.get("bold", bold)
        f.italic = d.get("italic", italic)
        f.name = d.get("font", font)
        f.color.rgb = rgb(d.get("color", color))
        if "after" in d:
            para.space_after = Pt(d["after"])
    return tb


def box(slide, x, y, w, h, fill=WHITE, line=None, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        radius=0.06, name=None):
    sp = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        sp.name = name
    sp.fill.solid()
    sp.fill.fore_color.rgb = rgb(fill)
    if line:
        sp.line.color.rgb = rgb(line)
        sp.line.width = Pt(1.5)
    else:
        sp.line.fill.background()
    sp.shadow.inherit = False
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        sp.adjustments[0] = radius
    sp.text_frame.text = ""
    return sp


def pill(slide, x, y, w, h, label, fill=AMBER_F, color=INK, size=14, bold=True, font=BODY):
    sp = box(slide, x, y, w, h, fill=fill, radius=0.5)
    tf = sp.text_frame
    tf.margin_left = tf.margin_right = Inches(0.08)
    tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = label
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.name = font
    r.font.color.rgb = rgb(color)
    return sp


def arrow(slide, x1, y1, x2, y2, color=INK, width=2.25, head=True):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1),
                                   Inches(x2), Inches(y2))
    c.line.color.rgb = rgb(color)
    c.line.width = Pt(width)
    if head:
        ln = c.line._get_or_add_ln()
        tail = ln.makeelement(qn("a:tailEnd"), {"type": "triangle", "w": "med", "len": "med"})
        ln.append(tail)
    return c


def line(slide, x1, y1, x2, y2, color=INK, width=2.25):
    return arrow(slide, x1, y1, x2, y2, color, width, head=False)


def title(slide, label, dark=False):
    text(slide, MX, 0.45, W - 2 * MX, 0.9, label, size=38, bold=True,
         color=ON_DARK if dark else INK, font=HEAD, anchor=MSO_ANCHOR.MIDDLE, name="Title")


def footer(slide, dark=False):
    c = ON_DARK_M if dark else MUTED
    text(slide, MX, 7.0, 8, 0.3, "AXI4 manager, subordinate and registered channels",
         size=11, color=c, name="Footer")
    text(slide, W - MX - 1.0, 7.0, 1.0, 0.3, str(page_no[0]), size=11, color=c,
         align=PP_ALIGN.RIGHT, name="Page number")


def picture(slide, path, x, y, w=None, h=None, alt=""):
    p = slide.shapes.add_picture(path, Inches(x), Inches(y),
                                 Inches(w) if w else None, Inches(h) if h else None)
    p._element.nvPicPr.cNvPr.set("descr", alt)
    return p


def bullets_card(slide, x, y, w, h, heading, items, fill=WHITE, head_color=INK, size=15,
                 mono=False, hsize=19, sub=None):
    box(slide, x, y, w, h, fill=fill)
    text(slide, x + 0.3, y + 0.25, w - 0.6, 0.45, heading, size=hsize, bold=True,
         color=head_color, font=HEAD)
    top = y + 0.8
    if sub:
        text(slide, x + 0.3, y + 0.72, w - 0.6, 0.3, sub, size=12, color=MUTED, font=MONO)
        top = y + 1.15
    paras = [{"text": t, "after": 6, "font": MONO if mono else BODY,
              "size": size - (1 if mono else 0)} for t in items]
    text(slide, x + 0.3, top, w - 0.6, h - (top - y) - 0.2, paras, size=size)


# =========================================================================
# 1  Cover
# =========================================================================
s = new_slide(NAVY, "Open with the one-sentence summary: we built both ends of an AXI4 connection in "
              "Verilog. A manager that issues bursts, and a subordinate that is a 4 KiB memory. They are "
              "connected through five registered channels. Everything shown today comes from the "
              "simulation in the project folder, so every number can be reproduced live. The five amber "
              "pills are the five AXI channels; we come back to each one.")
text(s, 0.9, 1.5, 11, 0.4, "VIVA DEMONSTRATION", size=18, bold=True, color=AMBER, name="Eyebrow")
text(s, 0.9, 2.05, 11.2, 2.4, "AXI4 manager and subordinate in Verilog", size=60, bold=True,
     color=ON_DARK, font=HEAD, name="Title")
text(s, 0.9, 4.25, 10.5, 1.0,
     "Burst transfers over five registered channels, with 251 checks passing in simulation.",
     size=24, color=ON_DARK_M)
px = 0.9
for lab, w_ in (("AW", 0.9), ("W", 0.8), ("B", 0.8), ("AR", 0.9), ("R", 0.8)):
    pill(s, px, 5.35, w_, 0.5, lab, fill=AMBER, color=NAVY, size=18)
    px += w_ + 0.18
text(s, 0.9, 6.7, 11, 0.4, "[Your name]   ·   [Course and institution]   ·   [Date]",
     size=16, color=ON_DARK_M, name="Presenter")

# =========================================================================
# 2  What we built
# =========================================================================
s = new_slide(LIGHT, "Three pieces. The manager is the active side: your logic gives it a simple "
              "request and it runs the whole AXI conversation. The subordinate is a small memory that "
              "understands that conversation. The flip-flop stages sit between them. Stress that this is "
              "full AXI4: bursts, IDs and the LAST signals, not the single-word AXI4-Lite.")
title(s, "What we built")
text(s, MX, 1.4, 11.9, 0.5, "Both ends of an AXI4 connection, and the registers between them.",
     size=20, color=MUTED)
cards = [
    (BLUE_F, BLUE, "Manager", "axi4_master.v",
     "Takes a simple burst request from your logic and runs the full AXI4 exchange: address, data beats, response."),
    (VIOLET_F, VIOLET, "Subordinate", "axi4_slave.v",
     "A 4 KiB memory. Accepts bursts of 1 to 256 beats in FIXED, INCR or WRAP order, and answers OKAY or an error."),
    (AMBER_F, AMBER_D, "Flip-flop stages", "axi4_skid_buffer.v",
     "One registered stage per channel, so nothing crosses between the two modules combinationally."),
]
cx = MX
for fill, accent, head, fname, body in cards:
    box(s, cx, 2.25, 3.82, 3.9, fill=fill)
    text(s, cx + 0.35, 2.55, 3.1, 0.5, head, size=26, bold=True, font=HEAD)
    text(s, cx + 0.35, 3.15, 3.1, 0.35, fname, size=14, color=MUTED, font=MONO)
    text(s, cx + 0.35, 3.75, 3.1, 2.2, body, size=17)
    cx += 3.82 + 0.22
text(s, MX, 6.4, 11.9, 0.4,
     "Full AXI4 rather than AXI4-Lite: bursts, transaction IDs, WLAST and RLAST.",
     size=16, color=MUTED, italic=True)
footer(s)

# =========================================================================
# 3  Five channels
# =========================================================================
s = new_slide(LIGHT, "AXI separates a transaction into five independent one-way channels, so a read can "
              "proceed while a write waits, and a slow response never blocks the next address. A write "
              "uses AW for the address, W for the data beats, and B for one response at the end. A read "
              "uses AR for the address and R for the data coming back. Notice B and R point the other way.")
title(s, "Five independent channels")
mb = box(s, 0.9, 1.65, 2.5, 4.95, fill=BLUE_F, line=BLUE)
text(s, 0.9, 3.4, 2.5, 0.8, [{"text": "Manager", "size": 24, "bold": True, "font": HEAD,
                                "align": PP_ALIGN.CENTER},
                               {"text": "axi4_master", "size": 14, "font": MONO, "color": MUTED,
                                "align": PP_ALIGN.CENTER}])
sb = box(s, 9.93, 1.65, 2.5, 4.95, fill=VIOLET_F, line=VIOLET)
text(s, 9.93, 3.4, 2.5, 0.8, [{"text": "Subordinate", "size": 24, "bold": True, "font": HEAD,
                                 "align": PP_ALIGN.CENTER},
                                {"text": "axi4_slave", "size": 14, "font": MONO, "color": MUTED,
                                 "align": PP_ALIGN.CENTER}])
text(s, 3.7, 1.7, 2, 0.3, "WRITE", size=12, bold=True, color=MUTED)
text(s, 3.7, 4.55, 2, 0.3, "READ", size=12, bold=True, color=MUTED)
rows = [
    (2.4, "AW   write address", True), (3.25, "W   write data", True),
    (4.1, "B   write response", False),
    (5.2, "AR   read address", True), (6.05, "R   read data", False),
]
for y, lab, fwd in rows:
    if fwd:
        arrow(s, 3.45, y, 9.88, y, color=INK)
    else:
        arrow(s, 9.88, y, 3.45, y, color=INK)
    pill(s, 5.25, y - 0.24, 3.3, 0.48, lab, fill=AMBER_F, size=16)
footer(s)

# =========================================================================
# 4  Handshake
# =========================================================================
s = new_slide(LIGHT, "Every channel uses the same handshake. The sender raises VALID when its data is "
              "real. The receiver raises READY when it can take it. The transfer happens in the one clock "
              "cycle where both are high. Two rules keep it safe. First, once VALID is up the data must "
              "not change until the handshake completes. Second, a sender may not wait for READY before "
              "raising VALID, or two sides could wait on each other forever. Our testbenches check both "
              "rules on every run.")
title(s, "The VALID and READY handshake")
box(s, MX, 1.65, 5.6, 2.2, fill=WHITE)
text(s, MX + 0.3, 1.85, 5.0, 0.4, "Transfer", size=20, bold=True, font=HEAD)
text(s, MX + 0.3, 2.35, 5.0, 1.4,
     "The sender raises VALID when its data is real. The receiver raises READY when it can take it. "
     "The transfer happens in the cycle where both are high.", size=16)
box(s, MX, 4.05, 5.6, 2.6, fill=WHITE)
text(s, MX + 0.3, 4.25, 5.0, 0.4, "Two rules", size=20, bold=True, font=HEAD)
text(s, MX + 0.3, 4.75, 5.0, 1.8, [
    {"text": "Once VALID is up, the data and VALID stay put until the handshake completes.", "after": 8},
    {"text": "A sender may not wait for READY before raising VALID.", "after": 0}], size=16)
# waveform
wx, wy, cw = 6.9, 1.9, 0.7
box(s, 6.5, 1.65, 6.13, 5.0, fill=WHITE)
text(s, 6.8, 1.8, 3, 0.35, "One transfer, cycle by cycle", size=14, color=MUTED)
sigs = [("CLK", None), ("VALID", [0, 1, 1, 1, 0, 0]), ("READY", [0, 0, 0, 1, 1, 0])]
base = wy + 1.35
for i in range(6):
    xx = wx + 0.85 + i * cw
    line(s, xx, wy + 0.4, xx, wy + 3.75, color=RULE, width=1)
    text(s, xx, wy + 0.1, cw, 0.3, str(i), size=12, color=MUTED, align=PP_ALIGN.CENTER)
for r_, (nm, bits) in enumerate(sigs):
    yb = base + r_ * 0.9       # low level
    yt = yb - 0.5
    text(s, 6.8, yb - 0.45, 0.9, 0.4, nm, size=14, bold=True, font=MONO)
    if bits is None:
        for i in range(6):
            x0 = wx + 0.85 + i * cw
            line(s, x0, yt, x0 + cw / 2, yt, BLUE)
            line(s, x0 + cw / 2, yt, x0 + cw / 2, yb, BLUE)
            line(s, x0 + cw / 2, yb, x0 + cw, yb, BLUE)
            if i < 5:
                line(s, x0 + cw, yb, x0 + cw, yt, BLUE)
    else:
        prev = 0
        for i, b in enumerate(bits):
            x0 = wx + 0.85 + i * cw
            y_ = yt if b else yb
            if i and prev != b:
                line(s, x0, yb if prev == 0 else yt, x0, y_, BLUE)
            line(s, x0, y_, x0 + cw, y_, BLUE)
            prev = b
dot = box(s, wx + 0.85 + 3 * cw + cw / 2 - 0.13, base + 0.9 - 0.5 - 0.13, 0.26, 0.26,
          fill=AMBER, shape=MSO_SHAPE.OVAL)
text(s, 6.8, 5.7, 5.6, 0.7, "Amber dot: cycle 3 is the only cycle where VALID and READY are both high, "
     "so that is where the transfer happens.", size=14, color=MUTED)
footer(s)

# =========================================================================
# 5  Bursts
# =========================================================================
s = new_slide(LIGHT, "A burst is one address followed by many beats. LEN says how many beats minus one, "
              "SIZE says how wide each beat is, BURST says how the address moves, and LAST marks the final "
              "beat so the receiver knows where it ends. The three burst types, starting at 0x208 with "
              "four 4-byte beats: INCR counts up. FIXED stays on one address, like pushing into a FIFO "
              "register, and the last beat wins. WRAP counts up inside a 16-byte window and loops back to "
              "its start; a CPU uses it to fetch a cache line with the needed word first.")
title(s, "What a burst is made of")
chips = [("LEN", "beats minus 1"), ("SIZE", "bytes per beat = 2^n"),
         ("BURST", "how the address moves"), ("LAST", "marks the final beat")]
cx = MX
for k, v in chips:
    box(s, cx, 1.55, 2.85, 0.95, fill=BLUE_F)
    text(s, cx + 0.2, 1.65, 2.5, 0.4, k, size=18, bold=True, font=MONO, color=BLUE)
    text(s, cx + 0.2, 2.05, 2.5, 0.4, v, size=15)
    cx += 2.85 + 0.17
text(s, MX, 2.75, 11.9, 0.4, "Four beats of 4 bytes, starting at address 0x208:", size=16, color=MUTED)
types = [
    ("INCR", "00 → 01", ["0x208", "0x20C", "0x210", "0x214"], "Counts up. Normal streaming."),
    ("FIXED", "00", ["0x208", "0x208", "0x208", "0x208"], "Same location every beat. Last beat wins. Like pushing into a FIFO register."),
    ("WRAP", "10", ["0x208", "0x20C", "0x200", "0x204"], "Loops inside a 16-byte window. A cache line fetched with the needed word first."),
]
cx = MX
for nm, code, seq, desc in types:
    box(s, cx, 3.25, 3.82, 3.4, fill=WHITE)
    text(s, cx + 0.3, 3.45, 3.2, 0.45, nm, size=24, bold=True, font=HEAD)
    text(s, cx + 0.3, 4.05, 3.3, 1.2, [
        {"text": "   ".join(seq[:2]), "font": MONO, "size": 19, "after": 6},
        {"text": "   ".join(seq[2:]), "font": MONO, "size": 19, "color": AMBER_D, "bold": True}])
    text(s, cx + 0.3, 5.05, 3.25, 1.5, desc, size=16, color=MUTED)
    cx += 3.82 + 0.22
footer(s)

# =========================================================================
# 6  System block diagram
# =========================================================================
s = new_slide(LIGHT, "Walk left to right. Your logic uses a command port and two data streams. The "
              "manager turns those into the five AXI channels. Every channel passes through its own "
              "amber flip-flop stage. AW, W and AR carry requests forward; B and R carry responses back. "
              "Inside the subordinate there is a write engine, a read engine and a 4 KiB memory. The "
              "three notes at the bottom are the three design decisions we will justify.")
title(s, "System architecture")
from PIL import Image  # crop the margins and the sticky notes so the drawing can be larger
_src = Image.open(os.path.join(HERE, "axi4_block_diagram.png"))
_crop = os.path.join(HERE, "axi4_block_diagram_crop.png")
_src.crop((30, 105, 1970, 895)).save(_crop)
picture(s, _crop, 0.9, 1.4, w=11.5,
        alt="Block diagram: your logic, axi4_master, five flip-flop stages, axi4_slave with write engine, read engine and 4 KiB memory.")
notes3 = [("Latched once at start", "The bus payload never moves mid-burst."),
          ("Every wire is a flip-flop", "+2 cycles, same throughput."),
          ("Errors still drain the burst", "So the manager never hangs.")]
nx = MX
for hd, bd in notes3:
    box(s, nx, 6.1, 3.82, 0.78, fill=WHITE)
    text(s, nx + 0.2, 6.15, 3.45, 0.3, hd, size=14, bold=True)
    text(s, nx + 0.2, 6.47, 3.45, 0.3, bd, size=13, color=MUTED)
    nx += 3.82 + 0.22
footer(s)

# =========================================================================
# 7  Host interface
# =========================================================================
s = new_slide(LIGHT, "The host side of the manager is deliberately simple. You pulse a start signal "
              "with a burst description; for a write you push beats into the write stream, for a read "
              "you pull them from the read stream. cmd_done is a one-cycle pulse when the burst "
              "finishes. Two rules: a start pulse is ignored while cmd_busy is high, and if both starts "
              "are high at once the write wins. The manager copies the description into registers, so "
              "you may change cmd_addr straight after the pulse.")
title(s, "Host interface of the manager")
quad = [
    (BLUE_F, "Command port", "you drive",
     ["cmd_start_write", "cmd_start_read", "cmd_id[3:0]", "cmd_addr[31:0]", "cmd_len[7:0]",
      "cmd_size[2:0]", "cmd_burst[1:0]"]),
    (GREEN_F, "Status", "you read",
     ["cmd_busy", "cmd_done  (1-cycle pulse)", "cmd_resp[1:0]", "cmd_resp_id[3:0]", "cmd_last_err"]),
    (AMBER_F, "Write stream", "you push beats",
     ["hw_data[31:0]", "hw_strb[3:0]", "hw_valid", "hw_ready"]),
    (VIOLET_F, "Read stream", "you pull beats",
     ["hr_data[31:0]", "hr_resp[1:0]", "hr_last", "hr_valid", "hr_ready"]),
]
pos = [(MX, 1.55), (MX + 6.05, 1.55), (MX, 4.0), (MX + 6.05, 4.0)]
hts = [2.3, 2.3, 2.3, 2.3]
for (fill, hd, sub, items), (x, y) in zip(quad, pos):
    box(s, x, y, 5.85, 2.3, fill=fill)
    text(s, x + 0.3, y + 0.2, 3.0, 0.4, hd, size=20, bold=True, font=HEAD)
    text(s, x + 3.2, y + 0.26, 2.4, 0.35, sub, size=13, color=MUTED, align=PP_ALIGN.RIGHT)
    half = (len(items) + 1) // 2
    text(s, x + 0.3, y + 0.75, 2.7, 1.5, [{"text": t, "font": MONO, "size": 13, "after": 3}
                                          for t in items[:half]])
    text(s, x + 3.0, y + 0.75, 2.7, 1.5, [{"text": t, "font": MONO, "size": 13, "after": 3}
                                          for t in items[half:]])
text(s, MX, 6.45, 11.9, 0.4,
     "A start is ignored while cmd_busy is high. If both starts arrive together, the write wins.",
     size=15, color=MUTED, italic=True)
footer(s)

# =========================================================================
# 8  Master
# =========================================================================
s = new_slide(LIGHT, "The manager is a five-state machine. IDLE waits for a start and copies the "
              "burst description into its own registers. WRITE sends the address and streams the beats "
              "together, counting them and raising WLAST on the last; the address and data channels are "
              "independent so either may finish first. B waits for the single response. For a read, "
              "RADDR sends the address and RDATA passes beats to the host until RLAST. Two decisions to "
              "defend: registering the description, and generating WLAST inside the manager.")
title(s, "The manager, state by state")
states = [
    ("IDLE", "Waits for a start. Copies address, length, size, burst type and ID into registers."),
    ("WRITE", "Sends the address and streams the beats together. Counts beats, raises WLAST on the last."),
    ("B", "Waits for the one response for the whole burst. Pulses cmd_done."),
    ("RADDR", "Sends the read address and waits for the subordinate to take it."),
    ("RDATA", "Passes beats to the host until RLAST. Flags a RLAST on the wrong beat."),
]
bw, gap = 2.18, 0.25
x = MX
for i, (nm, d) in enumerate(states):
    fill = BLUE_F if i < 3 else GREEN_F
    box(s, x, 1.65, bw, 2.9, fill=fill)
    text(s, x + 0.2, 1.85, bw - 0.4, 0.5, nm, size=22, bold=True, font=MONO)
    text(s, x + 0.2, 2.5, bw - 0.4, 2.0, d, size=15)
    if i < 4:
        arrow(s, x + bw + 0.02, 3.1, x + bw + gap - 0.02, 3.1, color=MUTED, width=2)
    x += bw + gap
box(s, MX, 4.85, 5.85, 1.8, fill=WHITE)
text(s, MX + 0.3, 5.0, 5.3, 0.4, "Registered description", size=18, bold=True, font=HEAD)
text(s, MX + 0.3, 5.5, 5.3, 1.1,
     "The bus wires come from flip-flops loaded once. Your logic may change cmd_addr "
     "a cycle later without touching the burst in flight.", size=15)
box(s, MX + 6.05, 4.85, 5.85, 1.8, fill=WHITE)
text(s, MX + 6.35, 5.0, 5.3, 0.4, "WLAST made here", size=18, bold=True, font=HEAD)
text(s, MX + 6.35, 5.5, 5.3, 1.1,
     "The manager counts beats and raises WLAST itself, so your logic only streams data.",
     size=15)
footer(s)

# =========================================================================
# 9  Slave
# =========================================================================
s = new_slide(LIGHT, "The subordinate has two independent state machines because reads and writes "
              "use different channels. The write engine takes the address first and only then raises "
              "WREADY, applies WSTRB byte by byte, steps the address per beat, and sends one B response. "
              "The read engine fetches the first word on the address handshake and each following word "
              "on the previous beat's handshake, which is why beats come out one per clock. Errors: "
              "DECERR for an address outside the 4 KiB, SLVERR for a malformed request. Importantly, a "
              "failing write is still fully accepted and a failing read still returns every beat, so "
              "the manager never hangs.")
title(s, "The subordinate")
bullets_card(s, MX, 1.55, 3.82, 5.1, "Write engine", [
    "IDLE, DATA, RESP",
    "Takes the address, then raises WREADY",
    "Applies WSTRB byte by byte",
    "Steps the address per beat",
    "One B response per burst, BID copied from AWID",
], fill=VIOLET_F, size=18)
bullets_card(s, MX + 4.04, 1.55, 3.82, 5.1, "Read engine", [
    "IDLE, DATA",
    "First word fetched on the AR handshake",
    "Next word fetched on each R handshake",
    "One beat per clock, no gaps",
    "RLAST on the final beat",
], fill=GREEN_F, size=18)
box(s, MX + 8.08, 1.55, 3.82, 5.1, fill=WHITE)
text(s, MX + 8.38, 1.8, 3.2, 0.45, "Errors", size=19, bold=True, font=HEAD)
text(s, MX + 8.38, 2.4, 3.25, 4.1, [
    {"text": "DECERR", "font": MONO, "bold": True, "size": 15, "color": AMBER_D},
    {"text": "Address outside the 4 KiB region.", "after": 10},
    {"text": "SLVERR", "font": MONO, "bold": True, "size": 15, "color": AMBER_D},
    {"text": "Reserved burst code, beat wider than the bus, bad WRAP length, or WLAST on the wrong beat.",
     "after": 10},
    {"text": "A failing write is still fully accepted. A failing read still returns every beat. "
             "The manager never hangs.", "italic": True, "color": MUTED},
], size=16)
footer(s)

# =========================================================================
# 10  Flip-flop stage
# =========================================================================
s = new_slide(LIGHT, "You asked for the modules to communicate only through flip-flops. A single "
              "flip-flop per wire loses data: the receiver's READY arrives one cycle late, so the sender "
              "can push a beat the flip-flop has already used. The skid buffer fixes that with a spare "
              "slot: if the output is stuck, the next beat parks in the slot and in_ready drops at once, "
              "so a third beat can never arrive. Cost: one clock per stage, so two cycles per transaction "
              "in total, and throughput stays at one beat per clock.")
title(s, "The flip-flop stage: a skid buffer")
picture(s, os.path.join(HERE, "axi4_flipflop_stage.png"), MX, 2.4, w=7.0,
        alt="Skid buffer: an output register and a spare skid slot with in_ready equal to not skid_valid.")
box(s, 8.0, 1.6, 4.63, 5.05, fill=WHITE)
text(s, 8.3, 1.8, 4.0, 0.4, "Why not one flip-flop?", size=19, bold=True, font=HEAD)
text(s, 8.3, 2.3, 4.05, 1.5,
     "READY would reach the sender one cycle late, so it could push a beat the stage "
     "has already used. That beat would be lost.", size=15)
text(s, 8.3, 3.85, 4.0, 0.4, "What it costs", size=19, bold=True, font=HEAD)
text(s, 8.3, 4.35, 4.05, 2.2, [
    {"text": "+2 cycles per transaction, fixed", "after": 6},
    {"text": "Still 1 beat per clock", "after": 6},
    {"text": "Every path between the modules is register to register", "after": 0}], size=15)
footer(s)

# =========================================================================
# 11  Write waveform
# =========================================================================
s = new_slide(LIGHT, "This waveform was recorded from our simulation of the full system with the "
              "flip-flop stages: a 4-beat write to address 0x10. Cycle 0, the host pulses start. Cycle 1, "
              "AWVALID and WVALID go up together and handshake straight away at the stage. Cycle 2, the "
              "address reaches the subordinate, one cycle later: that is the stage. The subordinate "
              "raises WREADY only after it has the address, so on the manager side WREADY dips for one "
              "cycle at 3 while the stage absorbs the wait. The four beats then flow, WLAST on the "
              "fourth, the response arrives at cycle 8 and cmd_done pulses at 9.")
title(s, "A 4-beat write, recorded from the simulation")
picture(s, os.path.join(HERE, "axi4_waveform_write.png"), MX, 1.45, h=5.3,
        alt="Waveform of a 4-beat write through the flip-flop stages.")
text(s, 9.3, 1.55, 3.35, 5.2, [
    {"text": "How to read it", "size": 19, "bold": True, "font": HEAD, "after": 8},
    {"text": "Amber dots are handshakes.", "after": 8},
    {"text": "Slave side is one cycle after master side: that is the flip-flop stage.", "after": 8},
    {"text": "Master WREADY dips at cycle 3 while the slave waits for the address.", "after": 8},
    {"text": "Four beats, WLAST on the fourth, busy for 8 cycles.", "after": 0}], size=15)
footer(s)

# =========================================================================
# 12  Read waveform
# =========================================================================
s = new_slide(LIGHT, "Same address read back. One address goes out at cycle 2 and reaches the "
              "subordinate at 3. The manager raises RREADY as soon as the address is accepted. Data "
              "starts arriving at cycle 5 and the four beats come back to back, one per clock, with "
              "RLAST on the last at cycle 8; cmd_done at 9. After the first beat there are no gaps: that "
              "is the point of fetching the next word on each read handshake.")
title(s, "A 4-beat read, recorded from the simulation")
picture(s, os.path.join(HERE, "axi4_waveform_read.png"), MX, 2.0, w=8.3,
        alt="Waveform of a 4-beat read through the flip-flop stages.")
text(s, 9.3, 2.0, 3.35, 4.0, [
    {"text": "How to read it", "size": 19, "bold": True, "font": HEAD, "after": 8},
    {"text": "One address, then four beats.", "after": 8},
    {"text": "Beats arrive at cycles 5, 6, 7 and 8, one per clock, no gaps.", "after": 8},
    {"text": "RLAST rides on the fourth beat.", "after": 0}], size=15)
footer(s)

# =========================================================================
# 13  Tests
# =========================================================================
s = new_slide(LIGHT, "We verified at three levels so that a failure points at one place. Level 1 "
              "plays the manager against the subordinate alone and forces awkward cases that a real "
              "manager would not produce. Level 2 runs the manager against a mock subordinate whose "
              "delays we control, with always-on monitors that fail the test if VALID drops early or any "
              "payload bit changes while stalled. Level 3 runs the whole system, once with the flip-flop "
              "stages and once without, including a reset in the middle of a burst.")
title(s, "How it was verified")
lv = [
    (BLUE_F, "Level 1", "Subordinate alone", "45",
     "Testbench plays the manager: AW before W, W before AW, response stalls, WRAP, FIXED, byte strobes, bad addresses, ID echo, narrow beats."),
    (GREEN_F, "Level 2", "Manager and mock subordinate", "52",
     "Programmable delays. Monitors fail the test if VALID drops early or a payload bit changes while stalled."),
    (VIOLET_F, "Level 3", "Whole system, run twice", "77 × 2",
     "With and without the flip-flop stages. All burst types, errors, back-pressure, throughput and a mid-burst reset."),
]
cx = MX
for fill, lvl, nm, n, d in lv:
    box(s, cx, 1.55, 3.82, 4.4, fill=fill)
    text(s, cx + 0.3, 1.75, 3.2, 0.35, lvl.upper(), size=13, bold=True, color=MUTED)
    text(s, cx + 0.3, 2.1, 3.2, 0.5, nm, size=19, bold=True, font=HEAD)
    text(s, cx + 0.3, 2.75, 3.2, 0.9, n, size=44, bold=True, font=HEAD)
    text(s, cx + 0.3, 3.7, 3.2, 0.3, "checks", size=13, color=MUTED)
    text(s, cx + 0.3, 4.15, 3.25, 1.7, d, size=14)
    cx += 3.82 + 0.22
box(s, MX, 6.15, 11.9, 0.62, fill=AMBER_F)
text(s, MX + 0.3, 6.15, 11.3, 0.62, "Total: 45 + 52 + 77 + 77 = 251 checks, 0 failing.   Run it:  .\\run_tests.ps1",
     size=17, bold=True, anchor=MSO_ANCHOR.MIDDLE)
footer(s)

# =========================================================================
# 14  Results
# =========================================================================
s = new_slide(LIGHT, "Three numbers to remember. All 251 checks pass. The flip-flop stages add a fixed "
              "two cycles per transaction, which we measured by running the same stimulus with and "
              "without them: a 32-beat write took 37 cycles against 35. Thirty-two beats cannot take "
              "fewer than 32 cycles, so the extra cycles are the whole cost, and it does not grow with "
              "burst length. Throughput stays at one beat per clock.")
title(s, "Measured results")
stats = [("251 / 251", "checks passing", GREEN_F), ("+2 cycles", "fixed cost of the stages", AMBER_F),
         ("1 beat / clock", "sustained throughput", BLUE_F)]
cx = MX
for big, lab, fill in stats:
    box(s, cx, 1.55, 3.82, 2.1, fill=fill)
    text(s, cx + 0.3, 1.85, 3.3, 0.8, big, size=38, bold=True, font=HEAD)
    text(s, cx + 0.3, 2.85, 3.3, 0.5, lab, size=16, color=MUTED)
    cx += 3.82 + 0.22
rows_, cols_ = 3, 4
tbl = s.shapes.add_table(rows_, cols_, Inches(MX), Inches(4.1), Inches(11.9), Inches(1.7)).table
data = [["32-beat burst", "With flip-flop stages", "Wired directly", "Difference"],
        ["Write", "37 cycles", "35 cycles", "+2"],
        ["Read", "36 cycles", "34 cycles", "+2"]]
for r in range(rows_):
    for c in range(cols_):
        cell = tbl.cell(r, c)
        cell.fill.solid()
        cell.fill.fore_color.rgb = rgb(NAVY if r == 0 else WHITE)
        tf = cell.text_frame
        tf.paragraphs[0].text = ""
        run = tf.paragraphs[0].add_run()
        run.text = data[r][c]
        run.font.size = Pt(17)
        run.font.name = BODY
        run.font.bold = (r == 0 or c == 0)
        run.font.color.rgb = rgb(ON_DARK if r == 0 else INK)
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
text(s, MX, 6.05, 11.9, 0.6,
     "32 beats cannot take fewer than 32 cycles, so the extra cycles are the entire cost of the stages. "
     "It does not grow with burst length.", size=15, color=MUTED)
footer(s)

# =========================================================================
# 15  Limits
# =========================================================================
s = new_slide(LIGHT, "Say these before you are asked. One burst at a time per direction, so IDs are "
              "echoed but never used to reorder. No exclusive access. Narrow reads return the whole "
              "word and the manager picks its lanes. Only the start address is range-checked, which is "
              "safe for legal bursts because a legal burst cannot cross a 4 KiB boundary. The host "
              "streams inside the manager are a combinational pass-through with a state gate; the "
              "flip-flop stages sit immediately after, so the module boundary is clean, but it is not "
              "true that every manager output is a flip-flop. A reset in mid-burst discards beats still "
              "in the stages.")
title(s, "Limits, stated plainly")
lims = [
    ("One burst at a time", "Per direction. IDs are echoed but never used to reorder."),
    ("No exclusive access", "AxLOCK is 0, EXOKAY never returned. CACHE, PROT and QOS are carried, not used."),
    ("Narrow reads return the word", "The subordinate does not mask other byte lanes. Legal: the manager picks its lanes."),
    ("Start address is range-checked", "Safe for legal bursts, which cannot cross a 4 KiB boundary."),
    ("Host streams are not registered", "A state-gated pass-through inside the manager. The stages follow immediately."),
    ("Reset mid-burst", "Beats still in the stages are discarded. The outcome is undefined, so it is not asserted."),
]
for i, (h_, d) in enumerate(lims):
    col, row = i % 2, i // 2
    x = MX + col * 6.05
    y = 1.55 + row * 1.7
    box(s, x, y, 5.85, 1.5, fill=WHITE)
    text(s, x + 0.3, y + 0.18, 5.3, 0.4, h_, size=18, bold=True, font=HEAD)
    text(s, x + 0.3, y + 0.68, 5.3, 0.75, d, size=14, color=MUTED)
footer(s)

# =========================================================================
# 16  Demo
# =========================================================================
s = new_slide(NAVY, "Live demo, about two minutes. Open PowerShell in E:\\FPGA_Project and run "
              ".\\run_tests.ps1. It compiles and runs four suites. Point at the three result lines and "
              "the summary. Then run the top suite with -Wave to open the waveform in GTKWave and show "
              "the same shape as the recorded slides: the one-cycle shift from master side to slave "
              "side, and the WREADY dip. If the live run fails for any reason, the slides 11 and 12 "
              "are recorded from this exact simulation.")
title(s, "Live demo", dark=True)
box(s, MX, 1.6, 7.4, 3.0, fill="0F1726")
text(s, MX + 0.4, 1.85, 6.8, 2.6, [
    {"text": "cd E:\\FPGA_Project", "font": MONO, "size": 18, "color": ON_DARK, "after": 14},
    {"text": ".\\run_tests.ps1", "font": MONO, "size": 18, "color": AMBER, "after": 14},
    {"text": ".\\run_tests.ps1 -Suite top -Wave", "font": MONO, "size": 18, "color": AMBER, "after": 0}])
text(s, MX + 8.0, 1.6, 3.9, 0.4, "What to point at", size=20, bold=True, color=AMBER, font=HEAD)
text(s, MX + 8.0, 2.15, 3.9, 3.0, [
    {"text": "Four suites, each ending TEST PASSED", "after": 10},
    {"text": "Check counts: 45, 52, 77 and 77", "after": 10},
    {"text": "In the waveform: slave side lags master side by one cycle", "after": 0}],
     size=16, color=ON_DARK)
box(s, MX, 5.0, 11.9, 1.5, fill="22304A")
text(s, MX + 0.4, 5.2, 11.1, 1.2, [
    {"text": "If the live run fails", "size": 17, "bold": True, "color": AMBER, "after": 6},
    {"text": "Slides 11 and 12 are recorded from this same simulation. Logs and waveforms are "
             "written to the build folder.", "size": 16, "color": ON_DARK}])
footer(s, dark=True)

# =========================================================================
# 17  Questions
# =========================================================================
s = new_slide(LIGHT, "Likely questions with short answers. Why five channels: so address, data and "
              "response move independently and in both directions. Why not a single flip-flop: READY "
              "arrives late and a beat is lost; the spare slot catches it. Why does the subordinate use "
              "WLAST when it knows the length: it cross-checks and reports SLVERR instead of hanging. "
              "Why latch the command: the bus payload must stay stable until the handshake completes. "
              "What about a bad address mid-burst: the burst is still drained and DECERR is returned once.")
title(s, "Questions we expect")
qa = [
    ("Why five channels?", "Address, data and response move independently and in both directions, so a slow response never blocks the next address."),
    ("Why not a single flip-flop per wire?", "READY arrives one cycle late and a beat is lost. The spare slot catches that one beat."),
    ("Why check WLAST if the length is known?", "It is a cross-check. A mismatch ends the burst safely and returns SLVERR."),
    ("Why latch the command?", "The bus payload must not change until its handshake completes. Registers guarantee that."),
    ("What if the address is bad mid-burst?", "The subordinate still accepts every beat, skips the write, and returns DECERR once."),
    ("What does the stage cost?", "Two cycles per transaction, fixed. Throughput stays at one beat per clock."),
]
for i, (q, a) in enumerate(qa):
    col, row = i % 2, i // 2
    x = MX + col * 6.05
    y = 1.55 + row * 1.72
    box(s, x, y, 5.85, 1.55, fill=WHITE)
    text(s, x + 0.3, y + 0.17, 5.3, 0.4, q, size=17, bold=True, font=HEAD)
    text(s, x + 0.3, y + 0.66, 5.3, 0.85, a, size=15, color=MUTED)
footer(s)

prs.save(OUT)
print("saved", OUT, "slides:", len(prs.slides))
