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
    text(slide, MX, 7.0, 8, 0.3, "AXI4 manager and subordinate in Verilog",
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
              "wired directly together over the five AXI channels. Everything shown today comes from the "
              "simulation in the project folder, so every number can be reproduced live. The five amber "
              "pills are the five AXI channels; we come back to each one.")
text(s, 0.9, 1.5, 11, 0.4, "VIVA DEMONSTRATION", size=18, bold=True, color=AMBER, name="Eyebrow")
text(s, 0.9, 2.05, 11.2, 2.4, "AXI4 manager and subordinate in Verilog", size=60, bold=True,
     color=ON_DARK, font=HEAD, name="Title")
text(s, 0.9, 4.25, 10.5, 1.0,
     "Burst transfers over the five AXI4 channels, with 156 checks passing in simulation.",
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
s = new_slide(LIGHT, "Three files. The manager is the active side: your logic gives it a simple "
              "request and it runs the whole AXI conversation. The subordinate is a small memory that "
              "understands that conversation. The top level only wires the two together. Stress that this "
              "is full AXI4: bursts, IDs and the LAST signals, not the single-word AXI4-Lite.")
title(s, "What we built")
text(s, MX, 1.4, 11.9, 0.5, "Both ends of an AXI4 connection, wired together.",
     size=20, color=MUTED)
cards = [
    (BLUE_F, BLUE, "Manager", "axi4_master.v",
     "Takes a simple burst request from your logic and runs the full AXI4 exchange: address, data beats, response."),
    (VIOLET_F, VIOLET, "Subordinate", "axi4_slave.v",
     "A 4 KiB memory. Accepts bursts of 1 to 256 beats in FIXED, INCR or WRAP order and answers OKAY."),
    (GREEN_F, GREEN, "Top level", "axi4_top.v",
     "Wires the manager directly to the subordinate over the five AXI channels. Nothing sits between them."),
]
cx = MX
for fill, accent, head_, fname, body in cards:
    box(s, cx, 2.25, 3.82, 3.9, fill=fill)
    text(s, cx + 0.35, 2.55, 3.1, 0.5, head_, size=26, bold=True, font=HEAD)
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
              "manager turns those into the five AXI channels, shown with their real signal names. The "
              "channels run straight into the subordinate, which has a write engine, a read engine and a "
              "4 KiB memory. The three cards at the bottom are the design points we will justify.")
title(s, "System architecture")
picture(s, os.path.join(HERE, "axi4_block_diagram.png"), 0.9, 1.45, w=11.5,
        alt="Block diagram: your logic, axi4_master, five AXI4 channels with signal names, axi4_slave with write engine, read engine and 4 KiB memory.")
text(s, MX, 6.65, 11.9, 0.3,
     "The master and slave are wired directly. The burst description is copied into registers once, at the start.",
     size=14, color=MUTED, italic=True)
footer(s)

# =========================================================================
# 7  Host interface
# =========================================================================
s = new_slide(LIGHT, "The host side of the manager is deliberately small. You pulse a start signal "
              "with a burst description; for a write you push beats into the write stream, for a read "
              "you take them from the read stream. cmd_done is a one-cycle pulse when the burst finishes "
              "and cmd_resp carries the response. A start is taken only when the manager is idle, and "
              "if both starts are high the write wins. The manager copies the description into "
              "registers, so you may change cmd_addr straight after the pulse.")
title(s, "Host interface of the manager")
quad = [
    (BLUE_F, "Command port", "you drive",
     ["cmd_start_write", "cmd_start_read", "cmd_id[3:0]", "cmd_addr[31:0]", "cmd_len[7:0]",
      "cmd_size[2:0]", "cmd_burst[1:0]"]),
    (GREEN_F, "Status", "you read",
     ["cmd_done  (1-cycle pulse)", "cmd_resp[1:0]"]),
    (AMBER_F, "Write stream", "you push beats",
     ["hw_data[31:0]", "hw_strb[3:0]", "hw_valid", "hw_ready"]),
    (VIOLET_F, "Read stream", "you take beats",
     ["hr_data[31:0]", "hr_valid", "hr_ready"]),
]
pos = [(MX, 1.55), (MX + 6.05, 1.55), (MX, 4.0), (MX + 6.05, 4.0)]
for (fill, hd, sub, items), (x, y) in zip(quad, pos):
    box(s, x, y, 5.85, 2.3, fill=fill)
    text(s, x + 0.3, y + 0.2, 3.0, 0.4, hd, size=20, bold=True, font=HEAD)
    text(s, x + 3.2, y + 0.26, 2.4, 0.35, sub, size=13, color=MUTED, align=PP_ALIGN.RIGHT)
    half = (len(items) + 1) // 2 if len(items) > 3 else len(items)
    text(s, x + 0.3, y + 0.75, 2.9, 1.5, [{"text": t, "font": MONO, "size": 13, "after": 3}
                                          for t in items[:half]])
    text(s, x + 3.2, y + 0.75, 2.5, 1.5, [{"text": t, "font": MONO, "size": 13, "after": 3}
                                          for t in items[half:]])
text(s, MX, 6.45, 11.9, 0.4,
     "A start is taken only when the manager is idle. If both starts arrive together, the write wins.",
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
    ("RDATA", "Passes each beat to the host and finishes when RLAST arrives."),
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
              "on the previous beat's handshake, which is why beats come out one per clock. Every "
              "response is OKAY: this subordinate does no request checking, so an address beyond "
              "the 4 KiB simply wraps inside the memory.")
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
text(s, MX + 8.38, 1.8, 3.2, 0.45, "Responses", size=19, bold=True, font=HEAD)
text(s, MX + 8.38, 2.4, 3.25, 4.1, [
    {"text": "OKAY on every transfer", "font": MONO, "bold": True, "size": 15, "color": AMBER_D,
     "after": 4},
    {"text": "BRESP and RRESP are tied to 00.", "after": 12},
    {"text": "No request checking", "font": MONO, "bold": True, "size": 15, "color": AMBER_D,
     "after": 4},
    {"text": "A write ends on WLAST. A read ends after ARLEN + 1 beats. An address beyond the "
             "memory wraps inside it.", "after": 0},
], size=16)
footer(s)

# =========================================================================
# 10  End to end
# =========================================================================
s = new_slide(LIGHT, "One request from start to finish: write four words to address 0x10. The host "
              "pulses the start with cmd_len = 3 and streams four words. The manager copies the "
              "description, sends the address and the beats and raises WLAST on the fourth. The "
              "subordinate takes the address first, then writes each word into memory. After WLAST "
              "it sends one response. The manager takes it and pulses cmd_done. Measured: six busy "
              "cycles for four beats.")
title(s, "One write, end to end")
text(s, MX, 1.4, 11.9, 0.5, "Writing four words to address 0x10.", size=20, color=MUTED)
steps = [
    ("1  Host", BLUE_F, "Pulses cmd_start_write with cmd_addr = 0x10 and cmd_len = 3, then streams four words."),
    ("2  Master", BLUE_F, "Copies the description, sends AW, and sends the four beats on W with WLAST on the fourth."),
    ("3  Subordinate", VIOLET_F, "Takes the address first, then raises WREADY and writes each word into memory."),
    ("4  Response", VIOLET_F, "After WLAST it sends one B response: OKAY, with BID copied from AWID."),
    ("5  Done", GREEN_F, "The master takes the response and pulses cmd_done. The burst kept it busy for 6 cycles."),
]
bw, gap = 2.18, 0.25
x = MX
for i, (hd, fill, d) in enumerate(steps):
    box(s, x, 2.25, bw, 3.7, fill=fill)
    text(s, x + 0.2, 2.45, bw - 0.4, 0.9, hd, size=20, bold=True, font=HEAD)
    text(s, x + 0.2, 3.45, bw - 0.4, 2.4, d, size=16)
    if i < 4:
        arrow(s, x + bw + 0.02, 4.1, x + bw + gap - 0.02, 4.1, color=MUTED, width=2)
    x += bw + gap
text(s, MX, 6.3, 11.9, 0.5, "The waveforms on the next two slides show the same write and the matching read.",
     size=16, color=MUTED, italic=True)
footer(s)

# =========================================================================
# 11  Write waveform
# =========================================================================
s = new_slide(LIGHT, "This waveform was recorded from our simulation of the full system: a 4-beat "
              "write to address 0x10. Cycle 0, the host pulses start. Cycle 1, AWVALID and WVALID go up "
              "together and the address handshakes straight away; WREADY is still low because the "
              "subordinate takes the address first. From cycle 2 the four beats flow one per clock, "
              "WLAST rides on the fourth at cycle 5, the response handshakes at cycle 6 and cmd_done "
              "pulses at 7. The master was busy for 6 cycles.")
title(s, "A 4-beat write, recorded from the simulation")
picture(s, os.path.join(HERE, "axi4_waveform_write.png"), MX, 1.5, w=8.4,
        alt="Waveform of a 4-beat write on the bare design.")
text(s, 9.3, 1.55, 3.35, 5.2, [
    {"text": "How to read it", "size": 19, "bold": True, "font": HEAD, "after": 8},
    {"text": "Amber dots are handshakes.", "after": 8},
    {"text": "WREADY stays low in cycle 1: the subordinate takes the address first.", "after": 8},
    {"text": "Four beats at cycles 2 to 5, WLAST on the fourth.", "after": 8},
    {"text": "One response at cycle 6, cmd_done at 7. Busy for 6 cycles.", "after": 0}], size=15)
footer(s)

# =========================================================================
# 12  Read waveform
# =========================================================================
s = new_slide(LIGHT, "Same address read back. One address goes out and is accepted at cycle 1. The "
              "manager raises RREADY as soon as the address is accepted. The four beats come back to "
              "back at cycles 2 to 5, one per clock, with RLAST on the fourth. cmd_done pulses at 6. "
              "After the address there are no gaps: that is the point of fetching the next word on "
              "each read handshake.")
title(s, "A 4-beat read, recorded from the simulation")
picture(s, os.path.join(HERE, "axi4_waveform_read.png"), MX, 2.0, w=8.3,
        alt="Waveform of a 4-beat read on the bare design.")
text(s, 9.3, 2.0, 3.35, 4.0, [
    {"text": "How to read it", "size": 19, "bold": True, "font": HEAD, "after": 8},
    {"text": "One address at cycle 1.", "after": 8},
    {"text": "Four beats at cycles 2 to 5, one per clock, no gaps.", "after": 8},
    {"text": "RLAST rides on the fourth beat. cmd_done at 6. Busy for 5 cycles.", "after": 0}], size=15)
footer(s)

# =========================================================================
# 13  Tests
# =========================================================================
s = new_slide(LIGHT, "We verified at three levels so that a failure points at one place. Level 1 "
              "plays the manager against the subordinate alone and forces awkward cases that a real "
              "manager would not produce. Level 2 runs the manager against a mock subordinate whose "
              "delays we control, with always-on monitors that fail the test if VALID drops early or any "
              "payload bit changes while stalled. Level 3 runs the whole system through the host ports, "
              "including a reset in the middle of a burst.")
title(s, "How it was verified")
lv = [
    (BLUE_F, "Level 1", "Subordinate alone", "38",
     "Testbench plays the manager: AW before W, stalled responses, WRAP, FIXED, INCR, byte strobes, ID echo, narrow 1-byte beats."),
    (GREEN_F, "Level 2", "Manager and mock subordinate", "46",
     "Programmable delays. Monitors fail the test if VALID drops early or a payload bit changes while stalled."),
    (VIOLET_F, "Level 3", "Whole system", "72",
     "All burst types, byte strobes, host back-pressure, throughput and a reset in the middle of a burst."),
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
text(s, MX + 0.3, 6.15, 11.3, 0.62, "Total: 38 + 46 + 72 = 156 checks, 0 failing.   Run it:  .\\run_tests.ps1",
     size=17, bold=True, anchor=MSO_ANCHOR.MIDDLE)
footer(s)

# =========================================================================
# 14  Results
# =========================================================================
s = new_slide(LIGHT, "Three numbers to remember. All 156 checks pass. Sustained throughput is one beat "
              "per clock. A 32-beat write takes 35 cycles and a 32-beat read 34, measured from the "
              "start pulse to the done pulse. Thirty-two beats cannot take fewer than 32 cycles, so "
              "the remaining 3 and 2 cycles are the fixed cost of the address and response handshakes. "
              "That overhead does not grow with burst length: the 8-beat write took 11 cycles, the "
              "same 3 cycles over.")
title(s, "Measured results")
stats = [("156 / 156", "checks passing", GREEN_F), ("1 beat / clock", "sustained throughput", BLUE_F),
         ("35 cycles", "a 32-beat write", AMBER_F)]
cx = MX
for big, lab, fill in stats:
    box(s, cx, 1.55, 3.82, 2.1, fill=fill)
    text(s, cx + 0.3, 1.85, 3.3, 0.8, big, size=38, bold=True, font=HEAD)
    text(s, cx + 0.3, 2.85, 3.3, 0.5, lab, size=16, color=MUTED)
    cx += 3.82 + 0.22
rows_, cols_ = 3, 4
tbl = s.shapes.add_table(rows_, cols_, Inches(MX), Inches(4.1), Inches(11.9), Inches(1.7)).table
data = [["32-beat burst", "Cycles, start to done", "Beats", "Fixed overhead"],
        ["Write", "35", "32", "3 cycles"],
        ["Read", "34", "32", "2 cycles"]]
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
     "The overhead is the address and response handshakes. It does not grow with burst length.",
     size=15, color=MUTED)
footer(s)

# =========================================================================
# 15  Limits
# =========================================================================
s = new_slide(LIGHT, "Say these before you are asked. One burst at a time per direction, so IDs are "
              "echoed but never used to reorder. Every response is OKAY: there are no error "
              "responses, and an address beyond the 4 KiB wraps inside the memory. No exclusive "
              "access. Narrow reads return the whole word and the manager picks its lanes. The host "
              "streams inside the manager are a combinational pass-through with a state gate. A reset "
              "in mid-burst leaves the memory as it was, and which beats landed is not defined.")
title(s, "Limits, stated plainly")
lims = [
    ("One burst at a time", "Per direction. IDs are echoed but never used to reorder."),
    ("No error responses", "Every response is OKAY. A bad address wraps inside the 4 KiB."),
    ("No exclusive access", "AxLOCK is 0, EXOKAY never returned. CACHE, PROT and QOS are carried, not used."),
    ("Narrow reads return the word", "The subordinate does not mask other byte lanes. Legal: the manager picks its lanes."),
    ("Host streams pass straight through", "A state-gated pass-through inside the manager, not registered."),
    ("Reset mid-burst", "The memory is not cleared by reset. Which beats landed is undefined, so it is not asserted."),
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
              ".\\run_tests.ps1. It compiles and runs three suites. Point at the three result lines and "
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
    {"text": "Three suites, each ending TEST PASSED", "after": 10},
    {"text": "Check counts: 38, 46 and 72", "after": 10},
    {"text": "In the waveform: WREADY waits for the address", "after": 0}],
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
              "response move independently and in both directions. How does the subordinate know the "
              "burst ended: WLAST on writes, a beat count on reads. What about a bad address: this "
              "subordinate does no checking, the address wraps and the response is OKAY. Why latch the "
              "command: the bus payload must stay stable until the handshake completes. What limits "
              "throughput: one beat per clock after a few cycles of address and response overhead.")
title(s, "Questions we expect")
qa = [
    ("Why five channels?", "Address, data and response move independently and in both directions, so a slow response never blocks the next address."),
    ("How does it know a burst ended?", "On writes, from WLAST. On reads, by counting ARLEN + 1 beats."),
    ("What happens on a bad address?", "Nothing is checked. The address wraps inside the 4 KiB and the response is OKAY."),
    ("Why latch the command?", "The bus payload must not change until its handshake completes. Registers guarantee that."),
    ("Why does WREADY wait for the address?", "The subordinate takes the address first, then the data. The standard allows it."),
    ("What limits throughput?", "One beat per clock, plus a few cycles of address and response overhead: 35 cycles for 32 beats."),
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
print('saved', OUT, 'slides:', len(prs.slides))
