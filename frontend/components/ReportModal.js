"use client";

/**
 * ReportModal
 * -----------
 * "Report Street Issue" floating glass pop-up (opened from the [+] in the pill
 * nav). Streamlined flow: capture photo(s) and/or a voice note, then swipe to
 * submit. No title, no OTP — a full-screen success animation acknowledges the
 * submission. Fair-use limit: 1 grievance/day (highlighted at the top).
 *
 *   • Camera + voice recorder sit side-by-side above the swipe control.
 *   • Captured photo thumbnails stack above the camera tile.
 *   • The voice playback preview sits above the recorder tile.
 */

import { useEffect, useRef, useState } from "react";
import {
  MapPin, RotateCcw, Camera, Mic, Square, Trash2, X, Play, Pause, TriangleAlert,
} from "lucide-react";
import SwipeToConfirm from "@/components/SwipeToConfirm";
import SuccessOverlay from "@/components/SuccessOverlay";
import { reportIssue, confirmIssue } from "@/lib/api";
import { useGeolocation, useRecorder } from "@/lib/hooks";
import { getUserId } from "@/lib/user";
import { ticketNumber } from "@/lib/ticket";
import { dailyState, consumeDaily, GRIEVANCE_LIMIT_KEY } from "@/lib/dailyLimit";

const DAILY_MAX = 1;

/* Compact voice playback pill shown above the recorder tile. */
function AudioPill({ url, seconds, onDelete }) {
  const ref = useRef(null);
  const [playing, setPlaying] = useState(false);
  const mm = String(Math.floor(seconds / 60)).padStart(2, "0");
  const ss = String(seconds % 60).padStart(2, "0");

  function toggle() {
    const el = ref.current;
    if (!el) return;
    if (playing) { el.pause(); } else { el.play(); }
    setPlaying((p) => !p);
  }

  return (
    <div className="flex items-center gap-2 rounded-xl bg-brand-50 px-2 py-1.5 ring-1 ring-brand-100">
      <button type="button" onClick={toggle} className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand text-white">
        {playing ? <Pause size={13} /> : <Play size={13} className="ml-0.5" />}
      </button>
      <div className="flex h-4 flex-1 items-center gap-[2px]">
        {Array.from({ length: 14 }).map((_, i) => (
          <span key={i} className="w-0.5 rounded-full bg-brand/40" style={{ height: `${30 + ((i * 37) % 70)}%` }} />
        ))}
      </div>
      <span className="shrink-0 font-mono text-[11px] font-semibold text-brand">{mm}:{ss}</span>
      <button type="button" onClick={onDelete} className="shrink-0 text-slate-400 hover:text-rose-500" title="Delete recording">
        <Trash2 size={14} />
      </button>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <audio ref={ref} src={url} onEnded={() => setPlaying(false)} className="hidden" />
    </div>
  );
}

export default function ReportModal({ open, onClose }) {
  const { coords, areaName, status: geoStatus, refresh } = useGeolocation();
  const recorder = useRecorder();

  const [userId, setUserId] = useState("demo-user");
  const [images, setImages] = useState([]); // [{ id, file, url }]
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const [ticket, setTicket] = useState(null);
  const [showSuccess, setShowSuccess] = useState(false);
  const [limit, setLimit] = useState({ used: 0, remaining: DAILY_MAX, max: DAILY_MAX });
  const [resetToken, setResetToken] = useState(0);

  const cameraInputRef = useRef(null);

  useEffect(() => { setUserId(getUserId()); }, []);
  useEffect(() => { if (open) setLimit(dailyState(GRIEVANCE_LIMIT_KEY, DAILY_MAX)); }, [open]);

  function onPickImage(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImages((arr) => [...arr, { id: `${Date.now()}-${arr.length}`, file, url: URL.createObjectURL(file) }]);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
  }

  function removeImage(id) {
    setImages((arr) => {
      const gone = arr.find((x) => x.id === id);
      if (gone) URL.revokeObjectURL(gone.url);
      return arr.filter((x) => x.id !== id);
    });
  }

  function resetAll() {
    images.forEach((x) => URL.revokeObjectURL(x.url));
    setImages([]);
    recorder.reset();
    setError(null);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
  }

  function bumpReset() { setResetToken((t) => t + 1); }

  async function submit() {
    setError(null);
    // Fair-use counter is display-only for the demo — never blocks submission.
    if (!coords) { setError("Waiting for your location…"); bumpReset(); return; }
    if (images.length === 0 && !recorder.audioBlob) { setError("Add a photo or a voice note to describe the issue."); bumpReset(); return; }

    setSubmitting(true);
    try {
      const res = await reportIssue({
        imageFile: images[0]?.file,
        audioBlob: recorder.audioBlob,
        latitude: coords.lat,
        longitude: coords.lng,
        userId,
        title: "Street Issue",
        force: true,
      });
      if (res?.id) {
        const name = (typeof window !== "undefined" && localStorage.getItem("nk_citizen_name")) || "Citizen";
        try { await confirmIssue(res.id, "9999900000", name); } catch { /* non-blocking */ }
      }
      setLimit(consumeDaily(GRIEVANCE_LIMIT_KEY, DAILY_MAX));
      setTicket(ticketNumber(res?.id));
      setShowSuccess(true);
    } catch (err) {
      setError(err.message || "Submission failed. Please try again.");
      bumpReset();
    } finally {
      setSubmitting(false);
    }
  }

  function handleClose() {
    resetAll();
    onClose?.();
  }

  function handleSuccessDone() {
    setShowSuccess(false);
    setTicket(null);
    resetAll();
    onClose?.();
  }

  if (!open && !showSuccess) return null;

  const mm = String(Math.floor(recorder.seconds / 60)).padStart(2, "0");
  const ss = String(recorder.seconds % 60).padStart(2, "0");

  return (
    <>
      {open && (
        <div className="absolute inset-0 z-[600] flex items-center justify-center px-4 pb-24 pt-6">
          {/* Scrim */}
          <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={handleClose} />

          {/* Floating iOS glass card */}
          <div className="animate-modal-float glass-strong relative z-10 flex max-h-full w-full flex-col overflow-hidden rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
            <div className="mx-auto mt-2.5 h-1 w-10 shrink-0 rounded-full bg-slate-300/80" />
            <div className="no-scrollbar overflow-y-auto px-4 pb-5 pt-1">
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

              {/* Fair-use counter — display only, never enforced (demo) */}
              <div className="mt-3 flex items-center gap-2.5 rounded-2xl bg-amber-50 px-3.5 py-2.5 text-amber-800 ring-1 ring-amber-200">
                <TriangleAlert size={16} className="shrink-0" />
                <p className="text-[12.5px] font-semibold leading-snug">
                  Fair-use: <b>1 grievance per day</b> · {Math.max(0, limit.remaining)} of {limit.max} remaining today
                </p>
              </div>

              {/* Location */}
              <section className="mt-3 rounded-2xl border border-slate-200 bg-white p-3 shadow-sm">
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
                    geoStatus === "ready" ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-600"
                  }`}>
                    {geoStatus === "ready" ? `±${Math.round(coords?.accuracy || 0)} m`
                      : geoStatus === "fallback" ? "Default location" : "Locating…"}
                  </span>
                </div>
                <button onClick={refresh} className="mt-1.5 flex items-center gap-1 text-xs font-medium text-brand">
                  <RotateCcw size={12} /> Refresh location
                </button>
              </section>

              {/* Capture row — camera + voice side by side, previews above each */}
              <div className="mt-3 grid grid-cols-2 items-end gap-3">
                {/* Camera column */}
                <div className="flex flex-col gap-2">
                  {images.length > 0 && (
                    <div className="flex flex-wrap gap-1.5">
                      {images.map((img) => (
                        <div key={img.id} className="relative">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img src={img.url} alt="" className="h-11 w-11 rounded-lg object-cover ring-1 ring-slate-200" />
                          <button onClick={() => removeImage(img.id)} className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-slate-800 text-white">
                            <X size={11} />
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  <button
                    onClick={() => cameraInputRef.current?.click()}
                    className="flex flex-col items-center justify-center gap-1 rounded-2xl bg-brand-50 py-3.5 text-xs font-semibold text-brand ring-1 ring-brand-100 transition active:scale-[0.98]"
                  >
                    <Camera size={22} />
                    {images.length > 0 ? `Add photo (${images.length})` : "Capture photo"}
                  </button>
                </div>

                {/* Voice column */}
                <div className="flex flex-col gap-2">
                  {recorder.audioUrl && !recorder.isRecording && (
                    <AudioPill url={recorder.audioUrl} seconds={recorder.seconds} onDelete={recorder.reset} />
                  )}
                  <button
                    onClick={recorder.isRecording ? recorder.stop : recorder.start}
                    className={`flex flex-col items-center justify-center gap-1 rounded-2xl py-3.5 text-xs font-semibold ring-1 transition active:scale-[0.98] ${
                      recorder.isRecording
                        ? "recording-pulse bg-rose-500 text-white ring-rose-300"
                        : "bg-brand-50 text-brand ring-brand-100"
                    }`}
                  >
                    {recorder.isRecording ? (
                      <>
                        <Square size={20} className="fill-white" />
                        <span className="font-mono">{mm}:{ss} · Stop</span>
                      </>
                    ) : (
                      <>
                        <Mic size={22} />
                        {recorder.audioUrl ? "Re-record" : "Record voice"}
                      </>
                    )}
                  </button>
                </div>
              </div>
              <input ref={cameraInputRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickImage} />
              {recorder.error && <p className="mt-2 text-xs text-rose-500">{recorder.error}</p>}

              {error && <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-600">{error}</div>}

              {/* Swipe to submit */}
              <div className="mt-4">
                <SwipeToConfirm
                  label={submitting ? "Submitting…" : "Swipe to submit grievance"}
                  busyLabel="Submitting…"
                  onConfirm={submit}
                  busy={submitting}
                  resetToken={resetToken}
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* UPI-style full-screen acknowledgement */}
      <SuccessOverlay
        open={showSuccess}
        title="Grievance Submitted"
        message="Your report is on its way to the ward coordinator. Track it anytime under Grievance."
        ticket={ticket}
        onDone={handleSuccessDone}
      />
    </>
  );
}
