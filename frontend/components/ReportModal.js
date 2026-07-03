"use client";

/**
 * ReportModal
 * -----------
 * The "Report Street Issue" flow presented as a floating glass pop-up (opened
 * from the [+] in the pill nav) instead of a full screen. All the original
 * report logic — geolocation, camera-only capture, voice note, duplicate/verify/
 * success flow — lives here unchanged.
 */

import { useEffect, useRef, useState } from "react";
import { MapPin, RotateCcw, Camera, Mic, Square, Trash2, Send, X } from "lucide-react";
import DuplicateModal from "@/components/DuplicateModal";
import VerifyModal from "@/components/VerifyModal";
import SuccessModal from "@/components/SuccessModal";
import { reportIssue, upvoteIssue } from "@/lib/api";
import { useGeolocation, useRecorder } from "@/lib/hooks";
import { getUserId } from "@/lib/user";
import { ticketNumber } from "@/lib/ticket";

export default function ReportModal({ open, onClose }) {
  const { coords, areaName, status: geoStatus, refresh } = useGeolocation();
  const recorder = useRecorder();

  const [userId, setUserId]       = useState("demo-user");
  const [title, setTitle]         = useState("");
  const [imageFile, setImageFile] = useState(null);
  const [imagePreview, setImagePreview] = useState(null);

  const [submitting, setSubmitting] = useState(false);
  const [duplicate, setDuplicate]   = useState(null);
  const [verifyIssue, setVerifyIssue] = useState(null);
  const [ticket, setTicket]         = useState(null);
  const [error, setError]           = useState(null);
  const [info, setInfo]             = useState(null);

  const cameraInputRef = useRef(null);

  useEffect(() => { setUserId(getUserId()); }, []);

  function onPickImage(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
  }

  function clearImage() {
    setImageFile(null);
    if (imagePreview) URL.revokeObjectURL(imagePreview);
    setImagePreview(null);
  }

  function resetAll() {
    clearImage();
    recorder.reset();
    setTitle("");
    setError(null);
    setInfo(null);
    setDuplicate(null);
    setVerifyIssue(null);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
  }

  async function doSubmit(force = false) {
    setError(null);
    setInfo(null);
    if (!coords) { setError("Waiting for your location…"); return; }
    if (!imageFile && !recorder.audioBlob) {
      setError("Add a photo or a voice note to describe the issue.");
      return;
    }
    setSubmitting(true);
    try {
      const res = await reportIssue({
        imageFile,
        audioBlob: recorder.audioBlob,
        latitude: coords.lat,
        longitude: coords.lng,
        userId,
        title: title.trim() || "Street Issue",
        force,
      });
      if (res.duplicate_exists) setDuplicate(res.existing_issue);
      else { setDuplicate(null); setVerifyIssue(res); }
    } catch (err) {
      setError(err.message || "Submission failed");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleUpvoteExisting() {
    if (!duplicate) return;
    setSubmitting(true);
    try {
      await upvoteIssue(duplicate.id, userId);
      setInfo("Thanks! Your upvote was added to the existing report.");
      setDuplicate(null);
    } catch (err) {
      setError(err.message || "Could not upvote");
    } finally {
      setSubmitting(false);
    }
  }

  function handleVerified() {
    const issue = verifyIssue;
    setVerifyIssue(null);
    setTicket(ticketNumber(issue?.id));
    resetAll();
  }

  function handleClose() {
    resetAll();
    setTicket(null);
    onClose?.();
  }

  if (!open) return null;

  const mm = String(Math.floor(recorder.seconds / 60)).padStart(2, "0");
  const ss = String(recorder.seconds % 60).padStart(2, "0");

  return (
    <div className="absolute inset-0 z-[600] flex items-center justify-center px-4 pb-24 pt-6">
      {/* Scrim */}
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={handleClose} />

      {/* Floating iOS glass card — kept clear of the pill nav */}
      <div className="animate-modal-float glass-strong relative z-10 flex max-h-full w-full flex-col overflow-hidden rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        <div className="mx-auto mt-2.5 h-1 w-10 shrink-0 rounded-full bg-slate-300/80" />
        <div className="no-scrollbar overflow-y-auto px-4 pb-4 pt-1">
          {/* Header */}
          <div className="flex items-start justify-between pt-1">
            <div>
              <h1 className="text-xl font-extrabold tracking-tight text-slate-900">Report Street Issue</h1>
              <p className="text-xs text-slate-500">Help us build better and safer streets</p>
            </div>
            <button onClick={handleClose} className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-200/70 text-slate-500 hover:bg-slate-300/70">
              <X size={17} />
            </button>
          </div>

          {/* Location */}
          <section className="mt-3 rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm">
            <div className="flex items-start justify-between">
              <div className="flex items-start gap-2">
                <MapPin size={16} className="mt-0.5 shrink-0 text-brand" />
                <div>
                  <p className="text-sm font-semibold text-slate-800">Current Location</p>
                  {coords ? (
                    areaName
                      ? <p className="text-xs font-medium text-slate-700">{areaName}</p>
                      : <p className="text-xs text-slate-400">{coords.lat.toFixed(4)}° N, {coords.lng.toFixed(4)}° E</p>
                  ) : <p className="text-xs text-slate-400">Locating…</p>}
                </div>
              </div>
              <span className={`rounded-full px-2 py-1 text-[10px] font-semibold ${
                geoStatus === "ready" ? "bg-green-100 text-green-700" : "bg-amber-100 text-amber-700"
              }`}>
                {geoStatus === "ready" ? `±${Math.round(coords?.accuracy || 0)} m`
                  : geoStatus === "fallback" ? "Default location" : "Locating…"}
              </span>
            </div>
            <button onClick={refresh} className="mt-2 flex items-center gap-1 text-xs font-medium text-brand">
              <RotateCcw size={12} /> Refresh location
            </button>
          </section>

          {/* Title */}
          <section className="mt-3">
            <label className="mb-1 block text-xs font-semibold text-slate-600">Issue title (optional)</label>
            <input
              value={title}
              onChange={e => setTitle(e.target.value)}
              placeholder="e.g. Broken road near 8th Main"
              className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand"
            />
          </section>

          {/* Camera-only capture */}
          <section className="mt-3 rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm">
            <p className="mb-1 text-sm font-semibold text-slate-800">Capture Photo of the Issue</p>
            <p className="mb-3 text-xs text-slate-400">Live camera capture only — gallery uploads are disabled.</p>
            <div className="flex gap-3">
              <button
                onClick={() => cameraInputRef.current?.click()}
                className="flex flex-1 flex-col items-center gap-1.5 rounded-xl bg-brand-50 py-4 text-xs font-medium text-brand"
              >
                <Camera size={22} /> Capture Photo
              </button>
              {imagePreview && (
                <div className="relative h-24 w-24 shrink-0">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={imagePreview} alt="preview" className="h-24 w-24 rounded-xl object-cover" />
                  <button onClick={clearImage} className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-slate-800 text-white">
                    <span className="text-xs">✕</span>
                  </button>
                </div>
              )}
            </div>
            <input ref={cameraInputRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickImage} />
          </section>

          {/* Voice */}
          <section className="mt-3 rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm">
            <p className="mb-3 text-sm font-semibold text-slate-800">Describe the issue in your language</p>
            <div className="flex items-center gap-4">
              <button
                onClick={recorder.isRecording ? recorder.stop : recorder.start}
                className={`flex h-16 w-16 shrink-0 items-center justify-center rounded-full text-white transition ${
                  recorder.isRecording ? "recording-pulse bg-red-500" : "bg-brand"
                }`}
              >
                {recorder.isRecording ? <Square size={20} className="fill-white" /> : <Mic size={24} />}
              </button>
              <div className="flex-1">
                {recorder.isRecording ? (
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-sm font-semibold text-slate-700">{mm}:{ss}</span>
                    <div className="flex h-6 items-end gap-0.5">
                      {Array.from({ length: 16 }).map((_, i) => (
                        <span key={i} className="eq-bar w-1 rounded-full bg-brand" style={{ height: "100%", animationDelay: `${(i % 8) * 0.08}s` }} />
                      ))}
                    </div>
                  </div>
                ) : recorder.audioUrl ? (
                  <div className="space-y-2">
                    <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                      ✓ Voice Recorded ({mm}:{ss})
                    </span>
                    <audio src={recorder.audioUrl} controls className="h-8 w-full" />
                  </div>
                ) : (
                  <p className="text-sm text-slate-400">Tap the mic to record your description (any Indian language).</p>
                )}
              </div>
              {recorder.audioUrl && !recorder.isRecording && (
                <button onClick={recorder.reset} className="text-red-400" title="Delete recording">
                  <Trash2 size={18} />
                </button>
              )}
            </div>
            {recorder.error && <p className="mt-2 text-xs text-red-500">{recorder.error}</p>}
          </section>

          {error && <div className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-600">{error}</div>}
          {info &&  <div className="mt-3 rounded-xl border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-700">{info}</div>}

          <div className="mt-4">
            <button
              onClick={() => doSubmit(false)}
              disabled={submitting}
              className="flex w-full items-center justify-center gap-2 rounded-2xl bg-brand py-3.5 text-base font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-60"
            >
              {submitting ? "Processing…" : <><Send size={18} /> Submit Grievance</>}
            </button>
          </div>
        </div>
      </div>

      {/* Sub-modals */}
      <DuplicateModal issue={duplicate} busy={submitting} onUpvote={handleUpvoteExisting} onSubmitAnyway={() => doSubmit(true)} onClose={() => setDuplicate(null)} />
      <VerifyModal issue={verifyIssue} onVerified={handleVerified} onClose={() => setVerifyIssue(null)} />
      <SuccessModal ticket={ticket} onClose={handleClose} />
    </div>
  );
}
