"""Shared visual system for the Jac client. No external fonts or assets."""
def:pub AppStyles -> JsxElement {
    return <style>{"""
:root { color-scheme: light; --ink:#25382e; --muted:#69766e; --green:#295943; --line:#e1e7df; --paper:#fffefb; --tint:#eef3eb; }
* { box-sizing:border-box; }
body { margin:0; background:#f4f5ef; color:var(--ink); font:14px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; }
button,input,select { font:inherit; }
button { border:1px solid #cdd8cc; background:var(--paper); color:var(--green); border-radius:9px; padding:9px 13px; cursor:pointer; font-weight:600; transition:background .15s; }
button:hover:not(:disabled) { background:#e9f0e5; }
button:disabled { opacity:.5; cursor:default; }
button.primary { background:var(--green); color:white; border-color:var(--green); }
button.primary:hover:not(:disabled) { background:#1c4432; }
:focus-visible { outline:3px solid #93ad6b; outline-offset:3px; }
input,select { width:100%; min-width:0; padding:10px 11px; background:white; color:var(--ink); border:1px solid #d5ddd3; border-radius:8px; }
input[type=checkbox] { width:auto; accent-color:var(--green); margin-right:8px; }
label { display:grid; gap:6px; font-size:12px; font-weight:600; color:#566459; }
a { color:var(--green); text-underline-offset:3px; }
p { margin:8px 0 14px; overflow-wrap:anywhere; }
h1,h2,h3,h4 { line-height:1.25; }
h2 { font-size:18px; margin:0; } h3 { font-size:17px; margin:22px 0 10px; } h4 { font-size:16px; margin:4px 0 12px; }
small { color:var(--muted); font-size:12px; }
.app-shell { max-width:1540px; margin:0 auto; padding:0 36px; }
.app-header { display:flex; justify-content:space-between; align-items:center; gap:20px; padding:23px 0; border-bottom:1px solid var(--line); }
.brand { display:flex; align-items:center; gap:12px; font-size:23px; font-weight:750; text-decoration:none; letter-spacing:-.6px; }
.brand-icon { display:grid; place-items:center; background:var(--green); color:#eff4dd; width:43px; height:43px; border-radius:14px; font-size:31px; font-weight:400; }
.brand small { display:block; font-size:9px; letter-spacing:1.7px; font-weight:600; margin-top:2px; }
.new-trip { display:grid; gap:5px; text-align:center; } .new-trip span { font-size:11px; color:var(--muted); }
.page-intro { display:flex; align-items:center; justify-content:space-between; gap:24px; padding:25px 0; }
.eyebrow { letter-spacing:1.8px; font-size:10px; font-weight:700; color:#718060; margin:0 0 8px; }
h1 { font:400 35px/1.2 Georgia,serif; letter-spacing:-1px; margin:0 0 8px; }
.page-intro p:not(.eyebrow) { color:var(--muted); margin-bottom:0; }
.reset-help { max-width:310px; font-size:12px; flex-shrink:0; }
.reset-help summary { background:transparent; padding:5px; border:0; }
.app-columns { display:grid; grid-template-columns:minmax(0,1.4fr) minmax(350px,1fr); align-items:start; gap:22px; }
.shopping-panel,.assistant-panel { border:1px solid var(--line); border-radius:18px; background:var(--paper); box-shadow:0 5px 22px #25382e04; min-width:0; overflow:hidden; }
.shopping-heading { display:flex; align-items:center; justify-content:space-between; padding:23px 24px 16px; }
.section-number { font-size:11px; letter-spacing:1px; color:#82917c; }
.mode-switch { display:flex; padding:4px; border:1px solid var(--line); background:#f4f6f0; border-radius:10px; gap:3px; }
.mode-switch button { border:0; padding:7px 12px; background:transparent; font-size:12px; }
.mode-switch button[aria-pressed=true] { background:var(--green); color:white; opacity:1; }
.source-note { margin:0 24px 17px; padding:11px 13px; background:#f7f3e5; color:#766038; border-radius:9px; font-size:12px; }
.source-note strong { display:block; margin-bottom:2px; font-size:12px; }
.workspace-tabs { display:flex; gap:20px; padding:0 24px; border-bottom:1px solid var(--line); }
.workspace-tabs button { border:0; border-radius:0; padding:12px 0; background:transparent; font-size:13px; color:var(--muted); border-bottom:2px solid transparent; }
.workspace-tabs button[aria-selected=true] { color:var(--green); border-bottom-color:var(--green); }
.workspace-content { padding:20px 24px 24px; min-height:400px; }
.list-intro { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:20px; }
.list-intro h3 { margin:0; } .list-intro p { font-size:12px; margin:5px 0 0; color:var(--muted); }
.count-pill { font-size:12px; background:var(--tint); padding:5px 10px; border-radius:20px; white-space:nowrap; }
.empty-list { border:1px dashed #cdd7c6; background:#f8faf4; border-radius:13px; text-align:center; padding:29px 16px; margin-bottom:18px; }
.empty-list h3 { margin:7px 0; } .empty-list p { color:var(--muted); font-size:13px; max-width:370px; margin:8px auto; }
.empty-symbol { font:32px Georgia,serif; color:#708658; }
.interest-row { display:flex; align-items:center; justify-content:space-between; gap:12px; border:1px solid var(--line); border-radius:11px; padding:14px; margin-bottom:9px; }
.interest-row .item-name { display:block; font-size:14px; font-weight:650; }
.interest-row .item-meta { font-size:11px; color:var(--muted); }
.row-actions { display:flex; flex-wrap:wrap; gap:6px; } .row-actions button { font-size:11px; padding:6px 9px; }
.quick-add { margin:20px 0; border:1px solid var(--line); border-radius:11px; background:#f9faf6; }
.quick-add form { padding:14px; display:grid; grid-template-columns:minmax(100px,2fr) minmax(70px,1fr); gap:12px; align-items:end; }
.quick-add button { justify-self:start; }
details { margin:12px 0; } summary { cursor:pointer; font-weight:600; padding:12px 0; color:#405743; font-size:13px; }
.quick-add summary { padding:13px 14px; } details[open]>summary { margin-bottom:8px; }
.secondary-tools { border-top:1px solid var(--line); margin-top:22px; padding-top:4px; }
.secondary-tools p { font-size:12px; color:var(--muted); }
.reminder-banner { display:flex; align-items:center; justify-content:space-between; gap:10px; margin:0 24px 12px; padding:10px 13px; background:#e9f2ea; color:#24502f; border-radius:9px; font-size:12px; }
.reminder-banner span { min-width:0; overflow-wrap:anywhere; }
.error-banner { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:14px; padding:10px 13px; background:#fbe9e7; color:#8a2b1d; border:1px solid #f1c4bc; border-radius:9px; font-size:13px; }
.error-banner button { background:none; border:none; color:inherit; font-size:18px; cursor:pointer; padding:0 4px; }
.budget-summary, .budget-breakdown, .budget-weeks { border:1px solid var(--line); border-radius:11px; padding:14px; margin-bottom:14px; }
.budget-summary h3, .budget-breakdown h3, .budget-weeks h3 { margin:0 0 4px; }
.budget-summary p { font-size:12px; color:var(--muted); margin:6px 0; }
.budget-figures { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; margin:10px 0; }
.budget-figures span { display:block; font-size:11px; color:var(--muted); }
.budget-figures strong { font-size:20px; }
.budget-figures .over strong, .budget-figures .over span { color:#a3321f; }
.budget-meter { height:8px; background:#ece8dc; border-radius:99px; overflow:hidden; }
.budget-meter span { display:block; height:100%; background:#3f7a4e; }
.budget-meter span.over { background:#c2452f; }
.budget-row { display:flex; justify-content:space-between; font-size:13px; padding:4px 0; border-bottom:1px solid var(--line); }
.week-bars { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; align-items:end; height:120px; margin-top:8px; }
.week-bar { display:flex; flex-direction:column; justify-content:flex-end; align-items:center; height:100%; font-size:11px; }
.week-bar .bar { width:60%; min-height:2px; background:#8fb59a; border-radius:4px 4px 0 0; }
.week-bar small { color:var(--muted); }
.budget-note { padding:8px 11px; background:#fdf3e1; color:#7a5414; border-radius:8px; font-size:12px; }
.ledger-row { display:flex; align-items:center; justify-content:space-between; gap:12px; border:1px solid var(--line); border-radius:11px; padding:12px 14px; margin-bottom:8px; }
.ledger-row.voided { opacity:.55; }
.ledger-row .item-meta { display:block; }
.ledger-row .row-actions input { width:90px; }
.background-reminders { border:1px solid var(--line); border-radius:11px; padding:12px 14px; margin-bottom:12px; }
.background-reminders label { display:flex; align-items:center; gap:8px; font-size:13px; }
.delivery-settings h4 { margin:0 0 4px; }
.delivery-settings label { flex-wrap:wrap; margin:8px 0; }
.delivery-settings label input:not([type=checkbox]) { flex:1 1 220px; min-width:0; }
.delivery-settings .check-row { flex-wrap:nowrap; }
.delivery-settings .row-actions { flex-wrap:wrap; }
.sync-status { display:flex; align-items:center; justify-content:space-between; gap:15px; border-top:1px solid var(--line); padding:12px 24px; background:#fafbf7; }
.sync-status p { margin:0; font-size:11px; color:var(--muted); } .sync-status button { font-size:11px; padding:6px 8px; flex-shrink:0; }
.workspace-panel label { margin:12px 0; } .profile-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:4px 16px; align-items:end; }
.delivery-quotes .profile-grid > p, .delivery-quotes .profile-grid > fieldset { grid-column:1 / -1; min-width:0; }
.delivery-quotes fieldset { border:1px solid var(--line); border-radius:8px; padding:12px; }
.profile-grid button { margin:12px 0; justify-self:start; }
.result-card,.pending-request { border:1px solid var(--line); padding:18px; border-radius:12px; margin:14px 0; background:white; }
.result-card .result-card { background:#f8faf5; border-color:#e8ede4; padding:13px; }
.plan-title { display:flex; justify-content:space-between; align-items:start; gap:10px; } .plan-title h4 { margin:4px 0 14px; }
.plan-metrics { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); background:#f0f4eb; border-radius:9px; padding:12px; gap:10px; margin:5px 0 15px; }
.plan-metrics small { display:block; font-size:10px; } .plan-metrics strong { display:block; font-size:17px; margin-top:3px; }
.transit-itinerary { border-top:1px solid var(--line); padding-top:16px; margin-top:16px; }
.transit-itinerary .source-note { margin:0 0 14px; }
.transit-legs { list-style:none; padding:0; margin:0; }
.transit-legs li { display:grid; grid-template-columns:44px minmax(0,1fr); gap:12px; padding:14px 0; border-bottom:1px solid var(--line); }
.transit-kind { font-size:9px; font-weight:700; color:var(--green); background:var(--tint); border-radius:6px; padding:5px; align-self:start; text-align:center; }
.transit-legs strong { font-size:13px; } .transit-legs p { margin:5px 0; font-size:12px; } .transit-legs small { font-size:10px; }
.result-card p { font-size:13px; } .workspace-panel button { margin:4px 6px 4px 0; }
.pending-request { background:#fcf7e9; } .pending-request pre { white-space:pre-wrap; overflow-wrap:anywhere; }
[role=alert] { color:#9c472c; background:#fff3e9; border-radius:7px; padding:9px 12px; }
.workspace-panel>section>p:last-child,#store-visit-plans>p:last-child { font-size:11px; color:var(--muted); }
.assistant-panel { display:flex; flex-direction:column; position:sticky; top:20px; height:calc(100dvh - 250px); min-height:520px; max-height:850px; }
.assistant-heading { display:flex; align-items:center; gap:11px; padding:23px 22px 16px; }
.assistant-heading h2 { font-size:17px; } .assistant-heading p { font-size:12px; color:var(--muted); margin:4px 0 0; }
.assistant-icon { display:grid; place-items:center; width:39px; height:39px; border-radius:12px; background:#eaf0e0; color:#5a7447; font-size:22px; }
.chat-tools { padding:0 22px 14px; display:flex; align-items:center; justify-content:space-between; gap:8px; border-bottom:1px solid var(--line); font-size:10px; color:var(--muted); }
button.text-button { background:transparent; border:0; padding:3px 0; font-size:10px; text-decoration:underline; text-underline-offset:3px; }
.chat-log { overflow-y:auto; flex:1; min-height:100px; padding:22px; display:flex; flex-direction:column; gap:15px; scroll-behavior:smooth; }
.chat-empty { margin:auto 0; text-align:center; padding:10px 2px; } .chat-empty h3 { font:23px Georgia,serif; margin:15px 0 10px; } .chat-empty p { color:var(--muted); font-size:13px; } .chat-empty button { font-size:12px; margin:8px 0 12px; } .chat-empty small { display:block; font-size:11px; }
.message { max-width:94%; border-radius:13px; padding:13px 15px; font-size:13px; white-space:pre-wrap; overflow-wrap:anywhere; }
.message-user { align-self:flex-end; background:var(--green); color:white; border-bottom-right-radius:3px; }
.message-assistant { align-self:flex-start; background:#f0f4eb; border-bottom-left-radius:3px; }
.message-role { display:block; font-size:9px; text-transform:uppercase; letter-spacing:1px; opacity:.7; margin-bottom:5px; }
.thinking { font-size:12px; color:var(--muted); } .inline-alert { margin:10px 20px; }
.composer-wrap { padding:15px 18px 12px; border-top:1px solid var(--line); } .chat-composer { display:flex; gap:7px; } .chat-composer input { font-size:13px; } .chat-composer button { flex-shrink:0; padding:10px 12px; font-size:12px; } .composer-wrap p { font-size:10px; color:var(--muted); text-align:center; margin:9px 0 0; }
.app-footer { display:flex; justify-content:space-between; gap:15px; padding:18px 0; color:#84907f; font-size:10px; }
@media(min-width:1100px) { .workspace-content { max-height:calc(100dvh - 440px); min-height:350px; overflow-y:auto; } }
@media(max-width:1000px) { .app-shell { padding:0 20px; } .app-columns { grid-template-columns:minmax(0,1.1fr) minmax(320px,1fr); gap:14px; } .shopping-heading { flex-wrap:wrap; gap:14px; } .reset-help { display:none; } .profile-grid { grid-template-columns:1fr; } }
@media(max-width:740px) { .app-shell { padding:0 14px; } .app-header { padding:17px 0; gap:8px; } .brand { font-size:19px; gap:8px; } .brand-icon { width:34px; height:34px; font-size:25px; border-radius:10px; } .brand small { font-size:7px; letter-spacing:.7px; } .new-trip button { font-size:11px; padding:9px; } .new-trip span { font-size:9px; } h1 { font-size:29px; } .page-intro { padding:23px 0; } .page-intro p { font-size:12px; } .app-columns { grid-template-columns:minmax(0,1fr); } .assistant-panel { position:static; height:560px; min-height:0; } .shopping-heading { padding:19px 18px 14px; } .source-note, .reminder-banner { margin:0 18px 12px; } .workspace-tabs { padding:0 18px; } .workspace-content { padding:18px; min-height:0; } .app-footer { flex-direction:column; gap:3px; } .interest-row { flex-wrap:wrap; } }
@media(prefers-reduced-motion:reduce) { * { scroll-behavior:auto!important; transition:none!important; } }
"""}</style>;
}
