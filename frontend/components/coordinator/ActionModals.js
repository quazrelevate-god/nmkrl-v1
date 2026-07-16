"use client";

/**
 * ActionModals
 * ------------
 * Four floating-glass confirmation modals for the coordinator grievance page:
 *
 *   RedirectModal   — brief description before redirecting; sends the
 *                     grievance to admin's "Redirected" section.
 *   CloseModal      — MANDATORY live-photo capture + voice recording before
 *                     closing (moves the backend status to PENDING_VERIFICATION
 *                     via adminCloseIssue).
 *   TransferModal   — shows the AI-detected department as a changeable
 *                     dropdown + optional notes; sends the grievance to admin's
 *                     "Department Transferred" section.
 *   FalsePetitionModal — captures a reason before flagging as false; sends to
 *                        admin's "False Petitions" section.
 *
 * All four call onSubmit(data) with the collected payload; the parent is
 * responsible for wiring that into addAction() and any backend effects.
 */

import { useEffect, useRef, useState } from "react";
import {
  X, Send, Camera, Mic, Square, CheckCircle2, Ban, ChevronsUp, Building2,
  Trash2, Sparkles, Check, Paperclip,
} from "lucide-react";
import { DEPARTMENTS, departmentMeta, slaDeadline } from "@/lib/departments";
import { useRecorder } from "@/lib/hooks";
import { ticketNumber } from "@/lib/ticket";

/* ── Shared evidence capture (live photo + voice note), used across the action
   modals. Optional by default. Manages its own photo + recorder state and
   resets when the modal closes. `data()` returns the collected payload. ── */
function useEvidence(open) {
  const recorder = useRecorder();
  const [photo, setPhoto] = useState(null);
  const [photoUrl, setPhotoUrl] = useState(null);
  const cameraRef = useRef(null);

  useEffect(() => {
    if (!open) {
      setPhoto(null);
      setPhotoUrl((u) => { if (u) URL.revokeObjectURL(u); return null; });
      if (recorder.audioUrl) recorder.reset();
      if (cameraRef.current) cameraRef.current.value = "";
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  function onPickPhoto(e) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPhoto(f);
    setPhotoUrl((u) => { if (u) URL.revokeObjectURL(u); return URL.createObjectURL(f); });
  }
  function clearPhoto() {
    setPhoto(null);
    setPhotoUrl((u) => { if (u) URL.revokeObjectURL(u); return null; });
    if (cameraRef.current) cameraRef.current.value = "";
  }

  return {
    recorder, photo, photoUrl, cameraRef, onPickPhoto, clearPhoto,
    data: () => ({
      photoUrl: photoUrl || null,
      photoName: photo?.name || null,
      audioUrl: recorder.audioUrl || null,
      audioSeconds: recorder.seconds || 0,
    }),
  };
}

function EvidenceSection({ evidence, label = "Attach evidence (optional)" }) {
  const { recorder, photoUrl, cameraRef, onPickPhoto, clearPhoto } = evidence;
  const mm = String(Math.floor(recorder.seconds / 60)).padStart(2, "0");
  const ss = String(recorder.seconds % 60).padStart(2, "0");
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-3">
      <p className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-slate-700">
        <Paperclip size={13} /> {label}
      </p>
      <div className="grid grid-cols-2 gap-2">
        {/* Live camera */}
        {photoUrl ? (
          <div className="relative">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={photoUrl} alt="evidence" className="h-24 w-full rounded-xl object-cover" />
            <button onClick={clearPhoto} className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-slate-900/70 text-white"><X size={12} /></button>
          </div>
        ) : (
          <button onClick={() => cameraRef.current?.click()}
            className="flex h-24 flex-col items-center justify-center gap-1 rounded-xl bg-brand-50 text-brand ring-1 ring-brand/15">
            <Camera size={20} /><span className="text-[11px] font-bold">Live photo</span>
          </button>
        )}
        <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickPhoto} />

        {/* Voice note */}
        <div className="flex h-24 flex-col items-center justify-center gap-1.5 rounded-xl bg-brand-50 ring-1 ring-brand/15">
          <button onClick={recorder.isRecording ? recorder.stop : recorder.start}
            className={`flex h-11 w-11 items-center justify-center rounded-full text-white transition ${recorder.isRecording ? "recording-pulse bg-red-500" : "bg-brand"}`}>
            {recorder.isRecording ? <Square size={15} className="fill-white" /> : <Mic size={18} />}
          </button>
          <span className="text-[11px] font-bold text-brand">
            {recorder.isRecording ? `${mm}:${ss}` : recorder.audioUrl ? `✓ ${mm}:${ss}` : "Voice note"}
          </span>
        </div>
      </div>
      {recorder.audioUrl && !recorder.isRecording && (
        <div className="mt-2 flex items-center gap-2">
          {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
          <audio src={recorder.audioUrl} controls className="h-8 flex-1" />
          <button onClick={recorder.reset} className="shrink-0 text-rose-400"><Trash2 size={15} /></button>
        </div>
      )}
      {recorder.error && <p className="mt-1 text-[11px] text-rose-500">{recorder.error}</p>}
    </section>
  );
}

/* ── Shared modal shell ── */
function ModalShell({ open, onClose, icon: Icon, title, subtitle, children }) {
  if (!open) return null;
  return (
    <div className="absolute inset-0 z-[660] flex items-center justify-center px-4 pb-24 pt-6">
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />
      <div className="animate-modal-float glass-strong no-scrollbar relative z-10 flex max-h-full w-full flex-col overflow-y-auto rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300/80" />
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <div className="flex items-start gap-2.5">
            {Icon && (
              <span className="mt-0.5 flex h-8 w-8 items-center justify-center rounded-lg bg-brand-50 text-brand ring-1 ring-brand/20">
                <Icon size={16} />
              </span>
            )}
            <div>
              <h3 className="text-base font-bold text-slate-900">{title}</h3>
              {subtitle && <p className="text-xs text-slate-500">{subtitle}</p>}
            </div>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100"><X size={18} className="text-slate-400" /></button>
        </div>
        <div className="space-y-4 px-5 py-4">{children}</div>
      </div>
    </div>
  );
}

/* ── Escalate ── */
export function EscalateModal({ open, issue, onClose, onSubmit }) {
  const [description, setDescription] = useState("");
  const ev = useEvidence(open);
  useEffect(() => { if (!open) setDescription(""); }, [open]);
  const canSubmit = description.trim().length >= 8;
  return (
    <ModalShell open={open} onClose={onClose} icon={ChevronsUp}
      title="Escalate Grievance"
      subtitle="Raise to a higher authority — stays In Progress">
      {issue && <IssuePreview issue={issue} />}
      <div>
        <label className="mb-1 block text-xs font-semibold text-slate-600">Reason for escalation *</label>
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3}
          placeholder="e.g. Beyond ward capacity — escalating to Public Works for structural action."
          className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
        <p className="mt-1 text-[10px] text-slate-400">Minimum 8 characters</p>
      </div>
      <EvidenceSection evidence={ev} />
      <button onClick={() => canSubmit && onSubmit({ description: description.trim(), ...ev.data() })}
        disabled={!canSubmit}
        className="flex w-full items-center justify-center gap-2 rounded-xl bg-slate-800 py-3 text-sm font-bold text-white shadow-lg disabled:opacity-50">
        <ChevronsUp size={14} /> Submit & Escalate
      </button>
    </ModalShell>
  );
}

/* ── Close (requires photo + voice) ── */
export function CloseModal({ open, issue, onClose, onSubmit }) {
  const recorder = useRecorder();
  const [photo, setPhoto] = useState(null);
  const [photoUrl, setPhotoUrl] = useState(null);
  const [notes, setNotes] = useState("");
  const cameraRef = useRef(null);

  useEffect(() => {
    if (!open) {
      setPhoto(null); setPhotoUrl(null); setNotes("");
      if (recorder.audioUrl) recorder.reset();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  function onPickPhoto(e) {
    const f = e.target.files?.[0]; if (!f) return;
    setPhoto(f);
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    setPhotoUrl(URL.createObjectURL(f));
  }

  const canSubmit = photo && recorder.audioBlob;
  const mm = String(Math.floor(recorder.seconds / 60)).padStart(2, "0");
  const ss = String(recorder.seconds % 60).padStart(2, "0");

  return (
    <ModalShell open={open} onClose={onClose} icon={CheckCircle2}
      title="Mark as Closed"
      subtitle="Live photo + voice note required to close">
      {issue && <IssuePreview issue={issue} />}

      {/* Photo capture — mandatory */}
      <section className="rounded-2xl border border-slate-200 bg-white p-3">
        <p className="mb-2 flex items-center justify-between text-xs font-semibold text-slate-700">
          <span className="flex items-center gap-1.5"><Camera size={13} /> Live photo *</span>
          {photoUrl && <span className="text-[10px] font-semibold text-emerald-600">✓ Captured</span>}
        </p>
        {photoUrl ? (
          <div className="relative">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={photoUrl} alt="closure evidence" className="max-h-40 w-full rounded-xl object-cover" />
            <button onClick={() => { setPhoto(null); setPhotoUrl(null); }}
              className="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-slate-900/70 text-white">
              <X size={14} />
            </button>
          </div>
        ) : (
          <button onClick={() => cameraRef.current?.click()}
            className="flex w-full flex-col items-center gap-1 rounded-xl bg-brand-50 py-4 text-brand ring-1 ring-brand/15">
            <Camera size={22} />
            <span className="text-xs font-bold">Capture live photo</span>
          </button>
        )}
        <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickPhoto} />
      </section>

      {/* Voice note — mandatory */}
      <section className="rounded-2xl border border-slate-200 bg-white p-3">
        <p className="mb-2 flex items-center justify-between text-xs font-semibold text-slate-700">
          <span className="flex items-center gap-1.5"><Mic size={13} /> Voice note *</span>
          {recorder.audioUrl && !recorder.isRecording && <span className="text-[10px] font-semibold text-emerald-600">✓ Recorded ({mm}:{ss})</span>}
        </p>
        <div className="flex items-center gap-3">
          <button
            onClick={recorder.isRecording ? recorder.stop : recorder.start}
            className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-full text-white transition ${
              recorder.isRecording ? "recording-pulse bg-red-500" : "bg-brand"
            }`}>
            {recorder.isRecording ? <Square size={16} className="fill-white" /> : <Mic size={20} />}
          </button>
          <div className="flex-1">
            {recorder.isRecording ? (
              <span className="font-mono text-sm font-semibold text-slate-700">{mm}:{ss}</span>
            ) : recorder.audioUrl ? (
              <audio src={recorder.audioUrl} controls className="h-8 w-full" />
            ) : (
              <p className="text-xs text-slate-400">Describe the closure verbally</p>
            )}
          </div>
          {recorder.audioUrl && !recorder.isRecording && (
            <button onClick={recorder.reset} className="text-rose-400"><Trash2 size={16} /></button>
          )}
        </div>
        {recorder.error && <p className="mt-1 text-[11px] text-rose-500">{recorder.error}</p>}
      </section>

      <div>
        <label className="mb-1 block text-xs font-semibold text-slate-600">Notes (optional)</label>
        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
          placeholder="Any additional context"
          className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
      </div>

      <button onClick={() => canSubmit && onSubmit({
          photoUrl,
          photoName: photo?.name || "closure.jpg",
          audioUrl: recorder.audioUrl,
          audioSeconds: recorder.seconds,
          notes: notes.trim(),
        })}
        disabled={!canSubmit}
        className="flex w-full items-center justify-center gap-2 rounded-xl bg-emerald-600 py-3 text-sm font-bold text-white shadow-lg disabled:opacity-50">
        <CheckCircle2 size={15} /> Submit & Notify Pending Verification
      </button>
    </ModalShell>
  );
}

/* ── Department Transfer ── */
export function TransferModal({ open, issue, onClose, onSubmit }) {
  const aiSuggested = issue?.department || Object.keys(DEPARTMENTS)[0];
  const [department, setDepartment] = useState(aiSuggested);
  const [notes, setNotes] = useState("");
  const [stage, setStage] = useState("form"); // 'form' | 'dispatch'
  const [dispatched, setDispatched] = useState(false);
  const ev = useEvidence(open);

  useEffect(() => {
    if (open) {
      setDepartment(aiSuggested);
      setNotes("");
      setStage("form");
      setDispatched(false);
    }
  }, [open, aiSuggested]);

  const meta = departmentMeta(department);
  const changed = department !== aiSuggested;

  function handleSubmit() {
    // Fire the backend action first (parent's onSubmit calls coordinatorTransfer).
    onSubmit({ department, aiSuggested, overridden: changed, notes: notes.trim(), ...ev.data() });
    // Then reveal the WhatsApp dispatch preview so the coordinator can "send it".
    setStage("dispatch");
  }

  const highlights = (issue?.summary_highlights || []).join(", ");
  const deadline = issue?.created_at
    ? slaDeadline(issue.created_at, department).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })
    : "";
  const loc = issue
    ? (issue.area_name
        ? `${issue.area_name} (${issue.latitude?.toFixed(5)}, ${issue.longitude?.toFixed(5)})`
        : `${issue.latitude?.toFixed(5)}, ${issue.longitude?.toFixed(5)}`)
    : "";
  const waMessage = issue ? `🏛️ *FixMyStreet Grievance Dispatch*

*Ticket:* ${ticketNumber(issue.id)}
*Ward No:* ${issue.ward_no ?? "—"}
*Issue:* ${issue.title}
*Details:* ${issue.transcript || highlights || "—"}
*Location:* ${loc}
*Reported:* ${new Date(issue.created_at).toLocaleDateString("en-IN")}
*SLA Deadline:* ${deadline}${notes.trim() ? `

*Coordinator note:* ${notes.trim()}` : ""}

Kindly action this grievance before the SLA deadline.` : "";

  return (
    <ModalShell open={open} onClose={onClose} icon={Send}
      title="Department Transfer"
      subtitle={stage === "form" ? "AI-detected route — change if needed" : "WhatsApp dispatch to the department"}>
      {issue && <IssuePreview issue={issue} />}

      {stage === "form" && (
        <>
          {/* AI suggestion badge */}
          <div className="rounded-2xl border border-brand-100 bg-brand-50/60 p-3">
            <p className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-brand">
              <Sparkles size={11} /> AI routed to
            </p>
            <p className="text-sm font-bold text-slate-800">{aiSuggested}</p>
            <p className="text-[10px] text-slate-500">SLA · {departmentMeta(aiSuggested).slaDays} days</p>
          </div>

          <div>
            <label className="mb-1 flex items-center gap-1.5 text-xs font-semibold text-slate-600">
              <Building2 size={13} /> Route to department {changed && <span className="text-[10px] font-normal text-amber-600">· overridden</span>}
            </label>
            <select value={department} onChange={(e) => setDepartment(e.target.value)}
              className="w-full appearance-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm font-semibold text-slate-800 outline-none focus:border-brand">
              {Object.keys(DEPARTMENTS).map((d) => (
                <option key={d} value={d}>{departmentMeta(d).short} · {d}</option>
              ))}
            </select>
            <p className="mt-1 text-[10px] text-slate-500">SLA · {meta.slaDays} days · {meta.phone}</p>
          </div>

          <div>
            <label className="mb-1 block text-xs font-semibold text-slate-600">Notes (optional)</label>
            <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3}
              placeholder="Additional context for the receiving department"
              className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
          </div>

          <EvidenceSection evidence={ev} />

          <button onClick={handleSubmit}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg">
            <Send size={15} /> Submit & Preview Dispatch
          </button>
        </>
      )}

      {stage === "dispatch" && issue && (
        <>
          {/* WhatsApp-styled dispatch preview */}
          <div className="overflow-hidden rounded-2xl ring-1 ring-slate-200">
            <div className="flex items-center gap-2 bg-[#075E54] px-3 py-2 text-white">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[#25D366] text-sm font-bold">W</div>
              <div>
                <p className="text-xs font-bold leading-tight">{meta.short} Dept.</p>
                <p className="text-[10px] text-emerald-100">{meta.phone}</p>
              </div>
            </div>
            <div className="bg-[#ECE5DD] px-3 py-3">
              <div className="ml-auto max-w-[92%] rounded-xl rounded-tr-none bg-[#DCF8C6] p-2.5 shadow-sm">
                <pre className="whitespace-pre-wrap font-sans text-[11px] leading-snug text-slate-800">{waMessage}</pre>
              </div>
              {dispatched && (
                <p className="mt-2 text-center text-[11px] font-medium text-emerald-700">
                  ✓ Message queued for {meta.short} Department (demo)
                </p>
              )}
            </div>
            <div className="flex items-center gap-2 border-t border-slate-200 bg-white px-3 py-2">
              <div className="flex-1 truncate rounded-full bg-slate-100 px-4 py-2 text-xs text-slate-400">
                Templatised grievance dispatch ready…
              </div>
              <button onClick={() => setDispatched(true)} disabled={dispatched}
                className="flex h-9 w-9 items-center justify-center rounded-full bg-[#25D366] text-white shadow disabled:opacity-60">
                {dispatched ? <Check size={16} /> : <Send size={14} />}
              </button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <button onClick={() => setStage("form")}
              className="rounded-xl border border-slate-300 bg-white py-2.5 text-xs font-bold text-slate-700">
              Edit dispatch
            </button>
            <button onClick={onClose}
              className="rounded-xl bg-brand py-2.5 text-xs font-bold text-white">
              Done
            </button>
          </div>
        </>
      )}
    </ModalShell>
  );
}

/* ── False Petition ── */
const FALSE_REASONS = [
  "Duplicate of an existing grievance",
  "Fabricated / not a real issue",
  "Personal dispute, not a public grievance",
  "Outside constituency jurisdiction",
  "Malicious / harassing report",
  "Other",
];

export function FalsePetitionModal({ open, issue, onClose, onSubmit }) {
  const [reason, setReason] = useState(FALSE_REASONS[0]);
  const [details, setDetails] = useState("");
  const ev = useEvidence(open);

  useEffect(() => {
    if (open) { setReason(FALSE_REASONS[0]); setDetails(""); }
  }, [open]);

  const canSubmit = reason && (reason !== "Other" || details.trim().length >= 6);

  return (
    <ModalShell open={open} onClose={onClose} icon={Ban}
      title="Mark as False Petition"
      subtitle="Select a reason before flagging">
      {issue && <IssuePreview issue={issue} />}
      <div>
        <label className="mb-1 block text-xs font-semibold text-slate-600">Reason *</label>
        <select value={reason} onChange={(e) => setReason(e.target.value)}
          className="w-full appearance-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm font-semibold text-slate-800 outline-none focus:border-brand">
          {FALSE_REASONS.map((r) => (<option key={r} value={r}>{r}</option>))}
        </select>
      </div>
      <div>
        <label className="mb-1 block text-xs font-semibold text-slate-600">
          Additional details {reason === "Other" ? "*" : "(optional)"}
        </label>
        <textarea value={details} onChange={(e) => setDetails(e.target.value)} rows={3}
          placeholder="Explain why this is a false petition"
          className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
      </div>
      <EvidenceSection evidence={ev} label="Attach evidence (optional)" />
      <button onClick={() => canSubmit && onSubmit({ reason, details: details.trim(), ...ev.data() })}
        disabled={!canSubmit}
        className="flex w-full items-center justify-center gap-2 rounded-xl bg-rose-600 py-3 text-sm font-bold text-white shadow-lg disabled:opacity-50">
        <Ban size={15} /> Submit & Flag as False
      </button>
    </ModalShell>
  );
}

/* ── Shared issue preview strip ── */
function IssuePreview({ issue }) {
  return (
    <div className="rounded-xl bg-slate-50 p-3">
      <p className="text-sm font-semibold leading-tight text-slate-800">{issue.title}</p>
      {issue.area_name && <p className="mt-0.5 text-xs text-slate-500">{issue.area_name}</p>}
      <p className="mt-1 flex items-center gap-2 text-[11px] font-mono text-slate-500">
        {issue.id && <span className="rounded bg-white px-1.5 py-0.5">#{issue.id.slice(0, 8)}</span>}
        {issue.ward_no != null && <span className="rounded bg-white px-1.5 py-0.5">Ward {issue.ward_no}</span>}
      </p>
    </div>
  );
}
