"use client";

/**
 * PostComposer
 * ------------
 * The "+" nav button on the coordinator app opens this composer (instead of
 * the citizen ReportModal). Two content types — Post and Poll — each capped
 * at 1 per calendar day.
 *
 * Post: text description with live @mention + #hashtag extraction, optional
 *       photo OR video, current-GPS location OR manual location entry, and a
 *       multi-select target-audience picker.
 * Poll: question + 2–4 options, same location + audience controls.
 *
 * Publish routes through useCoordinator().addPost/addPoll which persists and
 * enforces the daily limit; the item appears at the top of the coordinator's
 * home feed.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import {
  X, Image as ImageIcon, Video, Camera, MapPin, Users, Plus, Trash2, Send,
  MessageSquare, BarChart3, AtSign, Hash, Loader2,
} from "lucide-react";
import { useCoordinator } from "./CoordinatorProvider";
import { shortAC } from "@/lib/constituencies";

const AUDIENCES = [
  "Ward Residents", "Constituency Residents", "All Chennai",
  "Youth (18-35)", "Senior Citizens", "Women's Groups",
  "Local Businesses", "Media & Press",
];

function extractMentionsAndTags(text) {
  const mentions = [...(text.matchAll(/@(\w+)/g) || [])].map((m) => m[1]);
  const hashtags = [...(text.matchAll(/#(\w+)/g) || [])].map((m) => m[1]);
  return { mentions, hashtags };
}

export default function PostComposer({ open, onClose }) {
  const { me, addPost, addPoll, canUploadPost, canUploadPoll } = useCoordinator();

  const [kind, setKind] = useState("post"); // "post" | "poll"
  const [body, setBody] = useState("");
  const [title, setTitle] = useState("");
  const [media, setMedia] = useState(null); // { url, kind: 'image'|'video' }
  const [question, setQuestion] = useState("");
  const [options, setOptions] = useState(["", ""]);

  // Location controls
  const [useGps, setUseGps] = useState(true);
  const [manualLoc, setManualLoc] = useState("");
  const [gpsLoc, setGpsLoc] = useState(null);
  const [locating, setLocating] = useState(false);

  // Audience
  const [audience, setAudience] = useState(["Ward Residents"]);

  const photoRef = useRef(null);
  const videoRef = useRef(null);

  // Reset on close.
  useEffect(() => {
    if (!open) {
      setKind("post"); setBody(""); setTitle(""); setMedia(null);
      setQuestion(""); setOptions(["", ""]);
      setUseGps(true); setManualLoc(""); setGpsLoc(null);
      setAudience(["Ward Residents"]);
    }
  }, [open]);

  // GPS on demand.
  useEffect(() => {
    if (!open || !useGps || gpsLoc || !navigator.geolocation) return;
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords;
        setGpsLoc({ lat: latitude, lng: longitude });
        setLocating(false);
      },
      () => setLocating(false),
      { timeout: 8000 }
    );
  }, [open, useGps, gpsLoc]);

  const { mentions, hashtags } = useMemo(() => extractMentionsAndTags(kind === "post" ? body : question), [kind, body, question]);
  const validOptions = options.map((o) => o.trim()).filter(Boolean);
  const canSubmit = kind === "post"
    ? (canUploadPost && (media || body.trim().length > 4))
    : (canUploadPoll && question.trim().length > 4 && validOptions.length >= 2);

  const locationLabel = useGps
    ? (locating ? "Detecting…" : gpsLoc ? `GPS · ${gpsLoc.lat.toFixed(3)}, ${gpsLoc.lng.toFixed(3)}` : "GPS unavailable")
    : manualLoc.trim() || "Add a location";

  function onPickPhoto(e) {
    const f = e.target.files?.[0]; if (!f) return;
    setMedia({ url: URL.createObjectURL(f), kind: "image" });
  }
  function onPickVideo(e) {
    const f = e.target.files?.[0]; if (!f) return;
    setMedia({ url: URL.createObjectURL(f), kind: "video" });
  }

  function addOption() { if (options.length < 4) setOptions((o) => [...o, ""]); }
  function removeOption(i) { setOptions((o) => o.filter((_, k) => k !== i)); }
  function setOption(i, v) { setOptions((o) => o.map((x, k) => (k === i ? v : x))); }

  function toggleAudience(a) {
    setAudience((cur) => cur.includes(a) ? cur.filter((x) => x !== a) : [...cur, a]);
  }

  function publish() {
    if (!canSubmit) return;
    const location = useGps
      ? (gpsLoc ? `Near ${gpsLoc.lat.toFixed(3)}, ${gpsLoc.lng.toFixed(3)}` : shortAC(me?.constituency || ""))
      : manualLoc.trim();

    if (kind === "post") {
      addPost({
        title: title.trim() || (body.trim().slice(0, 60) || "Update"),
        body: body.trim(),
        media: media?.url || null,
        mediaKind: media?.kind || null,
        location,
        mentions,
        hashtags,
        audience,
      });
    } else {
      addPoll({
        question: question.trim(),
        options: validOptions,
        location,
        audience,
      });
    }
    onClose?.();
  }

  if (!open) return null;

  return (
    <div className="absolute inset-0 z-[660] flex items-center justify-center px-4 pb-24 pt-6">
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />
      <div className="animate-modal-float glass-strong no-scrollbar relative z-10 flex max-h-full w-full flex-col overflow-y-auto rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300/80" />

        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <div>
            <h3 className="text-base font-bold text-slate-900">Create {kind === "post" ? "Post" : "Poll"}</h3>
            <p className="text-xs text-slate-500">
              {kind === "post"
                ? (canUploadPost ? "Publishing to community · 1 post/day" : "Daily post limit reached")
                : (canUploadPoll ? "Publishing to community · 1 poll/day" : "Daily poll limit reached")}
            </p>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100"><X size={18} className="text-slate-400" /></button>
        </div>

        <div className="space-y-4 px-5 py-4">
          {/* Kind toggle */}
          <div className="flex gap-1 rounded-xl bg-slate-100 p-1">
            <button onClick={() => setKind("post")}
              className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${kind === "post" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
              <MessageSquare size={13} /> Post
            </button>
            <button onClick={() => setKind("poll")}
              className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-bold transition ${kind === "poll" ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
              <BarChart3 size={13} /> Poll
            </button>
          </div>

          {/* POST body */}
          {kind === "post" && (
            <>
              <div>
                <label className="mb-1 block text-xs font-semibold text-slate-600">Title (optional)</label>
                <input value={title} onChange={(e) => setTitle(e.target.value)}
                  placeholder="Short headline"
                  className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
              </div>

              {media ? (
                <div className="relative overflow-hidden rounded-2xl">
                  {media.kind === "video" ? (
                    // eslint-disable-next-line jsx-a11y/media-has-caption
                    <video src={media.url} controls className="max-h-[240px] w-full bg-black object-cover" />
                  ) : (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={media.url} alt="preview" className="max-h-[240px] w-full object-cover" />
                  )}
                  <button onClick={() => setMedia(null)} className="absolute right-2 top-2 flex h-8 w-8 items-center justify-center rounded-full bg-slate-900/60 text-white">
                    <X size={16} />
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-3 gap-2">
                  <button onClick={() => photoRef.current?.click()}
                    className="flex flex-col items-center gap-1 rounded-xl bg-brand-50 py-3 text-brand ring-1 ring-brand/15">
                    <ImageIcon size={18} /><span className="text-[11px] font-bold">Photo</span>
                  </button>
                  <button onClick={() => videoRef.current?.click()}
                    className="flex flex-col items-center gap-1 rounded-xl bg-slate-100 py-3 text-slate-600 ring-1 ring-slate-200">
                    <Video size={18} /><span className="text-[11px] font-bold">Video</span>
                  </button>
                  <button onClick={() => photoRef.current?.click()}
                    className="flex flex-col items-center gap-1 rounded-xl bg-slate-100 py-3 text-slate-600 ring-1 ring-slate-200">
                    <Camera size={18} /><span className="text-[11px] font-bold">Capture</span>
                  </button>
                  <input ref={photoRef} type="file" accept="image/*" className="hidden" onChange={onPickPhoto} />
                  <input ref={videoRef} type="file" accept="video/*" className="hidden" onChange={onPickVideo} />
                </div>
              )}

              <div>
                <label className="mb-1 block text-xs font-semibold text-slate-600">Description</label>
                <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={4}
                  placeholder="Share an update… use @mentions and #hashtags"
                  className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
                {(mentions.length > 0 || hashtags.length > 0) && (
                  <div className="mt-1 flex flex-wrap gap-1">
                    {mentions.map((m) => (
                      <span key={`m-${m}`} className="inline-flex items-center gap-0.5 rounded-full bg-brand-50 px-2 py-0.5 text-[10px] font-semibold text-brand ring-1 ring-brand-100">
                        <AtSign size={9} />{m}
                      </span>
                    ))}
                    {hashtags.map((h) => (
                      <span key={`h-${h}`} className="inline-flex items-center gap-0.5 rounded-full bg-teal-50 px-2 py-0.5 text-[10px] font-semibold text-teal-700 ring-1 ring-teal-100">
                        <Hash size={9} />{h}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* POLL body */}
          {kind === "poll" && (
            <>
              <div>
                <label className="mb-1 block text-xs font-semibold text-slate-600">Poll question</label>
                <textarea value={question} onChange={(e) => setQuestion(e.target.value)} rows={2}
                  placeholder="What do residents think about…?"
                  className="w-full resize-none rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-brand" />
              </div>
              <div className="space-y-2">
                <p className="text-xs font-semibold text-slate-600">Options ({options.length}/4)</p>
                {options.map((v, i) => (
                  <div key={i} className="flex items-center gap-2">
                    <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-slate-100 text-[11px] font-bold text-slate-500">{i + 1}</span>
                    <input value={v} onChange={(e) => setOption(i, e.target.value)}
                      placeholder={`Option ${i + 1}`}
                      className="flex-1 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand" />
                    {options.length > 2 && (
                      <button onClick={() => removeOption(i)} className="rounded-md p-1 text-slate-400 hover:bg-slate-100">
                        <Trash2 size={14} />
                      </button>
                    )}
                  </div>
                ))}
                {options.length < 4 && (
                  <button onClick={addOption}
                    className="flex w-full items-center justify-center gap-1.5 rounded-xl border border-dashed border-slate-300 py-2 text-xs font-semibold text-slate-500 hover:bg-slate-50">
                    <Plus size={14} /> Add option
                  </button>
                )}
              </div>
            </>
          )}

          {/* Location */}
          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="mb-2 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
              <MapPin size={12} /> Location
            </p>
            <div className="flex gap-2 rounded-xl bg-slate-100 p-1">
              <button onClick={() => setUseGps(true)}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-[11px] font-bold ${useGps ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
                {locating ? <Loader2 size={12} className="animate-spin" /> : <MapPin size={12} />} Current location
              </button>
              <button onClick={() => setUseGps(false)}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-[11px] font-bold ${!useGps ? "bg-white text-slate-900 shadow-sm" : "text-slate-500"}`}>
                Add manually
              </button>
            </div>
            {!useGps ? (
              <input value={manualLoc} onChange={(e) => setManualLoc(e.target.value)}
                placeholder="e.g. Anna Nagar Tower Park"
                className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none focus:border-brand" />
            ) : (
              <p className="mt-2 text-[11px] text-slate-500">{locationLabel}</p>
            )}
          </div>

          {/* Audience */}
          <div className="rounded-2xl border border-slate-200 bg-white p-3">
            <p className="mb-2 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
              <Users size={12} /> Target audience ({audience.length} selected)
            </p>
            <div className="flex flex-wrap gap-1.5">
              {AUDIENCES.map((a) => {
                const on = audience.includes(a);
                return (
                  <button key={a} onClick={() => toggleAudience(a)}
                    className={`rounded-full px-3 py-1 text-[11px] font-semibold transition ${
                      on ? "bg-brand text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                    }`}>
                    {a}
                  </button>
                );
              })}
            </div>
          </div>

          <button onClick={publish} disabled={!canSubmit}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-50">
            <Send size={15} /> Publish {kind === "post" ? "Post" : "Poll"}
          </button>
        </div>
      </div>
    </div>
  );
}
