#!/usr/bin/env python3
"""Generate a private, self-contained workout report from a Garmin FIT export.

Usage:
    tools/.venv/bin/python tools/report_fit.py activity.fit
    tools/.venv/bin/python tools/report_fit.py garmin-export.zip -o report.html

The report never uploads data. It visualizes the app's per-second motion
features alongside Garmin heart rate and the work/rest laps recorded by the app.
"""

from __future__ import annotations

import argparse
import html
import json
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

from fitparse import FitFile

try:
    from validate_workout import validate
except ModuleNotFoundError:  # Imported as tools.report_fit by the test suite.
    from tools.validate_workout import validate


MOVEMENTS = {
    0: "360",
    1: "10-to-2",
    2: "Mill",
    3: "Shield cast",
    4: "Flow / other",
    5: "Reverse mill",
    6: "Bullwhip",
    7: "Combo",
}
SIDES = {0: "Left", 1: "Right", 2: "Alternating", 3: "Two-handed"}


def value(message, name, default=None):
    result = message.get_value(name)
    return default if result is None else result


def timestamp(value_) -> float | None:
    if isinstance(value_, datetime):
        return value_.timestamp()
    return None


def fit_path(source: Path, directory: Path) -> Path:
    """Resolve a raw FIT file or safely extract the activity from a ZIP."""
    if source.suffix.lower() != ".zip":
        return source
    with zipfile.ZipFile(source) as archive:
        candidates = [
            item for item in archive.infolist()
            if not item.is_dir() and item.filename.lower().endswith(".fit")
        ]
        if not candidates:
            raise ValueError(f"{source} contains no FIT activity")
        if len(candidates) > 1:
            candidates.sort(key=lambda item: ("activity" not in item.filename.lower(), item.filename))
        item = candidates[0]
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / Path(item.filename).name
        destination.write_bytes(archive.read(item))
        return destination


def collect(fit: FitFile) -> dict:
    sessions = list(fit.get_messages("session"))
    if not sessions:
        raise ValueError("FIT file contains no session")
    session = sessions[0]
    session_start = value(session, "start_time")
    activities = list(fit.get_messages("activity"))
    local_start = value(activities[0], "local_timestamp") if activities else None
    equipment = None
    for field in getattr(session, "fields", []):
        candidate = getattr(field, "value", None)
        if isinstance(candidate, str) and any(
            name in candidate.lower() for name in ("mace", "club", "bulava")
        ):
            equipment = candidate
            break

    raw_laps = []
    for index, lap in enumerate(fit.get_messages("lap"), 1):
        start = timestamp(value(lap, "start_time"))
        elapsed = value(lap, "total_elapsed_time")
        if start is None or elapsed is None:
            continue
        phase = value(lap, "phase")
        set_number = int(value(lap, "set_number", 0))
        is_work = phase == 1 if phase is not None else set_number > 0
        raw_laps.append({
            "lap": index,
            "start_abs": start,
            "end_abs": start + float(elapsed),
            "set": set_number,
            "phase": "work" if is_work else "rest",
            "duration": round(float(value(lap, "phase_duration", elapsed)), 1),
            "elapsed": round(float(elapsed), 1),
            "movement": MOVEMENTS.get(value(lap, "movement_type"), "Unknown"),
            "side": SIDES.get(value(lap, "working_side"), "Unknown"),
            "weight": value(lap, "implement_weight"),
            "smoothness": value(lap, "set_smoothness"),
            "swings": value(lap, "swing_count"),
            "exposure": value(lap, "motion_exposure"),
            "motion_peak": value(lap, "motion_peak"),
            "active_seconds": value(lap, "active_seconds"),
            "weight_volume": value(lap, "weight_volume"),
        })

    records = []
    for record in fit.get_messages("record"):
        at = timestamp(value(record, "timestamp"))
        if at is None:
            continue
        point = {
            "at_abs": at,
            "hr": value(record, "heart_rate"),
            "rms": value(record, "accel_rms"),
            "peak": value(record, "accel_peak"),
            "zc": value(record, "accel_zc"),
        }
        if any(point[key] is not None for key in ("hr", "rms", "peak", "zc")):
            records.append(point)

    starts = [lap["start_abs"] for lap in raw_laps]
    starts += [point["at_abs"] for point in records]
    origin = min(starts) if starts else 0
    for lap in raw_laps:
        lap["start"] = round(lap.pop("start_abs") - origin, 3)
        lap["end"] = round(lap.pop("end_abs") - origin, 3)
    for point in records:
        point["t"] = round(point.pop("at_abs") - origin, 3)

    work_laps = [lap for lap in raw_laps if lap["phase"] == "work" and lap["set"] > 0]
    valid_sets = [lap for lap in work_laps if lap["elapsed"] >= 10]
    movement = next((lap["movement"] for lap in work_laps if lap["movement"] != "Unknown"), "Unknown")
    side = next((lap["side"] for lap in work_laps if lap["side"] != "Unknown"), "Unknown")

    return {
        "summary": {
            "elapsed": round(float(value(session, "total_elapsed_time", 0)), 1),
            "timer": round(float(value(session, "total_timer_time", 0)), 1),
            "avg_hr": value(session, "avg_heart_rate"),
            "max_hr": value(session, "max_heart_rate"),
            "sets": value(session, "total_sets", len(work_laps)),
            "movement": movement,
            "side": side,
            "equipment": equipment,
            "date": (local_start if isinstance(local_start, datetime) else session_start).strftime("%d %b %Y")
                    if isinstance(local_start, datetime) or isinstance(session_start, datetime) else None,
            "work_seconds": round(sum(lap["elapsed"] for lap in work_laps), 1),
            "rest_seconds": round(sum(lap["elapsed"] for lap in raw_laps if lap["phase"] == "rest"), 1),
            "valid_sets": len(valid_sets),
        },
        "laps": raw_laps,
        "records": records,
    }


def render(report: dict, title: str) -> str:
    report = {**report, "quality": report.get("quality") or validate(report)}
    payload = json.dumps(report, separators=(",", ":"), allow_nan=False)
    safe_title = html.escape(title)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{safe_title}</title>
<style>
  :root {{ color-scheme: light dark; --bg:#f7f5f1; --surface:#fff; --ink:#24211d; --muted:#6f6961; --grid:#d9d4cc; --work:#e66b38; --rest:#4d7ca8; --rms:#bd3e14; --peak:#e4a02b; --hr:#b32747; --smooth:#397a68; --warn:#ad561f; --error:#a33131; --ok:#397a68; }}
  @media (prefers-color-scheme:dark) {{ :root {{ --bg:#171614; --surface:#211f1c; --ink:#f3eee7; --muted:#b8afa4; --grid:#49443e; --work:#f1814f; --rest:#6c9ccc; --rms:#ff7848; --peak:#ffc052; --hr:#ff698b; --smooth:#67c4a9; --warn:#ff9a55; --error:#ff7777; --ok:#67c4a9; }} }}
  * {{ box-sizing:border-box; }} body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.45 system-ui,-apple-system,sans-serif; }}
  main {{ max-width:1120px; margin:auto; padding:28px 24px 56px; }} h1 {{ margin:0 0 4px; font-size:clamp(24px,4vw,38px); font-weight:600; }}
  .subtitle {{ color:var(--muted); margin-bottom:24px; }} .metrics {{ display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:12px; margin-bottom:28px; }}
  .metric {{ border-top:2px solid var(--grid); padding-top:8px; }} .metric strong {{ display:block; font-size:21px; font-weight:600; }} .metric span {{ color:var(--muted); font-size:13px; }}
  section {{ margin:30px 0; }} h2 {{ font-size:18px; font-weight:600; margin:0 0 3px; }} .note {{ color:var(--muted); margin:0 0 12px; font-size:13px; }}
  svg {{ display:block; width:100%; height:auto; background:var(--surface); border:1px solid var(--grid); }} .grid line {{ stroke:var(--grid); stroke-opacity:.65; }}
  .axis text,.label {{ fill:var(--muted); font-size:12px; }} .axis path,.axis line {{ stroke:var(--grid); }} .phase-work {{ fill:var(--work); opacity:.10; }} .phase-rest {{ fill:var(--rest); opacity:.075; }}
  .line-rms {{ fill:none; stroke:var(--rms); stroke-width:1.5; }} .line-peak {{ fill:none; stroke:var(--peak); stroke-width:1.1; opacity:.72; }} .line-hr {{ fill:none; stroke:var(--hr); stroke-width:1.4; }}
  .smooth-bar {{ fill:var(--smooth); }} .duration-mark {{ fill:var(--work); }} .anomaly {{ fill:var(--warn); }} .legend {{ display:flex; flex-wrap:wrap; gap:14px; margin:6px 0 10px; color:var(--muted); font-size:13px; }}
  .legend button {{ color:inherit; border:0; padding:2px 0; background:none; cursor:pointer; }} .legend button[aria-pressed=false] {{ opacity:.4; }} .swatch {{ width:18px; height:3px; display:inline-block; vertical-align:middle; margin-right:5px; }}
  .tooltip {{ position:fixed; pointer-events:none; display:none; background:var(--surface); color:var(--ink); border:1px solid var(--grid); padding:7px 9px; font-size:12px; z-index:5; }}
  .insight {{ border-left:3px solid var(--warn); padding:8px 12px; color:var(--muted); }}
  .quality {{ display:grid; grid-template-columns:minmax(140px,170px) minmax(0,1fr); gap:18px; padding:18px; border:1px solid var(--grid); background:var(--surface); }}
  .quality > div {{ min-width:0; }}
  .quality-score strong {{ display:block; font-size:42px; line-height:1; }} .quality-score span {{ color:var(--muted); }}
  .availability {{ display:flex; flex-wrap:wrap; gap:8px; margin:0 0 12px; }} .chip {{ border:1px solid var(--grid); border-radius:999px; padding:3px 9px; font-size:12px; }}
  .finding {{ display:flex; gap:8px; padding:7px 0; border-top:1px solid var(--grid); }} .finding b {{ flex:0 0 58px; text-transform:uppercase; font-size:11px; letter-spacing:.04em; }} .finding span,.finding a {{ min-width:0; overflow-wrap:anywhere; }}
  .finding-warning b {{ color:var(--warn); }} .finding-error b {{ color:var(--error); }} .finding-info b {{ color:var(--muted); }} .finding a {{ color:inherit; }}
  .provenance {{ color:var(--muted); font-size:12px; margin:10px 0 0; overflow-wrap:anywhere; }} :target {{ outline:3px solid var(--warn); outline-offset:3px; }}
  @media (max-width:700px) {{ main {{ padding:20px 12px 40px; }} .metrics {{ grid-template-columns:repeat(2,minmax(0,1fr)); }} .quality {{ grid-template-columns:1fr; }} }}
</style>
</head>
<body><main>
  <h1>Mace &amp; Clubs workout</h1><div class="subtitle" id="subtitle"></div>
  <div class="metrics" id="metrics"></div>
  <section><h2>Recording quality</h2><p class="note">Checks whether this export is complete and internally consistent. It is not an injury or readiness score.</p><div class="quality"><div class="quality-score"><strong id="quality-score"></strong><span id="quality-status"></span></div><div><div class="availability" id="availability"></div><div id="findings"></div><p class="provenance"><b>Measured:</b> heart rate, lap timing, and wrist acceleration. <b>Derived:</b> coverage, consistency findings, smoothness, and this quality score.</p></div></div></section>
  <section><h2>Motion through the session</h2><p class="note">Per-second wrist acceleration. Work and rest intervals are shaded.</p>
    <div class="legend"><button data-series="rms" aria-pressed="true"><i class="swatch" style="background:var(--rms)"></i>Dynamic intensity (RMS)</button><button data-series="peak" aria-pressed="true"><i class="swatch" style="background:var(--peak)"></i>Peak acceleration</button><button data-series="hr" aria-pressed="true"><i class="swatch" style="background:var(--hr)"></i>Heart rate</button><span><i class="swatch" style="height:10px;background:var(--work);opacity:.3"></i>Work</span><span><i class="swatch" style="height:10px;background:var(--rest);opacity:.25"></i>Rest</span></div>
    <svg id="timeline" role="img" aria-label="Motion and heart rate timeline"></svg>
  </section>
  <section><h2>Set consistency</h2><p class="note">Smoothness is a repeatability score from wrist motion; very short sets are flagged and excluded from trend interpretation.</p><svg id="sets" role="img" aria-label="Smoothness and duration by set"></svg></section>
  <p class="insight" id="insight"></p>
  <div class="tooltip" id="tooltip" role="tooltip"></div>
</main>
<script>
const report={payload};
const root=document.documentElement, summary=report.summary, records=report.records, laps=report.laps, quality=report.quality;
const work=laps.filter(d=>d.phase==='work'&&d.set>0), valid=work.filter(d=>d.elapsed>=10);
const fmt=s=>{{s=Math.round(s);return `${{Math.floor(s/60)}}:${{String(s%60).padStart(2,'0')}}`;}};
document.getElementById('subtitle').textContent=[summary.date,summary.equipment,summary.movement,summary.side,`${{summary.sets}} recorded sets`].filter(Boolean).join(' · ');
const metrics=[['Duration',fmt(summary.elapsed)],['Work',fmt(summary.work_seconds)],['Rest',fmt(summary.rest_seconds)],['Average HR',summary.avg_hr?`${{summary.avg_hr}} bpm`:'—'],['Max HR',summary.max_hr?`${{summary.max_hr}} bpm`:'—']];
document.getElementById('metrics').innerHTML=metrics.map(([k,v])=>`<div class="metric"><strong>${{v}}</strong><span>${{k}}</span></div>`).join('');
document.getElementById('quality-score').textContent=`${{quality.score}}/100`;
document.getElementById('quality-status').textContent={{healthy:'Healthy recording',usable_with_gaps:'Usable with gaps',invalid:'Structurally invalid'}}[quality.status]||quality.status;
const availability=document.getElementById('availability');
for(const [label,key] of [['Motion series','motion'],['Heart rate','heart_rate']]){{const chip=document.createElement('span');chip.className='chip';chip.textContent=`${{label}} ${{Math.round(quality.coverage[key]*100)}}%`;availability.append(chip);}}
const findings=document.getElementById('findings'),items=quality.findings.length?quality.findings:[{{severity:'info',message:'No integrity or data-quality issues found.',target:null}}];
for(const item of items){{const row=document.createElement('div');row.className=`finding finding-${{item.severity}}`;const level=document.createElement('b');level.textContent=item.severity;const message=item.target?document.createElement('a'):document.createElement('span');message.textContent=item.message;if(item.target)message.href=`#${{item.target}}`;row.append(level,message);findings.append(row);}}
const ns='http://www.w3.org/2000/svg', css=n=>getComputedStyle(root).getPropertyValue(n).trim();
const S=(tag,attrs={{}})=>{{const e=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);return e;}};
const extent=(a,key)=>{{const v=a.map(key).filter(Number.isFinite);return [Math.min(...v),Math.max(...v)];}};
const scale=(d0,d1,r0,r1)=>v=>r0+(v-d0)*(r1-r0)/(d1-d0||1);
const linePath=(data,x,y,key)=>data.filter(d=>Number.isFinite(key(d))).map((d,i)=>`${{i?'L':'M'}}${{x(d.t).toFixed(1)}},${{y(key(d)).toFixed(1)}}`).join(' ');
const tooltip=document.getElementById('tooltip');
function yAxis(svg,box,domain,label){{
  for(let i=0;i<=3;i++){{const yy=box.t+(box.b-box.t)*i/3,val=domain[1]-(domain[1]-domain[0])*i/3,l=S('line',{{x1:box.l,x2:box.r,y1:yy,y2:yy,stroke:css('--grid'),opacity:'.65'}});svg.append(l);const t=S('text',{{x:box.l-8,y:yy+4,'text-anchor':'end',fill:css('--muted'),'font-size':'12'}});t.textContent=Math.round(val);svg.append(t);}}
  const yl=S('text',{{x:14,y:(box.t+box.b)/2,transform:`rotate(-90 14 ${{(box.t+box.b)/2}})`,fill:css('--muted'),'font-size':'12','text-anchor':'middle'}});yl.textContent=label;svg.append(yl);
}}
function timeAxis(svg,box){{
  const ticks=innerWidth<500?3:4;
  for(let i=0;i<=ticks;i++){{const xx=box.l+(box.r-box.l)*i/ticks,t=S('text',{{x:xx,y:box.b+22,'text-anchor':i===0?'start':i===ticks?'end':'middle',fill:css('--muted'),'font-size':'12'}});t.textContent=fmt(summary.elapsed*i/ticks);svg.append(t);}}
}}
function drawTimeline(){{
  const svg=document.getElementById('timeline'),w=Math.max(320,svg.clientWidth||900),h=w<500?390:440,m={{l:64,r:18,t:18,b:34}},motionBox={{l:m.l,r:w-m.r,t:m.t,b:w<500?235:270}},hrBox={{l:m.l,r:w-m.r,t:w<500?270:310,b:h-m.b}};svg.replaceChildren();svg.setAttribute('viewBox',`0 0 ${{w}} ${{h}}`);
  const motion=records.filter(d=>Number.isFinite(d.rms)||Number.isFinite(d.peak)), maxMotion=Math.max(1,...motion.flatMap(d=>[d.rms||0,d.peak||0]));
  const hrs=records.filter(d=>Number.isFinite(d.hr)),hrExt=hrs.length?extent(hrs,d=>d.hr):[50,120],x=scale(0,summary.elapsed,m.l,w-m.r),y=scale(0,maxMotion,motionBox.b,motionBox.t),yh=scale(Math.max(35,hrExt[0]-8),hrExt[1]+8,hrBox.b,hrBox.t);
  laps.forEach(d=>{{for(const [i,box] of [motionBox,hrBox].entries()){{const attrs={{x:x(d.start),y:box.t,width:Math.max(1,x(d.end)-x(d.start)),height:box.b-box.t,class:d.phase==='work'?'phase-work':'phase-rest'}};if(i===0)attrs.id=`lap-${{d.lap}}`;const r=S('rect',attrs);svg.append(r);}}}});
  yAxis(svg,motionBox,[0,maxMotion],'Acceleration (mg)');yAxis(svg,hrBox,[Math.max(35,hrExt[0]-8),hrExt[1]+8],'Heart rate (bpm)');timeAxis(svg,hrBox);
  const paths={{rms:S('path',{{d:linePath(records,x,y,d=>d.rms),class:'line-rms'}}),peak:S('path',{{d:linePath(records,x,y,d=>d.peak),class:'line-peak'}}),hr:S('path',{{d:linePath(records,x,yh,d=>d.hr),class:'line-hr'}})}};Object.values(paths).forEach(p=>svg.append(p));
  const hit=S('rect',{{x:m.l,y:m.t,width:w-m.l-m.r,height:h-m.t-m.b,fill:'transparent'}});svg.append(hit);hit.addEventListener('pointermove',e=>{{const box=svg.getBoundingClientRect(),px=(e.clientX-box.left)*w/box.width,t=(px-m.l)*(summary.elapsed)/(w-m.l-m.r);const d=records.reduce((a,b)=>Math.abs(b.t-t)<Math.abs(a.t-t)?b:a);tooltip.style.display='block';tooltip.style.left=`${{Math.min(innerWidth-190,e.clientX+12)}}px`;tooltip.style.top=`${{e.clientY+12}}px`;tooltip.innerHTML=`<b>${{fmt(d.t)}}</b><br>RMS ${{d.rms??'—'}} mg · peak ${{d.peak??'—'}} mg<br>HR ${{d.hr??'—'}} bpm`;}});hit.addEventListener('pointerleave',()=>tooltip.style.display='none');
  document.querySelectorAll('[data-series]').forEach(b=>b.onclick=()=>{{const k=b.dataset.series,on=b.getAttribute('aria-pressed')==='true';b.setAttribute('aria-pressed',String(!on));paths[k].style.display=on?'none':'';}});
}}
function drawSets(){{
  const svg=document.getElementById('sets'),w=Math.max(320,svg.clientWidth||900),h=w<500?280:320,m={{l:64,r:28,t:22,b:42}};svg.replaceChildren();svg.setAttribute('viewBox',`0 0 ${{w}} ${{h}}`);
  const scores=valid.map(d=>d.smoothness).filter(v=>Number.isFinite(v)&&v>=0),domain=scores.length?[Math.max(0,Math.min(...scores)-8),Math.min(100,Math.max(...scores)+8)]:[0,100],box={{l:m.l,r:w-m.r,t:m.t,b:h-m.b}},x=scale(.5,Math.max(1.5,work.length+.5),box.l,box.r),y=scale(domain[0],domain[1],box.b,box.t);
  yAxis(svg,box,domain,'Smoothness (0–100)');
  work.forEach(d=>{{const short=d.elapsed<10,bw=Math.max(8,(box.r-box.l)/Math.max(work.length,1)*.48),score=Number.isFinite(d.smoothness)&&d.smoothness>=0?d.smoothness:domain[0],bar=S('rect',{{id:`set-${{d.set}}`,x:x(d.set)-bw/2,y:short?box.b-5:y(Math.max(domain[0],score)),width:bw,height:short?5:Math.max(2,box.b-y(Math.max(domain[0],score))),class:short?'anomaly':'smooth-bar'}});svg.append(bar);const val=S('text',{{x:x(d.set),y:short?box.b-10:y(Math.max(domain[0],score))-5,'text-anchor':'middle',fill:short?css('--warn'):css('--ink'),'font-size':'12'}});val.textContent=short?`${{Math.round(d.elapsed)}}s`:score;svg.append(val);const label=S('text',{{x:x(d.set),y:h-17,'text-anchor':'middle',fill:css('--muted'),'font-size':'12'}});label.textContent=d.set;svg.append(label);bar.addEventListener('pointermove',e=>{{tooltip.style.display='block';tooltip.style.left=`${{Math.min(innerWidth-190,e.clientX+12)}}px`;tooltip.style.top=`${{e.clientY+12}}px`;tooltip.innerHTML=`<b>Set ${{d.set}}</b><br>${{fmt(d.elapsed)}} · smoothness ${{short?'excluded':d.smoothness??'—'}}<br>peak ${{d.motion_peak??'—'}} mg · ${{d.swings??'—'}} swings`;}});bar.addEventListener('pointerleave',()=>tooltip.style.display='none');}});
  const xl=S('text',{{x:(box.l+box.r)/2,y:h-2,'text-anchor':'middle',fill:css('--muted'),'font-size':'12'}});xl.textContent='Set';svg.append(xl);
}}
const first=valid.slice(0,3).map(d=>d.smoothness).filter(Number.isFinite),last=valid.slice(-3).map(d=>d.smoothness).filter(Number.isFinite),avg=a=>a.length?a.reduce((x,y)=>x+y,0)/a.length:null,delta=avg(last)-avg(first),anomalies=work.filter(d=>d.elapsed<10);
document.getElementById('insight').textContent=!first.length||!last.length?'Not enough comparable smoothness data for a session trend.':anomalies.length?`Set ${{anomalies.map(d=>d.set).join(', ')}} lasted under 10 seconds and is excluded from the smoothness comparison. Across comparable sets, the last three averaged ${{Math.abs(delta).toFixed(1)}} points ${{delta<0?'lower':'higher'}} than the first three.`:`Across comparable sets, the last three averaged ${{Math.abs(delta).toFixed(1)}} points ${{delta<0?'lower':'higher'}} than the first three.`;
let lastWidth=0;new ResizeObserver(entries=>{{const width=Math.round(entries[0].contentRect.width);if(width===lastWidth)return;lastWidth=width;drawTimeline();drawSets();}}).observe(document.querySelector('main'));
</script></body></html>"""


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="raw FIT activity or Garmin ZIP export")
    parser.add_argument("-o", "--output", type=Path, help="output HTML path")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    output = args.output or args.source.with_name(f"{args.source.stem}-report.html")
    with tempfile.TemporaryDirectory(prefix="mace-clubs-fit-") as temporary:
        source = fit_path(args.source, Path(temporary))
        report = collect(FitFile(str(source)))
    output.write_text(render(report, f"Mace & Clubs · {args.source.stem}"), encoding="utf-8")
    print(output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
