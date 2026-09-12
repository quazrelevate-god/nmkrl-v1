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
  ShieldCheck, Send, CheckCircle2, Clock, Landmark, Hash, Flag, FileText, Mic, Square, Camera,
  ChevronDown, ExternalLink, Loader2,
  Route, CornerDownRight, UserCheck, AlertCircle,
} from "lucide-react";
import { mediaUrl, adminVerifyGrievance, adminForwardIssue, adminCloseIssue, fetchOfficerContacts, summariseDocument } from "@/lib/api";
import { departmentMeta } from "@/lib/departments";
import { loadDeptTree, resolveRouting } from "@/lib/deptRouting";

/** Fuzzy officer-contact lookup against the backend contacts map (mirrors the
 *  old localStorage contactForRouting: exact key, then any officer match in
 *  the same department). */
function pickContact(routing, contacts) {
  if (!routing || !contacts) return null;
  const exact = contacts[`${routing.govDept}||${routing.subDept}||${routing.officer}`];
  if (exact) return exact;
  const prefix = `${routing.govDept}||`;
  const suffix = `||${routing.officer}`;
  const hit = Object.keys(contacts).find((k) => k.startsWith(prefix) && k.endsWith(suffix));
  return hit ? contacts[hit] : null;
}
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
  const [resolve, setResolve] = useState(false);
  const [routing, setRouting] = useState(null);
  const [contact, setContact] = useState(null);

  // Resolve the AI routing chain (Gov Dept → … → Responsible Officer) + look up
  // the officer's configured contact whenever the ticket changes; re-check the
  // contact if the departmental config is edited elsewhere.
  useEffect(() => {
    if (!issue) return undefined;
    let alive = true;
    Promise.all([
      loadDeptTree(),
      fetchOfficerContacts().then((r) => r.contacts || {}).catch(() => ({})),
    ]).then(([tree, contacts]) => {
      if (!alive) return;
      const current = resolveRouting(issue, tree);
      setRouting(current);
      setContact(pickContact(current, contacts));
    });
    return () => { alive = false; };
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

  const canDispatch = issue.department && ["ACTIVE", "FORWARDED", "IN_PROGRESS"].includes(issue.status);

  return (
    <div className="fixed inset-0 z-[80] flex">
      <div className="animate-scrim-in flex-1 bg-slate-900/40 backdrop-blur-[3px]" onClick={onClose} />
      {/* Solid white, not frosted: this drawer is a reading surface for
          photos, transcripts and evidence, and the dashboard showing through
          it put moving colour behind all of them. */}
      <div className="animate-drawer-in flex h-full w-[70%] min-w-0 flex-col border-l border-slate-200 bg-white shadow-2xl">
        {/* Drawer header */}
        <div className="flex items-center justify-between border-b border-slate-200 px-6 py-3.5">
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
        <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] divide-x divide-slate-200">
          {/* ── LEFT: media ── */}
          <div className="min-h-0 overflow-y-auto bg-slate-50/70 p-5 space-y-4">
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

            {issue.document_url && (
              <Section icon={FileText} title="Document submission">
                <DocumentPreview issue={issue} />
              </Section>
            )}

            {(issue.closure_image_url || issue.closure_audio_url) && (
              <Section icon={CheckCircle2} title="Closure evidence">
                <div className="space-y-2.5 rounded-xl bg-white p-3 ring-1 ring-emerald-100">
                  {issue.closure_image_url && (
                    <a href={mediaUrl(issue.closure_image_url)} target="_blank" rel="noreferrer">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={mediaUrl(issue.closure_image_url)} alt="Closure proof"
                        className="w-full rounded-lg object-cover ring-1 ring-slate-200" style={{ maxHeight: 220 }} />
                    </a>
                  )}
                  {issue.closure_audio_url && (
                    /* eslint-disable-next-line jsx-a11y/media-has-caption */
                    <audio controls src={mediaUrl(issue.closure_audio_url)} className="w-full" />
                  )}
                  <p className="text-[11px] text-slate-400">
                    Captured by the coordinator at the moment of closing.
                  </p>
                </div>
              </Section>
            )}

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
                  <p className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-brand"><Sparkles size={12} /> AI Summary (Voice Note)</p>
                  {issue.transcript && <p className="text-sm italic leading-snug text-slate-700">“{issue.transcript}”</p>}
                  {issue.summary_highlights?.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {issue.summary_highlights.map((h, i) => (
                        <span key={i} className="rounded-full bg-white px-2.5 py-0.5 text-[11px] font-medium text-brand ring-1 ring-brand-200">{h}</span>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {/* Reading the attached petition is a separate, manual action:
                  it costs a model call, most grievances have no document, and
                  opening a ticket to glance at it should not trigger one. The
                  button only exists when there is something to read. */}
              {issue.document_url && <DocumentSummary issue={issue} />}
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
              {["ACTIVE", "FORWARDED", "IN_PROGRESS"].includes(issue.status) && (
                <ActionBtn onClick={() => setResolve(true)} success icon={CheckCircle2}>Mark Resolved</ActionBtn>
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

      {wa && (
        <WhatsAppModal
          issue={issue}
          officer={routing?.officer}
          contact={contact}
          // Sending IS forwarding — the status moves on the dispatch rather
          // than on a separate button that claimed the same thing.
          onDispatched={async () => {
            if (issue.status === "ACTIVE" || issue.status === "IN_PROGRESS") {
              try {
                await adminForwardIssue(issue.id);
                onChanged?.();
              } catch { /* the message still went; leave the status alone */ }
            }
          }}
          onClose={() => setWa(false)}
        />
      )}
      {resolve && (
        <ResolveModal
          issue={issue}
          onClose={() => setResolve(false)}
          onDone={() => { setResolve(false); onChanged?.(); }}
        />
      )}
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


/* ── Petition document ────────────────────────────────────────────────────
   A single bar the same width as the photo and audio cards above it, so the
   left column reads as one stack rather than one item breaking the rhythm.
   Clicking expands an inline preview; the file itself is one click further,
   in a new tab. */
function DocumentPreview({ issue }) {
  const [open, setOpen] = useState(false);
  const url = mediaUrl(issue.document_url);
  const name = issue.document_name || "Attached petition";
  const isPdf = /\.pdf$/i.test(name) || /\.pdf$/i.test(issue.document_url || "");
  const isImage = /\.(png|jpe?g|webp)$/i.test(name);

  return (
    <div className="overflow-hidden rounded-xl bg-white ring-1 ring-slate-200">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center gap-2.5 p-3 text-left transition hover:bg-slate-50"
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-brand/10 text-brand">
          <FileText size={16} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13px] font-bold text-slate-800">{name}</span>
          <span className="block text-[11px] text-slate-400">
            Uploaded by the citizen · {open ? "click to collapse" : "click to preview"}
          </span>
        </span>
        <ChevronDown
          size={16}
          className={`shrink-0 text-slate-400 transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>

      {open && (
        <div className="border-t border-slate-100 p-3">
          {isPdf ? (
            <object data={url} type="application/pdf" className="h-[420px] w-full rounded-lg ring-1 ring-slate-200">
              <p className="p-4 text-[12px] text-slate-500">
                This browser cannot show the PDF inline.
              </p>
            </object>
          ) : isImage ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={url} alt={name} className="w-full rounded-lg object-contain ring-1 ring-slate-200" style={{ maxHeight: 420 }} />
          ) : (
            <p className="rounded-lg bg-slate-50 p-4 text-[12px] text-slate-500">
              No inline preview for this file type.
            </p>
          )}
          <a href={url} target="_blank" rel="noreferrer"
            className="mt-2.5 inline-flex items-center gap-1.5 text-[12px] font-bold text-brand hover:underline">
            Open in a new tab <ExternalLink size={12} />
          </a>
        </div>
      )}
    </div>
  );
}

/* ── AI Summary (Document) ────────────────────────────────────────────────
   Manual by design. The model reads Tamil and English alike, and a scan is
   handled as an image; the result is cached server-side so the button is paid
   for once per document. */
function DocumentSummary({ issue }) {
  const [state, setState] = useState({ status: "idle" });

  async function run(refresh = false) {
    setState({ status: "loading" });
    try {
      const data = await summariseDocument(issue.id, { refresh });
      setState(
        data.ok
          ? { status: "done", data }
          : { status: "error", message: data.reason || "Could not read the document." }
      );
    } catch (err) {
      setState({ status: "error", message: err.message });
    }
  }

  if (state.status === "done") {
    const d = state.data;
    return (
      <div className="mt-2 rounded-xl border border-amber-200/70 bg-amber-50/50 p-3">
        <div className="mb-1.5 flex flex-wrap items-center justify-between gap-2">
          <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-amber-700">
            <FileText size={12} /> AI Summary (Document)
            {d.language && (
              <span className="rounded-full bg-white px-1.5 py-0.5 text-[10px] font-bold text-amber-700 ring-1 ring-amber-200">
                {d.language}
              </span>
            )}
          </p>
          <button type="button" onClick={() => run(true)}
            className="text-[11px] font-bold text-amber-700 hover:underline">
            Re-read
          </button>
        </div>
        {d.title && <p className="text-[13px] font-bold text-slate-800">{d.title}</p>}
        {d.summary && <p className="mt-1 text-[13px] leading-snug text-slate-700">{d.summary}</p>}
        {d.points?.length > 0 && (
          <ul className="mt-2.5 space-y-1.5">
            {d.points.map((pt, i) => (
              <li key={i} className="flex gap-2 text-[12.5px] leading-snug text-slate-700">
                <span className="mt-[7px] h-1 w-1 shrink-0 rounded-full bg-amber-600" />
                {pt}
              </li>
            ))}
          </ul>
        )}
        {d.asks?.length > 0 && (
          <div className="mt-2.5">
            <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-amber-700">Asking for</p>
            <div className="flex flex-wrap gap-1.5">
              {d.asks.map((a, i) => (
                <span key={i} className="rounded-full bg-white px-2.5 py-0.5 text-[11px] font-medium text-amber-800 ring-1 ring-amber-200">{a}</span>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="mt-2">
      <button
        type="button"
        onClick={() => run(false)}
        disabled={state.status === "loading"}
        className="flex w-full items-center justify-center gap-2 rounded-xl border border-amber-300 bg-amber-50/60 px-3 py-2.5 text-[12.5px] font-bold text-amber-800 transition hover:bg-amber-50 disabled:opacity-60"
      >
        {state.status === "loading" ? <Loader2 size={14} className="animate-spin" /> : <FileText size={14} />}
        {state.status === "loading" ? "Reading the document…" : "AI Summary (Document)"}
      </button>
      {state.status === "error" && (
        <p className="mt-1.5 text-[11.5px] text-rose-600">{state.message}</p>
      )}
    </div>
  );
}


/* ── Mark Resolved ────────────────────────────────────────────────────────
   Closing used to be a bare button. The coordinator app has required a photo
   and a note to close since the evidence work; admin could close with nothing,
   which made the two routes to the same status mean different things. */
function ResolveModal({ issue, onClose, onDone }) {
  const [photo, setPhoto] = useState(null);
  const [preview, setPreview] = useState(null);
  const [note, setNote] = useState("");
  const [voice, setVoice] = useState(null);
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const recorderRef = useState(() => ({ rec: null, chunks: [] }))[0];

  // A note is compulsory, in either form — typed or spoken.
  const hasNote = note.trim().length > 0 || !!voice;
  const ready = !!photo && hasNote;

  function pick(e) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPhoto(f);
    setPreview(URL.createObjectURL(f));
  }

  async function toggleRecord() {
    if (recording) {
      recorderRef.rec?.stop();
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const rec = new MediaRecorder(stream);
      recorderRef.rec = rec;
      recorderRef.chunks = [];
      rec.ondataavailable = (e) => e.data.size && recorderRef.chunks.push(e.data);
      rec.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        setVoice(new Blob(recorderRef.chunks, { type: "audio/webm" }));
        setRecording(false);
      };
      rec.start();
      setRecording(true);
    } catch {
      setError("Microphone unavailable — type a note instead.");
    }
  }

  async function submit() {
    setBusy(true); setError(null);
    try {
      await adminCloseIssue(issue.id, { note: note.trim(), photo, voice });
      onDone();
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[700] flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-slate-200 px-5 py-3.5">
          <div>
            <p className="text-[15px] font-extrabold text-slate-900">Mark resolved</p>
            <p className="text-[11.5px] text-slate-400">{ticketNo(issue)} · proof of work is required</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1.5 text-slate-400 hover:bg-slate-100"><X size={18} /></button>
        </div>

        <div className="space-y-4 p-5">
          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
              Photo of the completed work <span className="text-rose-500">*</span>
            </p>
            <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-dashed border-slate-300 p-3 hover:border-brand">
              <input type="file" accept="image/*" capture="environment" className="hidden" onChange={pick} />
              {preview ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={preview} alt="" className="h-14 w-14 rounded-lg object-cover ring-1 ring-slate-200" />
              ) : (
                <span className="flex h-14 w-14 items-center justify-center rounded-lg bg-slate-100 text-slate-400"><Camera size={20} /></span>
              )}
              <span className="min-w-0 flex-1">
                <span className="block text-[13px] font-bold text-slate-700">
                  {photo ? photo.name : "Attach a photo"}
                </span>
                <span className="block text-[11.5px] text-slate-400">
                  {photo ? "Click to replace" : "Shows the citizen what was actually done"}
                </span>
              </span>
            </label>
          </div>

          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
              Resolution note <span className="text-rose-500">*</span>
              <span className="ml-1 font-medium normal-case text-slate-400">— typed or spoken</span>
            </p>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={3}
              placeholder="What was done, by whom, and when."
              className="w-full resize-none rounded-xl border border-slate-300 px-3 py-2.5 text-[13px] outline-none focus:border-brand focus:ring-2 focus:ring-brand/15"
            />
            <div className="mt-2 flex items-center gap-2">
              <button type="button" onClick={toggleRecord}
                className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[12px] font-bold ${
                  recording ? "bg-rose-50 text-rose-600" : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                }`}>
                {recording ? <Square size={12} /> : <Mic size={12} />}
                {recording ? "Stop recording" : voice ? "Re-record" : "Record instead"}
              </button>
              {voice && !recording && (
                <span className="flex items-center gap-1 text-[11.5px] font-semibold text-emerald-600">
                  <CheckCircle2 size={12} /> Voice note attached
                </span>
              )}
            </div>
          </div>

          {error && <p className="rounded-lg bg-rose-50 px-3 py-2 text-[12px] font-semibold text-rose-600">{error}</p>}

          <button
            type="button"
            onClick={submit}
            disabled={!ready || busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-emerald-600 py-3 text-[13.5px] font-bold text-white transition hover:bg-emerald-700 disabled:opacity-45"
          >
            <CheckCircle2 size={16} />
            {busy ? "Submitting…" : "Mark resolved & notify citizen"}
          </button>
          {!ready && (
            <p className="-mt-1 text-center text-[11.5px] text-slate-400">
              {!photo ? "Attach a photo" : "Add a note, typed or spoken"} to continue.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
