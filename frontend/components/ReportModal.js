"use client";

/**
 * ReportModal
 * -----------
 * Grievance submission sheet, opened from the [+] in the pill nav. Ported from
 * the Flutter app's report sheet so both clients present the same object:
 *
 *   Layer 1  bottom-attached navy sheet, top corners only
 *   Layer 2  slightly lighter inner container holding the tiles
 *   Layer 3  two FIXED-HEIGHT white tiles (photo / voice)
 *
 * The tiles never resize: adding a photo or finishing a recording swaps their
 * contents in place, so the sheet's height is constant across every state.
 * Both attachments are required; the swipe stays inert and self-describing
 * until both exist. Ends in the full-screen success acknowledgement.
 */

import { useEffect, useRef, useState } from "react";
import { Camera, Mic, Square, Trash2, Play, Pause, ShieldCheck } from "lucide-react";
import SwipeToConfirm from "@/components/SwipeToConfirm";
import SuccessOverlay from "@/components/SuccessOverlay";
import { reportIssue, confirmIssue } from "@/lib/api";
import { useGeolocation, useRecorder } from "@/lib/hooks";
import { getUserId } from "@/lib/user";
import { ticketNumber } from "@/lib/ticket";
import { dailyState, consumeDaily, GRIEVANCE_LIMIT_KEY } from "@/lib/dailyLimit";

const DAILY_MAX = 1;

export default function ReportModal({ open, onClose }) {
  const { coords } = useGeolocation();
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
  const audioRef = useRef(null);
  const [playing, setPlaying] = useState(false);

  // Both attachments are mandatory — see the guard in submit().
  const canSubmit = images.length > 0 && !!recorder.audioBlob;

  function togglePlay() {
    const el = audioRef.current;
    if (!el) return;
    if (el.paused) { el.play(); setPlaying(true); } else { el.pause(); setPlaying(false); }
  }

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
    // BOTH are required, matching the Flutter sheet: the photo is what a
    // coordinator triages on, the voice note is the citizen's account of it.
    const noPhoto = images.length === 0;
    const noVoice = !recorder.audioBlob;
    if (noPhoto || noVoice) {
      setError(
        noPhoto && noVoice ? "Add both a photo and a voice note to submit."
        : noPhoto ? "Add a photo — a voice note alone is not enough."
        : "Record a voice note — a photo alone is not enough."
      );
      bumpReset();
      return;
    }

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
        <div className="absolute inset-0 z-[600] flex flex-col justify-end">
          {/* Scrim */}
          <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={handleClose} />

          {/* Layer 1 — flat navy outer, only the top corners rounded so it
              reads as a bottom-attached sheet, not a floating card. The tall
              bottom padding clears the nav pill, which renders ABOVE this
              (z-700 vs z-600) so its "+" can stay live as the ✕ close. */}
          <div className="animate-sheet-up relative z-10 w-full rounded-t-[28px] bg-brand px-3.5 pb-24 pt-2.5 shadow-[0_-18px_60px_-12px_rgba(15,23,42,0.55)]">
            {/* Grip */}
            <div className="mx-auto h-1 w-[42px] rounded-full bg-white/30" />

            {/* Layer 2 — lighter inner container wrapping the two tiles. */}
            <div className="mt-4 rounded-[30px] bg-[#234874] p-2">
              <div className="grid grid-cols-2 gap-2">
                {/* ── Photo tile ── */}
                <button
                  type="button"
                  onClick={() => cameraInputRef.current?.click()}
                  className="flex h-[82px] items-center gap-1 rounded-3xl bg-white pl-2 pr-1 py-2.5 text-left transition active:scale-[0.99]"
                >
                  {images.length > 0 ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={images[0].url} alt="" className="h-11 w-11 shrink-0 rounded-xl object-cover" />
                  ) : (
                    <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-slate-100 text-brand">
                      <Camera size={22} />
                    </span>
                  )}
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[12.5px] font-extrabold leading-tight text-slate-900">
                      {images.length > 0 ? "Photo added" : "Upload Photo"}
                    </span>
                    <span className="mt-0.5 block text-[11.5px] leading-snug text-slate-500">
                      {images.length > 0 ? "Tap to add another" : "Camera or gallery"}
                    </span>
                  </span>
                  {images.length > 0 && (
                    <span
                      role="button"
                      tabIndex={0}
                      aria-label="Remove photo"
                      onClick={(e) => { e.stopPropagation(); removeImage(images[0].id); }}
                      onKeyDown={(e) => { if (e.key === "Enter") { e.stopPropagation(); removeImage(images[0].id); } }}
                      className="shrink-0 text-slate-400 hover:text-rose-500"
                    >
                      <Trash2 size={15} />
                    </span>
                  )}
                </button>

                {/* ── Voice tile ── */}
                <button
                  type="button"
                  onClick={recorder.isRecording ? recorder.stop : (recorder.audioUrl ? undefined : recorder.start)}
                  className="flex h-[82px] items-center gap-1 rounded-3xl bg-white pl-2 pr-1 py-2.5 text-left transition active:scale-[0.99]"
                >
                  <span
                    onClick={(e) => { if (recorder.audioUrl && !recorder.isRecording) { e.stopPropagation(); togglePlay(); } }}
                    className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${
                      recorder.isRecording ? "recording-pulse bg-rose-500 text-white" : "bg-slate-100 text-brand"
                    }`}
                  >
                    {recorder.isRecording ? <Square size={18} className="fill-current" />
                      : recorder.audioUrl ? (playing ? <Pause size={20} /> : <Play size={20} className="ml-0.5" />)
                      : <Mic size={22} />}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[12.5px] font-extrabold leading-tight text-slate-900">
                      {recorder.isRecording ? "Recording…" : recorder.audioUrl ? "Voice note" : "Record Voice"}
                    </span>
                    <span className="mt-0.5 block font-mono text-[11.5px] leading-snug text-slate-500">
                      {recorder.isRecording ? `${mm}:${ss} · Tap to stop`
                        : recorder.audioUrl ? `${mm}:${ss}`
                        : "Describe the issue"}
                    </span>
                  </span>
                  {recorder.audioUrl && !recorder.isRecording && (
                    <span
                      role="button"
                      tabIndex={0}
                      aria-label="Delete recording"
                      onClick={(e) => { e.stopPropagation(); setPlaying(false); recorder.reset(); }}
                      onKeyDown={(e) => { if (e.key === "Enter") { e.stopPropagation(); recorder.reset(); } }}
                      className="shrink-0 text-slate-400 hover:text-rose-500"
                    >
                      <Trash2 size={15} />
                    </span>
                  )}
                </button>
              </div>
            </div>

            <input ref={cameraInputRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickImage} />
            {recorder.audioUrl && (
              <audio ref={audioRef} src={recorder.audioUrl} onEnded={() => setPlaying(false)} className="hidden" />
            )}

            {(error || recorder.error) && (
              <p className="mt-2.5 text-center text-xs text-[#FFB4B4]">{error || recorder.error}</p>
            )}

            {/* Fair-use policy row — aligned with the tiles above. */}
            <div className="mt-4 flex items-center justify-center gap-2">
              <ShieldCheck size={16} className="shrink-0 text-white/[0.66]" />
              <p className="truncate text-[13px] text-white/80">
                Fair use policy: you can report {limit.max} grievance per day
              </p>
            </div>

            {/* Swipe to submit — inert until BOTH attachments exist. */}
            <div className="mt-4">
              <SwipeToConfirm
                label={canSubmit ? "Swipe to submit grievance" : "Add a photo and a voice note"}
                busyLabel="Submitting…"
                onConfirm={submit}
                busy={submitting}
                disabled={!canSubmit}
                resetToken={resetToken}
                height={62}
                knobWidth={84}
                radius={22}
                uppercase
                trackStyle={{ background: "#ffffff" }}
                knobStyle={{ background: "#ffffff", color: "#1A3556", boxShadow: "0 2px 8px rgba(15,23,42,0.12)" }}
                labelColor="#8B90A0"
                fillStyle={{ background: "rgba(26,53,86,0.08)" }}
              />
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
