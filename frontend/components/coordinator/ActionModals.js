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
  X, Send, Camera, Mic, Square, CheckCircle2, Ban, ArrowRightLeft, Building2,
  Trash2, Sparkles,
} from "lucide-react";
import { DEPARTMENTS, departmentMeta } from "@/lib/departments";
import { useRecorder } from "@/lib/hooks";

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

/* ── Redirect ── */
export function RedirectModal({ open, issue, onClose, onSubmit }) {
  const [description, setDescription] = useState("");
  useEffect(() => { if (!open) setDescription(""); }, [open]);
  const canSubmit = description.trim().length >= 8;
  return (
    <ModalShell open={open} onClose={onClose} icon={ArrowRightLeft}
      title="Redirect Grievance"
      subtitle="Send this back to admin with a brief note">
      {issue && <IssuePreview issue={issue} />}
      <div>
        <label className="mb-1 block text-xs font-semibold text-slate-600">Reason for redirect *</label>
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4}
          placeholder="e.g. This grievance falls under Public Works. Redirecting for further review."
          className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
        <p className="mt-1 text-[10px] text-slate-400">Minimum 8 characters</p>
      </div>
      <button onClick={() => canSubmit && onSubmit({ description: description.trim() })}
        disabled={!canSubmit}
        className="flex w-full items-center justify-center gap-2 rounded-xl bg-slate-800 py-3 text-sm font-bold text-white shadow-lg disabled:opacity-50">
        <Send size={14} /> Submit & Redirect
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

  useEffect(() => {
    if (open) {
      setDepartment(aiSuggested);
      setNotes("");
    }
  }, [open, aiSuggested]);

  const meta = departmentMeta(department);
  const changed = department !== aiSuggested;

  return (
    <ModalShell open={open} onClose={onClose} icon={Send}
      title="Department Transfer"
      subtitle="AI-detected route — change if needed">
      {issue && <IssuePreview issue={issue} />}

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

      <button onClick={() => onSubmit({ department, aiSuggested, overridden: changed, notes: notes.trim() })}
        className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg">
        <Send size={15} /> Submit & Transfer
      </button>
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
      <button onClick={() => canSubmit && onSubmit({ reason, details: details.trim() })}
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
