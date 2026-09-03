#!/usr/bin/env python3
"""Generate tools/promo.html — the marketplace card — with the scene captures inlined.

The screenshots are embedded as data URIs so the page renders identically from
any working directory and needs nothing fetched at build time.
"""
import base64
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCENES = ROOT / "assets" / "scenes"

# The captures are one popup each: the plugin's own title header, the board,
# then the key hints. The card has its own title and its own captions, so both
# of those are cropped away and only the board is kept.
CROP_X, CROP_Y, CROP_W, CROP_H = 0, 142, 528, 880

PANELS = [
    ("off.png",      "ATTRACT",   "insert coin"),
    ("play.png",     "IN PLAY",   "aim, bounce, match three"),
    ("chain.png",    "CHAIN",     "clusters cut loose and falling"),
    ("gameover.png", "GAME OVER", "today's best, and all time"),
]


def uri(name):
    out = subprocess.run(
        ["magick", str(SCENES / name),
         "-crop", f"{CROP_W}x{CROP_H}+{CROP_X}+{CROP_Y}", "+repage", "png:-"],
        check=True, capture_output=True).stdout
    return "data:image/png;base64," + base64.b64encode(out).decode()


cards = "\n".join(
    f'''      <figure class="card">
        <div class="shot"><img src="{uri(f)}" alt="{label}"></div>
        <figcaption><b>{label}</b> {note}</figcaption>
      </figure>''' for f, label, note in PANELS)

HTML = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ width:1600px; height:1000px; background:#080a12; overflow:hidden;
         font-family:'JetBrainsMono Nerd Font','JetBrainsMono NF',monospace; }}
  body::before {{ content:""; position:absolute; inset:0;
    background:radial-gradient(1100px 620px at 50% 116%, #06303a 0%, transparent 70%),
               radial-gradient(760px 460px at 6% -12%, #23093a 0%, transparent 72%); }}
  .wrap {{ position:relative; padding:52px 56px; height:100%; display:flex; flex-direction:column; }}
  .brand {{ display:flex; align-items:center; gap:13px; margin-bottom:20px; }}
  /* Drawn, not a glyph: a Nerd Font codepoint renders as a box in headless
     chromium, which is a font that may or may not be installed wherever this
     runs. A bubble costs one div. */
  .brand .mark {{ width:19px; height:19px; border-radius:50%; flex:none;
                 background:radial-gradient(circle at 32% 30%, #bff9ff 0%, #00F5FF 45%, #04616e 100%);
                 box-shadow:0 0 0 3px rgba(255,0,110,.25), 0 0 16px rgba(0,245,255,.7); }}
  .brand .word {{ color:#6f7a90; font-size:15px; font-weight:700; letter-spacing:6px; }}
  .head {{ display:flex; gap:60px; align-items:flex-end; margin-bottom:30px; }}
  h1 {{ color:#e6edf6; font-size:44px; line-height:1.14; font-weight:800;
        letter-spacing:-0.5px; flex:none; }}
  h1 .acc {{ color:#00F5FF; }}
  .side {{ flex:1; padding-bottom:4px; }}
  .sub {{ color:#818d a3; font-size:16.5px; line-height:1.55; }}
  .sub {{ color:#818da3; }}
  .sub em {{ font-style:normal; color:#e6edf6; }}
  .feat {{ list-style:none; margin-top:15px; display:flex; gap:32px; }}
  .feat li {{ color:#9aa6bd; font-size:14.5px; line-height:1.45; padding-left:19px;
              position:relative; flex:1; }}
  .feat li::before {{ content:"\\25B8"; color:#FF006E; font-weight:700; position:absolute; left:0; }}
  .feat b {{ color:#e6edf6; }}
  .grid {{ flex:1; display:grid; grid-template-columns:repeat(4, 1fr); gap:0 26px; align-items:start; }}
  .card {{ display:flex; flex-direction:column; min-height:0; }}
  .card .shot {{ border-radius:9px; border:1px solid #23384a;
                overflow:hidden; box-shadow:0 18px 44px rgba(0,0,0,.6);
                -webkit-mask-image:linear-gradient(to bottom,#000 96%,transparent 100%);
                mask-image:linear-gradient(to bottom,#000 96%,transparent 100%); }}
  .card .shot img {{ display:block; width:100%; }}
  .card figcaption {{ margin-top:11px; color:#6f7a90; font-size:13px; }}
  .card figcaption b {{ color:#00F5FF; letter-spacing:2.2px; margin-right:9px; }}
  .install {{ margin-top:24px; display:inline-block; background:#0d1420; border:1px solid #1f3040;
             border-radius:9px; padding:12px 18px; color:#9aa6bd; font-size:13.5px; white-space:nowrap; }}
  .install .p {{ color:#6f7a90; }} .install .c {{ color:#00F5FF; }}
</style></head><body>
  <div class="wrap">
    <div class="brand"><span class="mark"></span><span class="word">NEON BUBBLE POP</span></div>
    <div class="head">
      <h1>One board.<br><span class="acc">Every day.</span></h1>
      <div class="side">
        <div class="sub">A bubble shooter in the bar, seeded from the date &mdash; <em>the same puzzle for everyone, every day</em>, with today's best kept apart from your all-time best. Match three to pop, and cut clusters loose so they fall: a bubble you drop is worth more than one you pop, which is the whole game.</div>
        <ul class="feat">
          <li><b>Earned specials.</b> Clear enough and the gun loads a bomb, or a wildcard</li>
          <li><b>Bounce off the walls</b> &mdash; the guide is drawn from the numbers the shot uses</li>
          <li><b>No network, no account.</b> One file on disk: your high score</li>
        </ul>
        <div class="install"><span class="p">$</span> omarchy plugin add <span class="c">github.com/Snackwrap/omarchy-neonbubble</span></div>
      </div>
    </div>
    <div class="grid">
{cards}
    </div>
  </div>
</body></html>"""

(ROOT / "tools" / "promo.html").write_text(HTML, encoding="utf-8")
print("tools/promo.html written")
