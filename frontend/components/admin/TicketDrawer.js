"use client";

/**
 * TicketDrawer
 * ------------
 * Right-side detail drawer (70% of the screen) that replaces the old inline
 * expand. Two panes:
 *   • LEFT  — media: photo preview, audio player (if any), location mini-map.
 *   • RIGHT — everything else: citizen personal details, ward/zone/constituency,
 *             urgency, upvotes, AI transcript/highlights, department routing, and
 *             the status action buttons (verify → forward → start → resolve).
 * Reuses every backend action from the current project.
 */

import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import {
  X, Phone, User, MapPin, Building2, ThumbsUp, Sparkles, ImageIcon, Volume2,
  ShieldCheck, Send, PlayCircle, CheckCircle2, Clock, Landmark, Hash, Flag,
  Route, CornerDownRight, UserCheck, AlertCircle,
} from "lucide-react";
import { mediaUrl, adminVerifyGrievance, adminForwardIssue, adminStartIssue, adminCloseIssue } from "@/lib/api";
import { departmentMeta } from "@/lib/departments";
import { loadDeptTree, resolveRouting, contactForRouting } from "@/lib/deptRouting";
import {
  portalStatus, derivePriority, PRIORITY_META, ticketNo, tokenNo,
  daysOpen, slaWeeksLabel, slaBreached, citizenName,
} from "@/lib/adminModel";
import { constituenciesForWard, shortAC } from "@/lib/constituencies";
import WhatsAppModal from "@/components/WhatsAppModal";

const MiniMap = dynamic(() => import("@/components/MiniMap"), { ssr: false });

const LIFECYCLE = [
  { key: "SUBMITTED", label: "Submitted" },
  { key: "ACTIVE", label: "Verified" },
  { key: "FORWARDED", label: "Forwarded" },
  { key: "IN_PROGRESS", label: "In Progress" },
  { key: "PENDING_VERIFICATION", label: "Resolved" },
  { key: "CLOSED", label: "Closed" },
];
const STAGE_INDEX = { SUBMITTED: 0, ACTIVE: 1, FORWARDED: 2, IN_PROGRESS: 3, PENDING_VERIFICATION: 4, CLOSED: 5 };

export default function TicketDrawer({ issue, onClose, onChanged }) {
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const [wa, setWa] = useState(false);
  const [routing, setRouting] = useState(null);
  const [contact, setContact] = useState(null);

  // Resolve the AI routing chain (Gov Dept → … → Responsible Officer) + look up
  // the officer's configured contact whenever the ticket changes; re-check the
  // contact if the departmental config is edited elsewhere.
  useEffect(() => {
    if (!issue) return undefined;
    let alive = true;
    let current = null;
    loadDeptTree().then((tree) => {
      if (!alive) return;
      current = resolveRouting(issue, tree);
      setRouting(current);
      setContact(contactForRouting(current));
    });
    const sync = () => setContact(contactForRouting(current));
    window.addEventListener("nk:dept-contacts-changed", sync);
    return () => { alive = false; window.removeEventListener("nk:dept-contacts-changed", sync); };
  }, [issue]);

  if (!issue) return null;

  const st = portalStatus(issue.status);
  const priority = derivePriority(issue);
  const pm = PRIORITY_META[priority];
  const dept = departmentMeta(issue.department);
  const name = citizenName(issue);
  const acs = constituenciesForWard(issue.ward_no);
  const stage = STAGE_INDEX[issue.status] ?? 1;

  async function run(key, fn) {
    setBusy(key); setError(null);
    try { const updated = await fn(issue.id); onChanged?.(updated); }
    catch (err) { setError(err.message); }
    finally { setBusy(null); }
  }

  const canForward = issue.status === "ACTIVE" || issue.status === "IN_PROGRESS";
  const canDispatch = issue.department && ["ACTIVE", "FORWARDED", "IN_PROGRESS"].includes(issue.status);

  return (
    <div className="fixed inset-0 z-[80] flex">
      <div className="animate-scrim-in flex-1 bg-slate-900/40 backdrop-blur-[3px]" onClick={onClose} />
      <div className="glass-panel-strong animate-drawer-in flex h-full w-[70%] min-w-0 flex-col">
        {/* Drawer header */}
        <div className="flex items-center justify-between border-b border-white/50 px-6 py-3.5">
          <div className="flex items-center gap-3">
            <span className="w-1 self-stretch rounded-full" style={{ background: pm.dot }} />
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-extrabold text-brand">{ticketNo(issue)}</h2>
                <span className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold ${st.badge}`}>{st.label}</span>
                <span className={`rounded-md px-2 py-0.5 text-[11px] font-bold ${pm.badge}`}>{priority}</span>
              </div>
              <p className="flex items-center gap-1 text-[11px] text-slate-400"><Hash size={10} /> {tokenNo(issue)}</p>
            </div>
          </div>
          <button onClick={onClose} className="rounded-full p-2 text-slate-400 hover:bg-slate-100"><X size={20} /></button>
        </div>

        {/* Two panes */}
        <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] divide-x divide-white/40">
          {/* ── LEFT: media ── */}
          <div className="min-h-0 overflow-y-auto bg-white/25 p-5 space-y-4">
            <Section icon={ImageIcon} title="Photo submission">
              {issue.image_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={mediaUrl(issue.image_url)} alt="grievance" className="w-full rounded-xl object-cover ring-1 ring-slate-200" style={{ maxHeight: 340 }} />
              ) : (
                <Empty>No photo submitted</Empty>
              )}
            </Section>

            <Section icon={Volume2} title="Audio submission">
              {issue.audio_url ? (
                <div className="rounded-xl bg-white p-3 ring-1 ring-slate-200">
                  {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
                  <audio controls src={mediaUrl(issue.audio_url)} className="w-full" />
                </div>
              ) : (
                <Empty>No audio submitted</Empty>
              )}
            </Section>

            <Section icon={MapPin} title="Location">
              {issue.latitude != null && issue.longitude != null ? (
                <div className="h-52 overflow-hidden rounded-xl ring-1 ring-slate-200">
                  <MiniMap lat={issue.latitude} lng={issue.longitude} />
                </div>
              ) : <Empty>No coordinates</Empty>}
              {issue.area_name && <p className="mt-2 flex items-center gap-1 text-xs text-slate-500"><MapPin size={11} /> {issue.area_name}</p>}
            </Section>
          </div>

          {/* ── RIGHT: details + actions ── */}
          <div className="min-h-0 overflow-y-auto p-5 space-y-5">
            {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{error}</p>}

            {/* Citizen */}
            <div className="rounded-2xl border border-slate-200 p-4">
              <p className="mb-2 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-400"><User size={12} /> Citizen details</p>
              <p className="text-lg font-extrabold text-slate-900">{name}</p>
              <div className="mt-2 flex flex-wrap gap-4 text-sm">
                <span className="flex items-center gap-1.5 text-slate-600"><Phone size={13} className="text-slate-400" /> {issue.phone ? `+91 ${issue.phone}` : "—"}</span>
                <span className="flex items-center gap-1.5 text-slate-600"><ThumbsUp size={13} className="text-slate-400" /> {issue.upvotes} upvotes</span>
                <span className="flex items-center gap-1.5 text-slate-600"><Clock size={13} className="text-slate-400" /> Open {daysOpen(issue)}d · {slaWeeksLabel(issue)}</span>
              </div>
            </div>

            {/* Location / jurisdiction */}
            <div className="grid grid-cols-2 gap-3">
              <Info label="Ward" value={issue.ward_no != null ? `Ward ${issue.ward_no}` : "—"} icon={MapPin} />
              <Info label="Zone" value={issue.zone ? `Zone ${issue.zone}${issue.zone_name ? ` · ${issue.zone_name}` : ""}` : "—"} icon={Building2} />
              <Info label="Constituency" value={acs.length ? acs.map(shortAC).join(", ") : "—"} icon={Landmark} span />
              <Info label="Urgency" value={priority} icon={Flag} badge={pm.badge} />
              <Info label="SLA" value={slaBreached(issue) ? "Breached" : "On track"} icon={Clock} tone={slaBreached(issue) ? "text-red-600" : "text-emerald-600"} />
            </div>

            {/* Summary / AI */}
            <div>
              <p className="mb-1 text-[11px] font-bold uppercase tracking-wide text-slate-400">Headline</p>
              <p className="font-bold text-slate-800">{issue.title || <span className="italic text-slate-400">No headline</span>}</p>
              {(issue.transcript || issue.summary_highlights?.length > 0) && (
                <div className="mt-2 rounded-xl border border-brand/15 bg-brand-50/50 p-3">
                  <p className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-brand"><Sparkles size={12} /> AI Summary</p>
                  {issue.transcript && <p className="text-sm italic leading-snug text-slate-700">“{issue.transcript}”</p>}
                  {issue.summary_highlights?.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {issue.summary_highlights.map((h, i) => (
                        <span key={i} className="rounded-full bg-white/80 px-2.5 py-0.5 text-[11px] font-medium text-brand ring-1 ring-brand-200">{h}</span>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Department routing — AI-resolved chain to the responsible officer */}
            <div className="rounded-2xl border border-slate-200 p-4">
              <div className="mb-3 flex items-center justify-between">
                <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-400"><Route size={12} /> AI Routing → Responsible Officer</p>
                <span className="rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-bold text-brand ring-1 ring-brand-100">{dept.short} · {dept.slaDays}d SLA</span>
              </div>

              {routing ? (
                <>
                  <div className="space-y-0">
                    <RouteStep label="Government Department" value={routing.govDept} first />
                    <RouteStep label="Grievance Type" value={routing.type} />
                    <RouteStep label="Grievance SubType" value={routing.subtype} />
                    <RouteStep label="Sub Department" value={routing.subDept} />
                    <RouteStep label="Responsible Officer" value={routing.officer} officer />
                  </div>

                  {/* Resolved officer contact (from Departmental Configuration) */}
                  <div className={`mt-3 rounded-xl p-3 ring-1 ${contact ? "bg-emerald-50 ring-emerald-200" : "bg-amber-50 ring-amber-200"}`}>
                    {contact ? (
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-2">
                          <UserCheck size={16} className="shrink-0 text-emerald-600" />
                          <div>
                            <p className="text-sm font-bold text-slate-800">{contact.name}</p>
                            <p className="flex items-center gap-1 text-xs text-slate-600"><Phone size={11} /> +91 {contact.mobile}</p>
                          </div>
                        </div>
                        <span className="rounded-md bg-emerald-100 px-2 py-0.5 text-[10px] font-bold text-emerald-700">Contact on file</span>
                      </div>
                    ) : (
                      <p className="flex items-center gap-1.5 text-xs font-medium text-amber-800">
                        <AlertCircle size={14} className="shrink-0" /> No contact configured for this officer — add it in <b>Departments</b>.
                      </p>
                    )}
                  </div>
                </>
              ) : (
                <p className="text-sm text-slate-400">Resolving routing…</p>
              )}

              {canDispatch && (
                <button onClick={() => setWa(true)} className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-lg bg-[#25D366] px-3 py-2.5 text-xs font-bold text-white hover:brightness-95">
                  <Send size={13} /> WhatsApp dispatch to officer
                </button>
              )}
            </div>

            {/* Lifecycle */}
            <div>
              <p className="mb-2 text-[11px] font-bold uppercase tracking-wide text-slate-400">Lifecycle</p>
              <div className="flex items-center">
                {LIFECYCLE.map((s, i) => (
                  <div key={s.key} className="flex flex-1 flex-col items-center">
                    <div className="flex w-full items-center">
                      {i > 0 && <div className={`h-0.5 flex-1 ${i <= stage ? "bg-brand" : "bg-slate-200"}`} />}
                      <div className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[9px] font-bold ${
                        i < stage ? "bg-brand text-white" : i === stage ? "bg-brand text-amber-300 ring-4 ring-brand-100" : "bg-slate-200 text-slate-400"
                      }`}>{i < stage ? "✓" : ""}</div>
                      {i < LIFECYCLE.length - 1 && <div className={`h-0.5 flex-1 ${i < stage ? "bg-brand" : "bg-slate-200"}`} />}
                    </div>
                    <span className={`mt-1 text-center text-[9px] leading-tight ${i === stage ? "font-bold text-brand" : "text-slate-400"}`}>{s.label}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Actions */}
            <div className="flex flex-wrap gap-2 border-t border-slate-100 pt-4">
              {issue.status === "SUBMITTED" && (
                <ActionBtn onClick={() => run("verify", adminVerifyGrievance)} busy={busy === "verify"} primary icon={ShieldCheck}>Verify Grievance</ActionBtn>
              )}
              {canForward && (
                <ActionBtn onClick={() => run("forward", adminForwardIssue)} busy={busy === "forward"} icon={Send}>Forward to Department</ActionBtn>
              )}
              {(issue.status === "ACTIVE" || issue.status === "FORWARDED") && (
                <ActionBtn onClick={() => run("start", adminStartIssue)} busy={busy === "start"} icon={PlayCircle}>Accept &amp; Start</ActionBtn>
              )}
              {["ACTIVE", "FORWARDED", "IN_PROGRESS"].includes(issue.status) && (
                <ActionBtn onClick={() => run("close", adminCloseIssue)} busy={busy === "close"} success icon={CheckCircle2}>Mark Resolved</ActionBtn>
              )}
              {issue.status === "PENDING_VERIFICATION" && (
                <p className="flex items-center gap-1.5 text-sm font-medium text-amber-700"><Clock size={15} /> Awaiting citizen verification…</p>
              )}
              {issue.status === "CLOSED" && (
                <p className="flex items-center gap-1.5 text-sm font-medium text-emerald-700"><CheckCircle2 size={15} /> Resolved &amp; verified.</p>
              )}
            </div>
          </div>
        </div>
      </div>

      {wa && <WhatsAppModal issue={issue} onClose={() => setWa(false)} />}
    </div>
  );
}

function RouteStep({ label, value, officer }) {
  return (
    <div className="flex gap-3">
      <div className="flex flex-col items-center pt-0.5">
        <span className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full ${officer ? "bg-brand text-white" : "bg-slate-200 text-slate-500"}`}>
          {officer ? <UserCheck size={11} /> : <CornerDownRight size={11} />}
        </span>
        {!officer && <span className="my-0.5 w-px flex-1 bg-slate-200" />}
      </div>
      <div className="min-w-0 pb-3">
        <p className="text-[10px] font-bold uppercase tracking-wide text-slate-400">{label}</p>
        <p className={`text-sm font-semibold leading-snug ${officer ? "text-brand" : "text-slate-800"}`}>{value}</p>
      </div>
    </div>
  );
}

function Section({ icon: Icon, title, children }) {
  return (
    <div>
      <p className="mb-2 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-400"><Icon size={12} /> {title}</p>
      {children}
    </div>
  );
}

function Empty({ children }) {
  return <div className="flex h-24 items-center justify-center rounded-xl border border-dashed border-slate-200 bg-white text-xs text-slate-400">{children}</div>;
}

function Info({ label, value, icon: Icon, span, badge, tone }) {
  return (
    <div className={`rounded-xl border border-slate-200 p-3 ${span ? "col-span-2" : ""}`}>
      <p className="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wide text-slate-400"><Icon size={11} /> {label}</p>
      {badge
        ? <span className={`mt-1 inline-flex rounded-md px-2 py-0.5 text-[11px] font-bold ${badge}`}>{value}</span>
        : <p className={`mt-0.5 text-sm font-semibold ${tone || "text-slate-800"}`}>{value}</p>}
    </div>
  );
}

function ActionBtn({ onClick, busy, primary, success, icon: Icon, children }) {
  const cls = primary
    ? "bg-violet-600 text-white hover:bg-violet-700"
    : success
    ? "bg-emerald-600 text-white hover:bg-emerald-700"
    : "border border-slate-300 bg-white text-slate-700 hover:bg-slate-50";
  return (
    <button onClick={onClick} disabled={busy} className={`flex items-center gap-1.5 rounded-xl px-4 py-2.5 text-sm font-bold transition disabled:opacity-60 ${cls}`}>
      <Icon size={15} /> {busy ? "Working…" : children}
    </button>
  );
}
