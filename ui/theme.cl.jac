"""Shared visual system for the Jac client. System fonts only; no external assets."""
def:pub AppStyles -> JsxElement {
    return <style>{"""
:root { color-scheme: light; --ink:#17251d; --muted:#627068; --green:#1d5a3f; --green-2:#2f7a55; --green-deep:#123d2b; --line:#e1e7df; --paper:#ffffff; --bg:#eef2ed; --tint:#e1efe5; --tint-2:#f2f7f3;
  --glow:#7af0b4; --amber:#94580a; --amber-bg:#fff3dc; --red:#b0402a; --bus:#2a6fcf; --walk:#b3bdb5; --wait:#dde2db; --shop:#2f8a5a; --order:#e0a440; --hl:#fff0a3;
  --font:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',sans-serif; --mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.55 var(--font); }
button,input,select { font:inherit; }
button { border:1px solid #cfdcd2; background:var(--paper); color:var(--green); border-radius:9px; padding:8px 12px; cursor:pointer; font-weight:650; transition:background .15s, box-shadow .15s; }
button:hover:not(:disabled) { background:#e9f2ec; }
button:disabled { opacity:.5; cursor:default; }
button.primary { background:var(--ink); color:#fff; border-color:var(--ink); }
button.primary:hover:not(:disabled) { background:#2a3b31; }
button.go { background:var(--green); color:#fff; border-color:var(--green); }
button.go:hover:not(:disabled) { background:#174a34; }
button.ghost { border-color:transparent; background:transparent; color:var(--muted); }
button.cta { font-size:14px; font-weight:800; padding:11px 18px; border-radius:12px; }
@media(min-width:861px) { button.cta { white-space:nowrap; } }
:focus-visible { outline:3px solid #6fbf95; outline-offset:2px; }
input,select { width:100%; min-width:0; padding:9px 11px; background:white; color:var(--ink); border:1px solid #d5ddd3; border-radius:9px; }
input[type=checkbox] { width:auto; accent-color:var(--green); margin-right:8px; }
label { display:grid; gap:6px; font-size:12px; font-weight:600; color:#4f5f55; }
a { color:var(--green); text-underline-offset:3px; }
p { margin:8px 0 12px; overflow-wrap:anywhere; }
h1,h2,h3,h4 { line-height:1.25; }
h2 { font-size:18px; margin:0; } h3 { font-size:16px; margin:18px 0 10px; } h4 { font-size:15px; margin:4px 0 10px; }
small { color:var(--muted); font-size:12px; }
.num { font-variant-numeric:tabular-nums; }
.sr-only { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; }

/* shell */
.app-shell { max-width:1480px; margin:0 auto; padding:0 24px 20px; }
.topbar { display:flex; align-items:center; gap:10px; padding:14px 0; }
.brand { display:flex; align-items:center; gap:10px; font-size:19px; font-weight:800; letter-spacing:-.4px; color:var(--green-deep); text-decoration:none; margin-right:auto; }
.brand-icon { display:grid; place-items:center; background:var(--green); color:#eaf6e4; width:30px; height:30px; border-radius:10px; font-size:17px; }
.topbar button { font-size:13px; padding:7px 12px; }
.topbar .new-trip { background:var(--ink); color:#fff; border-color:var(--ink); }
.pane-switch { display:none; }
.app-columns { display:grid; grid-template-columns:minmax(0,1.55fr) minmax(340px,1fr); align-items:start; gap:16px; }
.shopping-panel,.assistant-panel { border:1px solid var(--line); border-radius:20px; background:var(--paper); min-width:0; overflow:hidden; }
/* conversation first: the workspace appears once there is something to show */
.app-columns.booting .shopping-panel { visibility:hidden; }
.app-columns.onboarding { grid-template-columns:minmax(0, 760px); justify-content:center; }
.app-columns.onboarding .shopping-panel { display:none; }
.app-columns:not(.onboarding):not(.booting) .shopping-panel { animation:slide-in .6s cubic-bezier(.2,.9,.2,1) both; }
@keyframes slide-in { from { transform:translateX(-24px); opacity:0; } }
.welcome { margin:auto; flex:1; display:flex; flex-direction:column; align-items:center; justify-content:center; text-align:center; gap:14px; padding:32px 28px; max-width:620px; align-self:center; }
.welcome-orb { width:64px; height:64px; }
.welcome h1 { margin:6px 0 0; font-size:34px; font-weight:800; letter-spacing:-.9px; line-height:1.1; animation:rise .6s cubic-bezier(.2,.9,.2,1) both; }
.welcome > p { margin:0; color:var(--muted); font-size:15px; max-width:480px; animation:rise .6s cubic-bezier(.2,.9,.2,1) both .08s; }
.welcome-composer { display:flex; gap:8px; width:100%; margin-top:8px; padding:6px; border:1.5px solid #cfdcd2; border-radius:18px; background:#fff; box-shadow:0 12px 30px -18px rgba(29,90,63,.5); animation:rise .6s cubic-bezier(.2,.9,.2,1) both .16s; }
.welcome-composer:focus-within { border-color:var(--green-2); }
.welcome-composer input { border:0; font-size:16px; padding:10px 12px; }
.welcome-composer input:focus-visible { outline:none; }
.welcome-composer button { border-radius:13px; padding:10px 18px; font-size:14px; flex-shrink:0; }
.examples { display:flex; flex-wrap:wrap; justify-content:center; gap:8px; animation:rise .6s cubic-bezier(.2,.9,.2,1) both .24s; }
.examples button { font-size:12.5px; font-weight:600; border-radius:999px; color:#3b4a41; padding:6px 12px; }
.welcome-links { display:flex; flex-wrap:wrap; justify-content:center; gap:6px 16px; font-size:12px; color:var(--muted); margin-top:6px; }
.welcome-links button.text-button { font-size:12.5px; color:var(--green); }
.next-steps { align-self:flex-start; display:flex; flex-wrap:wrap; align-items:center; gap:6px; margin:-2px 0 4px; animation:rise .4s ease-out both .15s; }
.next-steps span { font-size:11px; font-weight:700; letter-spacing:.6px; text-transform:uppercase; color:var(--muted); margin-right:2px; }
.next-steps button { font-size:12.5px; padding:6px 12px; border-radius:999px; }
.app-footer { display:flex; justify-content:space-between; gap:15px; padding:14px 2px 0; color:#84907f; font-size:11px; }

/* trip bar */
.trip-bar { position:relative; margin:8px; border-radius:15px; background:var(--green-deep); color:#eef7f0; padding:14px 16px 12px; overflow:hidden; isolation:isolate; }
.trip-bar::before, .trip-bar::after { content:""; position:absolute; z-index:-1; border-radius:50%; filter:blur(36px); }
.trip-bar::before { width:320px; height:220px; left:-70px; top:-120px; background:radial-gradient(circle, rgba(54,208,139,.55), transparent 65%); animation:aurora-a 18s ease-in-out infinite alternate; }
.trip-bar::after { width:360px; height:240px; right:-90px; bottom:-170px; background:radial-gradient(circle, rgba(185,239,106,.32), transparent 65%); animation:aurora-b 22s ease-in-out infinite alternate; }
@keyframes aurora-a { to { transform:translate(280px, 60px) scale(1.15); } }
@keyframes aurora-b { to { transform:translate(-300px, -30px) scale(1.08); } }
.trip-top { display:flex; align-items:flex-start; gap:12px; }
.trip-top h2 { font-size:22px; font-weight:800; letter-spacing:-.5px; margin:0; color:#fff; }
.trip-sub { color:#b9d9c6; font-size:13px; margin-top:3px; }
.trip-side { margin-left:auto; display:grid; gap:6px; justify-items:end; }
.trip-pill { font-size:11px; font-weight:800; letter-spacing:.5px; padding:3px 10px; border-radius:999px; background:rgba(255,255,255,.12); color:#dff3e6; border:1px solid rgba(255,255,255,.18); white-space:nowrap; }
.trip-pill.amber { background:#ffd38a; color:#4a2e00; border-color:#ffd38a; }
.trip-pill.go { background:var(--glow); color:#0d3322; border-color:var(--glow); }
.trip-stats { display:grid; grid-auto-flow:column; grid-auto-columns:minmax(0,1fr); gap:10px; margin-top:12px; }
.trip-stat { background:rgba(255,255,255,.07); border:1px solid rgba(255,255,255,.12); border-radius:12px; padding:7px 12px; min-width:0; }
.trip-stat small { display:block; font-size:11px; color:#a9cdb8; }
.trip-stat .value { font-size:24px; font-weight:800; letter-spacing:-.5px; line-height:1.15; display:flex; align-items:baseline; white-space:nowrap; font-variant-numeric:tabular-nums; }
.trip-stat .unit { font-size:13px; font-weight:600; color:#a9cdb8; margin-left:4px; }
.trip-stat.bad .value { color:#ffb59f; } .trip-stat.ok .value { color:var(--glow); }
.trip-prefs { display:flex; flex-wrap:wrap; align-items:center; gap:6px; margin-top:10px; font-size:12px; }
.trip-prefs span { color:#cfe6d8; border:1px solid rgba(255,255,255,.16); border-radius:999px; padding:2px 10px; }
.trip-prefs button { border:0; background:transparent; color:#fff; font-size:12px; font-weight:700; text-decoration:underline; text-underline-offset:3px; padding:2px 4px; }
.trip-prefs button:hover:not(:disabled) { background:transparent; color:var(--glow); }
.kinetic { font-size:28px; font-weight:800; letter-spacing:-.8px; line-height:1.1; margin:6px 0 4px; color:#fff; }
.kinetic span { display:inline-block; animation:word-up .8s cubic-bezier(.2,.9,.2,1) both; }
.kinetic em { font-style:normal; color:var(--glow); }
@keyframes word-up { from { transform:translateY(60%) rotate(4deg); opacity:0; filter:blur(4px); } }
.odo { display:inline-flex; }
.odo-col { display:inline-block; height:1.15em; overflow:hidden; vertical-align:bottom; }
.odo-col > span { display:flex; flex-direction:column; transition:transform .55s cubic-bezier(.2,.9,.2,1); }
.odo-col > span > i { font-style:normal; height:1.15em; line-height:1.15em; text-align:center; }

/* stage nav */
.stage-nav { position:relative; display:grid; grid-template-columns:repeat(4,1fr); margin:2px 14px 0; background:var(--tint-2); border-radius:12px; padding:4px; }
.stage-nav button { position:relative; z-index:1; border:0; background:transparent; color:var(--muted); font-size:13px; font-weight:700; padding:6px; display:flex; justify-content:center; gap:7px; align-items:center; border-radius:9px; }
.stage-nav button:hover:not(:disabled) { background:transparent; color:var(--ink); }
.stage-nav button em { font-style:normal; font-size:10.5px; width:18px; height:18px; border-radius:50%; display:grid; place-items:center; background:#dfe8e1; color:var(--muted); }
.stage-nav button.done { color:var(--green); } .stage-nav button.done em { background:var(--green); color:#fff; }
.stage-nav button[aria-selected=true] { color:var(--ink); } .stage-nav button[aria-selected=true] em { background:var(--ink); color:#fff; }
.stage-ind { position:absolute; z-index:0; top:4px; bottom:4px; width:calc((100% - 8px) / 4); border-radius:9px; background:#fff; box-shadow:0 2px 8px -2px rgba(0,0,0,.15); transition:left .55s cubic-bezier(.3,1.25,.4,1); }
.view-head { display:flex; align-items:center; justify-content:space-between; gap:10px; margin:2px 14px 0; padding:6px 4px; }
.view-head h2 { font-size:17px; }
.workspace-content { padding:14px 16px 16px; min-height:380px; }
.workspace-content > * { animation:rise .45s cubic-bezier(.2,.9,.2,1) both; }
@keyframes rise { from { transform:translateY(8px); opacity:0; } }
.sync-status { display:flex; align-items:center; justify-content:space-between; gap:15px; border-top:1px solid var(--line); padding:8px 16px; background:#fafbf8; }
.sync-status p { margin:0; font-size:11.5px; color:var(--muted); } .sync-status strong { color:var(--ink); font-weight:650; }
.sync-status button { font-size:11.5px; padding:5px 9px; flex-shrink:0; }

/* common blocks */
.stage-head { display:flex; justify-content:space-between; align-items:baseline; gap:12px; margin:2px 0 10px; }
.stage-head h3 { margin:0; font-size:15px; } .stage-head small { font-size:12px; }
.cta-row { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-top:14px; }
.cta-row > span { color:var(--muted); font-size:13px; } .cta-row b { color:var(--ink); }
.info-box { font-size:12.5px; color:var(--muted); background:var(--tint-2); border-radius:10px; padding:9px 12px; margin:10px 0; }
.info-box b { color:var(--ink); }
.ev { display:inline-block; font-size:11px; font-weight:700; color:#55665c; background:var(--tint-2); border:1px solid var(--line); border-radius:6px; padding:0 7px; white-space:nowrap; }
.ev.user { color:#7a5a12; background:#fbf4e3; border-color:#efe0b8; }
.label-chip { display:inline-block; font-size:11px; font-weight:700; padding:1px 8px; border-radius:99px; background:var(--tint); color:var(--green); margin-right:5px; }
.count-pill { font-size:12px; background:var(--tint); padding:4px 10px; border-radius:20px; white-space:nowrap; }
.hl { animation:flash-hl 2.2s ease-out both .2s; border-radius:5px; }
@keyframes flash-hl { 0%,35% { background:var(--hl); box-shadow:0 0 0 3px var(--hl); } 100% { box-shadow:0 0 0 0 transparent; } }
.trip-bar .hl { animation-name:flash-glow; }
@keyframes flash-glow { 0%,35% { background:rgba(122,240,180,.35); box-shadow:0 0 0 3px rgba(122,240,180,.6); } 100% { box-shadow:0 0 0 0 transparent; } }
.toast { position:fixed; right:24px; top:16px; z-index:30; width:min(340px, calc(100vw - 32px)); background:var(--ink); color:#fff; border-radius:14px; padding:10px 12px; display:grid; grid-template-columns:1fr auto; gap:4px 10px; align-items:center; box-shadow:0 18px 40px -12px rgba(0,0,0,.5); animation:rise .35s ease-out both; }
.toast small { color:#a9c7b6; display:block; font-size:11px; }
.toast span { font-size:13px; overflow-wrap:anywhere; }
.toast .toast-actions { display:flex; gap:6px; grid-column:1 / -1; }
.toast button { font-size:12px; padding:4px 10px; background:#2c4136; color:#fff; border-color:#3c5447; }
.toast button.ghost { background:transparent; border-color:transparent; color:#a9c7b6; }
.beam { position:fixed; z-index:40; left:0; top:0; width:12px; height:12px; border-radius:50%; background:var(--glow); box-shadow:0 0 14px 5px rgba(122,240,180,.65); pointer-events:none; }

/* list */
.list-intro { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:10px; }
.list-intro h3 { margin:0; } .list-intro p { font-size:12px; margin:4px 0 0; color:var(--muted); }
.empty-list { border:1.5px dashed #cdd7c6; background:#f8faf6; border-radius:14px; text-align:center; padding:24px 16px; margin-bottom:14px; }
.empty-list h3 { margin:6px 0; } .empty-list p { color:var(--muted); font-size:13px; max-width:380px; margin:6px auto; }
.empty-symbol { font-size:30px; color:var(--green-2); }
.interest-row { display:flex; align-items:center; justify-content:space-between; gap:12px; border-bottom:1px solid var(--line); padding:9px 4px; }
.interest-row .item-name { display:block; font-size:14px; font-weight:700; }
.interest-row .item-meta { font-size:11.5px; color:var(--muted); }
.row-actions { display:flex; flex-wrap:wrap; gap:6px; } .row-actions button { font-size:11.5px; padding:5px 9px; }
.quick-add { margin:14px 0; border:1.5px dashed #cfdcd2; border-radius:12px; background:#fbfcfa; }
.quick-add form { padding:4px 14px 14px; display:grid; grid-template-columns:minmax(100px,2fr) minmax(70px,1fr) minmax(110px,1.2fr); gap:10px; align-items:end; }
.quick-add button { justify-self:start; }
details { margin:10px 0; } summary { cursor:pointer; font-weight:650; padding:10px 0; color:#3f5547; font-size:13px; }
.quick-add summary { padding:10px 14px; color:var(--green); } details[open]>summary { margin-bottom:6px; }
.secondary-tools { border-top:1px solid var(--line); margin-top:16px; padding-top:2px; }
.secondary-tools p { font-size:12px; color:var(--muted); }
.interests { border:1px solid var(--line); border-radius:14px; padding:10px 12px; margin:12px 0; background:#fafcfa; }
.interests-empty { margin:12px 0; font-size:12.5px; color:var(--muted); }
.attribution { margin-top:18px; font-size:11px; color:var(--muted); }
.interests-head { display:flex; justify-content:space-between; gap:10px; font-size:12.5px; color:var(--muted); margin-bottom:8px; }
.interests-head b { color:var(--ink); }
.interests-head button { font-size:12px; padding:0; border:0; background:transparent; text-decoration:underline; text-underline-offset:3px; }
.interest-cards { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:8px; }
.interest-card { background:#fff; border:1px solid var(--line); border-radius:12px; padding:8px 10px; display:grid; grid-template-columns:32px minmax(0,1fr); gap:2px 9px; align-items:center; }
.interest-card .ic { grid-row:span 2; width:32px; height:32px; border-radius:10px; display:grid; place-items:center; font-weight:800; font-size:12px; }
.interest-card .ic.rep { background:#eaf1fc; color:#2a5fb0; } .interest-card .ic.watch { background:var(--amber-bg); color:var(--amber); } .interest-card .ic.disc { background:#f1e9fb; color:#6a3fa8; }
.interest-card b { font-size:13px; overflow-wrap:anywhere; } .interest-card small { font-size:11.5px; line-height:1.3; overflow-wrap:anywhere; }
.interest-card .row-actions { grid-column:1 / -1; margin-top:5px; }

/* options */
.plan-best { border:1.5px solid var(--green); border-radius:16px; padding:12px 14px; display:grid; gap:9px; background:#fbfefc; position:relative; isolation:isolate; }
.plan-best::before { content:""; position:absolute; inset:0; border-radius:inherit; z-index:-1; background:radial-gradient(260px circle at var(--mx, 50%) var(--my, 0%), rgba(58,168,119,.13), transparent 60%); opacity:0; transition:opacity .3s; }
.plan-best:hover::before { opacity:1; }
.plan-kicker { font-size:11px; font-weight:800; letter-spacing:.6px; text-transform:uppercase; color:var(--green); }
.plan-name { font-size:15.5px; font-weight:800; }
.plan-why { font-size:18px; font-weight:750; letter-spacing:-.3px; line-height:1.3; }
.plan-why b { color:var(--green); }
.metrics { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); border:1px solid var(--line); border-radius:11px; background:#fff; }
.metrics > div { padding:6px 11px; border-right:1px solid var(--line); min-width:0; }
.metrics > div:last-child { border-right:0; }
.metrics small { display:block; font-size:11px; }
.metrics strong { font-size:18px; font-weight:800; font-variant-numeric:tabular-nums; }
.metrics .ok strong { color:var(--green); } .metrics .bad strong, .metrics .bad small { color:var(--red); } .metrics .unknown strong { color:var(--muted); }
.breakdown { font-size:12px; color:var(--muted); display:flex; flex-wrap:wrap; gap:6px 14px; align-items:center; }
.breakdown b { color:var(--ink); }
.time-strip { display:flex; height:9px; border-radius:99px; overflow:hidden; gap:2px; }
.time-strip i { display:block; height:100%; transform-origin:left; animation:grow-x .9s cubic-bezier(.2,.9,.2,1) both; }
.time-strip .WALK, .time-strip .BIKE { background:var(--walk); } .time-strip .WAIT { background:var(--wait); } .time-strip .BUS { background:var(--bus); } .time-strip .CAR { background:#7d8ca0; } .time-strip .SHOP { background:var(--shop); } .time-strip .ORDER { background:var(--order); }
@keyframes grow-x { from { transform:scaleX(0); } }
.plan-alt { display:grid; grid-template-columns:minmax(0,1fr) auto auto auto auto; gap:14px; align-items:center; border:1px solid var(--line); border-radius:12px; padding:9px 12px; font-size:13px; margin-top:8px; }
.plan-alt b.v { font-size:15px; font-weight:800; font-variant-numeric:tabular-nums; }
.plan-alt button { font-size:12px; padding:5px 10px; }
.plan-fold { border-radius:12px; padding:2px 12px; font-size:13px; color:var(--muted); background:var(--tint-2); margin-top:8px; }
.plan-fold summary { color:var(--ink); font-weight:600; font-size:13px; }
.plan-fold ul { margin:0 0 8px; padding-left:18px; }
.budget-note { padding:8px 11px; background:#fdf3e1; color:#7a5414; border-radius:8px; font-size:12px; }
.result-card,.pending-request { border:1px solid var(--line); padding:16px; border-radius:12px; margin:12px 0; background:white; }
.result-card .result-card { background:#f8faf5; border-color:#e8ede4; padding:12px; }
.plan-title { display:flex; justify-content:space-between; align-items:start; gap:10px; } .plan-title h4 { margin:4px 0 12px; }
.plan-metrics { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); background:var(--tint-2); border-radius:9px; padding:12px; gap:10px; margin:5px 0 15px; }
.plan-metrics small { display:block; font-size:10px; } .plan-metrics strong { display:block; font-size:17px; margin-top:3px; }
.result-card p { font-size:13px; } .workspace-panel button { margin:4px 6px 4px 0; }
.pending-request { background:#fcf7e9; border-color:#f0dfb4; }
.pending-request dl { display:grid; grid-template-columns:max-content minmax(0,1fr); gap:4px 14px; font-size:13px; margin:8px 0 12px; }
.pending-request dt { color:var(--muted); } .pending-request dd { margin:0; font-weight:650; overflow-wrap:anywhere; }
.source-note { margin:0 0 12px; padding:10px 13px; background:#f7f3e5; color:#766038; border-radius:9px; font-size:12px; }
.source-note strong { display:block; margin-bottom:2px; font-size:12px; }

/* start address */
.address-picker { border:1px solid var(--line); border-radius:16px; padding:14px 16px; margin:0 0 14px; background:#fbfdfb; display:grid; gap:10px; }
.address-picker h3 { margin:0; }
.address-picker > p { margin:0; font-size:13px; color:var(--muted); }
.address-picker.saved { grid-template-columns:minmax(0,1fr) auto; align-items:center; padding:10px 14px; }
.address-picker.saved small { display:block; font-size:11px; }
.address-picker.saved b { font-size:14px; overflow-wrap:anywhere; }
.address-actions { display:flex; flex-wrap:wrap; gap:8px; }
.address-confirm { display:grid; gap:6px; }
.address-confirm > small { font-weight:700; color:var(--green); }
.address-option { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:10px; align-items:center; border:1.5px solid #cfe3d6; background:#fff; border-radius:12px; padding:9px 12px; animation:rise .35s ease-out both; }
.address-option b { display:block; font-size:13.5px; overflow-wrap:anywhere; } .address-option small { font-size:11.5px; }
.address-problem { font-size:13px; line-height:1.45; color:#7a3b12; background:#fff3e6; border:1px solid #f1d0b0; border-radius:10px; padding:10px 12px; }
.address-type { display:flex; gap:8px; }
.address-type button { flex-shrink:0; }
.inline-select { width:auto; display:inline-block; padding:3px 6px; font-size:13px; }
.search-note { font-size:11.5px; color:var(--muted); margin:6px 0 0; }

/* route */
.route-map { border:1px solid var(--line); border-radius:16px; padding:10px 12px 6px; background:#fafcfa; }
.route-map svg { width:100%; height:auto; display:block; overflow:visible; }
.route-seg { fill:none; stroke-linecap:round; stroke-dasharray:1 1; stroke-dashoffset:1; animation:draw .7s cubic-bezier(.4,0,.2,1) forwards; }
@keyframes draw { to { stroke-dashoffset:0; } }
.route-node { animation:rise .4s ease both; }
.route-legend { display:flex; flex-wrap:wrap; gap:12px; font-size:11.5px; color:var(--muted); margin-top:4px; }
.route-legend i { display:inline-block; width:9px; height:9px; border-radius:2px; margin-right:4px; vertical-align:-1px; }
.key-times { display:grid; grid-template-columns:repeat(auto-fit,minmax(110px,1fr)); gap:8px; margin:10px 0; }
.key-time { border:1px solid var(--line); border-radius:12px; padding:7px 10px; background:#fff; min-width:0; }
.key-time small { display:block; font-size:11px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.key-time b { font:700 16px var(--mono); }
.key-time s { font:500 11px var(--mono); color:var(--muted); margin-left:6px; }
.route-grid { display:grid; grid-template-columns:minmax(0,1fr) 240px; gap:12px; align-items:start; }
.side-box { border:1px solid var(--line); border-radius:14px; padding:10px 12px; display:grid; gap:7px; }
.side-box h4 { margin:0; font-size:11px; letter-spacing:.7px; text-transform:uppercase; color:var(--muted); }
.side-box p { margin:0; font-size:12px; color:var(--muted); }
.carry-big { display:flex; justify-content:space-between; align-items:baseline; } .carry-big b { font-size:22px; font-weight:800; font-variant-numeric:tabular-nums; }
.carry-bar { display:flex; height:24px; border-radius:7px; border:1.5px solid #c9d6cc; overflow:hidden; background:#f6f8f5; }
.carry-bar i { display:grid; place-items:center; font-style:normal; font-size:10px; font-weight:800; color:#fff; border-right:2px solid #fff; overflow:hidden; white-space:nowrap; animation:drop-in .6s cubic-bezier(.3,1.4,.5,1) both; }
@keyframes drop-in { from { transform:translateY(-26px); opacity:0; } }
.carry-bar.over { border-color:var(--red); }
.delivery-box { border:1px dashed #e3c586; background:#fffaf0; border-radius:12px; padding:8px 11px; font-size:12px; display:grid; gap:2px; }
.delivery-box b { font-size:12.5px; }
.transit-itinerary { border-top:1px solid var(--line); padding-top:14px; margin-top:14px; }
.transit-itinerary .source-note { margin:0 0 12px; }
.transit-legs { list-style:none; padding:0; margin:0; }
.transit-legs li { display:grid; grid-template-columns:44px minmax(0,1fr); gap:12px; padding:12px 0; border-bottom:1px solid var(--line); }
.transit-kind { font-size:9px; font-weight:700; color:var(--green); background:var(--tint); border-radius:6px; padding:5px; align-self:start; text-align:center; }
.transit-legs strong { font-size:13px; } .transit-legs p { margin:4px 0; font-size:12px; } .transit-legs small { font-size:10px; }

/* accept / review */
.checks { display:grid; gap:8px; margin:10px 0; }
.check-card { display:grid; grid-template-columns:auto minmax(0,1fr) auto; gap:10px; align-items:center; border:1px solid var(--line); border-radius:12px; padding:10px 12px; font-size:13px; font-weight:600; color:var(--ink); }
.check-card input { width:18px; height:18px; margin:0; }
.check-card small { display:block; font-weight:400; }
.time-chip { font:700 12px var(--mono); color:var(--amber); background:var(--amber-bg); border-radius:6px; padding:2px 7px; white-space:nowrap; }
.review-box { border:1.5px solid #f0cf8e; background:#fffaf0; border-radius:14px; padding:10px 14px; margin:10px 0; }
.review-box h4 { margin:2px 0 6px; }
.review-box ul { margin:0; padding-left:18px; font-size:13px; display:grid; gap:3px; }

/* in store */
.store-list { border:1px solid var(--line); border-radius:14px; padding:2px 12px; }
.store-item { display:grid; grid-template-columns:auto minmax(0,1fr) auto; gap:10px; align-items:center; padding:9px 0; border-bottom:1px solid var(--line); }
.store-item:last-child { border-bottom:0; }
.pick { width:26px; height:26px; border-radius:50%; border:2px solid #bfcbc2; background:#fff; padding:0; display:grid; place-items:center; color:#fff; font-size:13px; }
.pick[aria-pressed=true] { background:var(--green); border-color:var(--green); animation:pop-in .4s cubic-bezier(.3,1.6,.5,1); }
.pick:hover:not(:disabled) { background:#e9f2ec; } .pick[aria-pressed=true]:hover:not(:disabled) { background:var(--green); }
@keyframes pop-in { from { transform:scale(.6); } }
.store-item.picked b { text-decoration:line-through; text-decoration-color:#9fb5a7; }
.store-item small { display:block; }
.in-basket { font-size:12px; font-weight:700; color:var(--green); }
.record-table { border:1px solid var(--line); border-radius:14px; padding:2px 12px; }
.record-row { display:grid; grid-template-columns:minmax(0,1fr) 92px 100px auto; gap:10px; align-items:center; padding:8px 0; border-bottom:1px solid var(--line); font-size:13.5px; }
.record-row:last-child { border-bottom:0; }
.record-row.head { font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.6px; padding:7px 0 3px; }
.record-row input { padding:5px 8px; font-family:var(--mono); text-align:right; }
.record-row label { display:flex; align-items:center; gap:4px; font-size:12px; font-weight:600; }
.record-row.skip { opacity:.55; } .record-row input.est { color:var(--muted); font-style:italic; }
.record-total { display:flex; justify-content:space-between; padding:9px 0; font-weight:800; }
.done-card { border:1px solid var(--line); border-radius:16px; padding:14px 16px; background:var(--tint-2); display:grid; gap:4px; }
.done-card h3 { margin:0 0 4px; display:flex; gap:10px; align-items:center; }
.done-card h3 i { width:26px; height:26px; border-radius:50%; background:var(--green); color:#fff; display:grid; place-items:center; font-style:normal; font-size:14px; animation:pop-in .5s cubic-bezier(.3,1.6,.5,1); }
.done-card .todo { color:var(--amber); }

/* budget & settings */
.reminder-banner { display:flex; align-items:center; justify-content:space-between; gap:10px; padding:10px 13px; background:#e9f2ea; color:#24502f; border-radius:9px; font-size:12px; }
.error-banner { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:14px; padding:10px 13px; background:#fbe9e7; color:#8a2b1d; border:1px solid #f1c4bc; border-radius:9px; font-size:13px; }
.error-banner button { background:none; border:none; color:inherit; font-size:18px; cursor:pointer; padding:0 4px; }
.budget-summary, .budget-breakdown, .budget-weeks { border:1px solid var(--line); border-radius:12px; padding:14px; margin-bottom:14px; }
.budget-summary h3, .budget-breakdown h3, .budget-weeks h3 { margin:0 0 4px; }
.budget-summary p { font-size:12px; color:var(--muted); margin:6px 0; }
.budget-figures { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; margin:10px 0; }
.budget-figures span { display:block; font-size:11px; color:var(--muted); }
.budget-figures strong { font-size:20px; font-variant-numeric:tabular-nums; }
.budget-figures .over strong, .budget-figures .over span { color:#a3321f; }
.budget-meter { height:8px; background:#e6ebe4; border-radius:99px; overflow:hidden; }
.budget-meter span { display:block; height:100%; background:var(--green-2); transform-origin:left; animation:grow-x .9s cubic-bezier(.2,.9,.2,1) both; }
.budget-meter span.over { background:#c2452f; }
.budget-row { display:flex; justify-content:space-between; font-size:13px; padding:4px 0; border-bottom:1px solid var(--line); }
.week-bars { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; align-items:end; height:120px; margin-top:8px; }
.week-bar { display:flex; flex-direction:column; justify-content:flex-end; align-items:center; height:100%; font-size:11px; }
.week-bar .bar { width:60%; min-height:2px; background:#9ccbad; border-radius:5px 5px 2px 2px; transform-origin:bottom; animation:grow-y .9s cubic-bezier(.2,.9,.2,1) both; }
@keyframes grow-y { from { transform:scaleY(0); } }
.week-bar small { color:var(--muted); }
.ledger-row { display:flex; align-items:center; justify-content:space-between; gap:12px; border:1px solid var(--line); border-radius:11px; padding:12px 14px; margin-bottom:8px; }
.ledger-row.voided { opacity:.55; }
.ledger-row .item-meta { display:block; }
.ledger-row .row-actions input { width:90px; }
.ledger-row .item-name { font-weight:700; display:block; }
.background-reminders { border:1px solid var(--line); border-radius:12px; padding:12px 14px; margin-bottom:12px; }
.background-reminders label { display:flex; align-items:center; gap:8px; font-size:13px; }
.delivery-settings h4 { margin:0 0 4px; }
.delivery-settings label { flex-wrap:wrap; margin:8px 0; }
.delivery-settings label input:not([type=checkbox]) { flex:1 1 220px; min-width:0; }
.delivery-settings .check-row { flex-wrap:nowrap; }
.delivery-settings .row-actions { flex-wrap:wrap; }
.workspace-panel label { margin:10px 0; } .profile-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:4px 16px; align-items:end; }
.profile-grid .wide { grid-column:1 / -1; }
.delivery-quotes .profile-grid > p, .delivery-quotes .profile-grid > fieldset { grid-column:1 / -1; min-width:0; }
.delivery-quotes fieldset { border:1px solid var(--line); border-radius:8px; padding:12px; }
.profile-grid button { margin:12px 0; justify-self:start; }
.chip-group { display:flex; flex-wrap:wrap; gap:6px; }
.chip-group button { font-size:12.5px; padding:5px 12px; border-radius:999px; }
.chip-group button[aria-pressed=true] { background:var(--green); color:#fff; border-color:var(--green); }
.slot-row { display:grid; grid-template-columns:minmax(80px,1fr) minmax(90px,1fr) minmax(90px,1fr) auto; gap:8px; align-items:center; margin-bottom:6px; }
.slot-row button { margin:0; }
[role=alert] { color:#9c472c; background:#fff3e9; border-radius:7px; padding:9px 12px; }
.workspace-panel>section>p:last-child,#store-visit-plans>p:last-child { font-size:11px; color:var(--muted); }

/* assistant */
.assistant-panel { display:flex; flex-direction:column; position:sticky; top:12px; height:calc(100dvh - 90px); min-height:520px; max-height:900px; }
.assistant-heading { display:flex; align-items:center; gap:11px; padding:14px 16px; border-bottom:1px solid var(--line); }
.assistant-heading h2 { font-size:15px; } .assistant-heading p { font-size:12px; color:var(--muted); margin:2px 0 0; }
.orb { width:32px; height:32px; flex:0 0 auto; border-radius:42% 58% 55% 45% / 50% 40% 60% 50%; background:conic-gradient(from 0deg, #3aa877, #b9ef6a, #2a8f9a, #3aa877); animation:morph 8s ease-in-out infinite, spin 14s linear infinite; box-shadow:0 0 16px -3px rgba(58,168,119,.6); }
.orb.busy { animation:morph 1.6s ease-in-out infinite, spin 3s linear infinite; }
@keyframes morph { 50% { border-radius:58% 42% 45% 55% / 40% 60% 40% 60%; } }
@keyframes spin { to { transform:rotate(360deg); } }
.assistant-heading button.text-button { margin-left:auto; }
button.text-button { background:transparent; border:0; padding:3px 0; font-size:11px; color:var(--muted); text-decoration:underline; text-underline-offset:3px; }
.chat-log { overflow-y:auto; flex:1; min-height:100px; padding:16px; display:flex; flex-direction:column; gap:10px; scroll-behavior:smooth; }
/* Scroll the log instead of squashing cards; .change-card hides overflow, so it would shrink to nothing. */
.chat-log > * { flex-shrink:0; }
.chat-empty { margin:auto 0; text-align:center; padding:10px 2px; } .chat-empty h3 { font-size:21px; font-weight:800; margin:12px 0 8px; letter-spacing:-.4px; } .chat-empty p { color:var(--muted); font-size:13px; } .chat-empty button { font-size:12px; margin:8px 0 12px; } .chat-empty small { display:block; font-size:11px; }
.message { max-width:92%; border-radius:16px; padding:10px 13px; font-size:13.5px; white-space:pre-wrap; overflow-wrap:anywhere; animation:rise .35s cubic-bezier(.2,.9,.2,1) both; }
.message-user { align-self:flex-end; background:var(--green); color:white; border-bottom-right-radius:5px; }
.message-assistant { align-self:flex-start; background:var(--tint-2); border:1px solid var(--line); border-bottom-left-radius:5px; }
.message-role { display:block; font-size:9.5px; text-transform:uppercase; letter-spacing:1px; opacity:.7; margin-bottom:4px; }
.change-card { align-self:stretch; border:1px solid #cfe3d6; background:linear-gradient(180deg,#fff,#f6fbf8); border-radius:14px; padding:9px 12px; font-size:12.5px; display:grid; gap:4px; position:relative; overflow:hidden; animation:rise .35s ease-out both; }
.change-card::before { content:""; position:absolute; left:0; top:0; height:2px; width:100%; background:linear-gradient(90deg, transparent, var(--glow), transparent); animation:sweep 1.6s ease-out 1 both; }
@keyframes sweep { from { transform:translateX(-100%); } to { transform:translateX(100%); } }
.change-card h4 { margin:0; font-size:10.5px; letter-spacing:.8px; text-transform:uppercase; color:var(--green); }
.change-card div { display:flex; justify-content:space-between; gap:10px; }
.change-card div span:last-child { font-variant-numeric:tabular-nums; font-weight:700; text-align:right; }
.thinking { font-size:12.5px; color:var(--muted); display:flex; gap:8px; align-items:center; } .thinking .orb { width:20px; height:20px; } .inline-alert { margin:10px 16px; }
.composer-wrap { padding:10px 14px 12px; border-top:1px solid var(--line); display:grid; gap:8px; }
.suggestions { display:flex; gap:6px; flex-wrap:wrap; }
.suggestions button { font-size:12px; font-weight:600; padding:3px 10px; border-radius:999px; color:#3b4a41; }
.chat-composer { display:flex; gap:7px; } .chat-composer input { font-size:13.5px; border-radius:12px; } .chat-composer button { flex-shrink:0; padding:9px 13px; font-size:12.5px; border-radius:12px; }
.composer-wrap p { font-size:10.5px; color:var(--muted); text-align:center; margin:0; }

@media(min-width:1101px) { .workspace-content { max-height:calc(100dvh - 330px); overflow-y:auto; } }
@media(max-width:1100px) { .app-columns { grid-template-columns:minmax(0,1.2fr) minmax(320px,1fr); gap:12px; } .profile-grid { grid-template-columns:1fr; } .interest-cards { grid-template-columns:1fr; } .route-grid { grid-template-columns:1fr; } }
@media(max-width:860px) {
  .app-shell { padding:0 12px 12px; }
  .topbar { flex-wrap:wrap; gap:8px; padding:10px 0; }
  .topbar .brand { font-size:17px; }
  .pane-switch { display:grid; grid-template-columns:1fr 1fr; width:100%; background:#fff; border:1px solid var(--line); border-radius:12px; padding:3px; order:5; }
  .pane-switch button { border:0; padding:7px; border-radius:9px; color:var(--muted); font-size:13px; display:flex; justify-content:center; gap:6px; align-items:center; }
  .pane-switch button[aria-pressed=true] { background:var(--ink); color:#fff; }
  .pane-switch em { font-style:normal; background:var(--glow); color:#0d3322; font-size:10.5px; border-radius:99px; padding:0 6px; }
  .app-columns { grid-template-columns:minmax(0,1fr); }
  .app-columns.pane-plan .assistant-panel, .app-columns.pane-assistant .shopping-panel { display:none; }
  .app-columns.onboarding .assistant-panel { display:flex; }
  .welcome h1 { font-size:27px; } .welcome { padding:24px 16px; }
  .assistant-panel { position:static; height:calc(100dvh - 130px); min-height:420px; }
  .trip-top { flex-wrap:wrap; } .trip-side { margin-left:0; justify-items:start; grid-auto-flow:column; align-items:center; }
  .trip-stat .value { font-size:19px; } .trip-stat { padding:6px 8px; }
  .stage-nav { margin:2px 8px 0; } .stage-nav button { font-size:12px; gap:4px; padding:6px 2px; }
  .workspace-content { padding:12px; min-height:0; }
  .quick-add form { grid-template-columns:1fr 1fr; }
  .plan-alt { grid-template-columns:minmax(0,1fr) auto; } .plan-alt .hide-narrow { display:none; }
  .record-row { grid-template-columns:minmax(0,1fr) 70px 84px; } .record-row .skip-toggle { grid-column:1 / -1; } .record-row.head span:last-child { display:none; }
  .interest-row { flex-wrap:wrap; }
  .app-footer { flex-direction:column; gap:3px; }
  .toast { right:12px; left:12px; width:auto; }
}
@media(prefers-reduced-motion:reduce) {
  *, *::before, *::after { scroll-behavior:auto!important; transition:none!important; animation:none!important; }
  .route-seg { stroke-dashoffset:0; }
}
"""}</style>;
}
