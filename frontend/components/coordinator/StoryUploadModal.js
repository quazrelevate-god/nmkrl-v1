"use client";

/**
 * StoryUploadModal
 * ----------------
 * Instagram-style highlight upload for the coordinator. Camera capture OR
 * gallery upload of a single photo, optional caption, publish. The parent is
 * responsible for enforcing the "1 per day" rule via addStory() which returns
 * false when the limit is exhausted.
 */

import { useEffect, useRef, useState } from "react";
import { X, Camera, ImagePlus, Send } from "lucide-react";

export default function StoryUploadModal({ open, onClose, onPublish }) {
  const [preview, setPreview] = useState(null);
  const [caption, setCaption] = useState("");
  const cameraRef = useRef(null);
  const galleryRef = useRef(null);

  useEffect(() => {
    if (!open) {
      setPreview(null);
      setCaption("");
    }
  }, [open]);

  function onPickImage(e) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPreview({ file: f, url: URL.createObjectURL(f) });
  }

  function publish() {
    if (!preview) return;
    onPublish({ image: preview.url, caption: caption.trim() });
    onClose?.();
  }

  if (!open) return null;

  return (
    <div className="absolute inset-0 z-[660] flex items-center justify-center px-4 pb-24 pt-6">
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/45 backdrop-blur-md" onClick={onClose} />
      <div className="animate-modal-float glass-strong no-scrollbar relative z-10 flex max-h-full w-full flex-col overflow-y-auto rounded-[30px] shadow-[0_30px_80px_-20px_rgba(15,23,42,0.55)] ring-1 ring-black/5">
        <div className="mx-auto mb-1 mt-3 h-1 w-10 rounded-full bg-slate-300/80" />
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3">
          <div>
            <h3 className="text-base font-bold text-slate-900">Add highlight</h3>
            <p className="text-xs text-slate-500">One story per day · shows on your feed for 24 h</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-slate-100">
            <X size={18} className="text-slate-400" />
          </button>
        </div>

        <div className="space-y-4 px-5 py-4">
          {preview ? (
            <div className="relative overflow-hidden rounded-2xl">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={preview.url} alt="preview" className="max-h-[360px] w-full object-cover" />
              <button onClick={() => setPreview(null)} className="absolute right-2 top-2 flex h-8 w-8 items-center justify-center rounded-full bg-slate-900/60 text-white">
                <X size={16} />
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              <button onClick={() => cameraRef.current?.click()}
                className="flex flex-col items-center gap-2 rounded-2xl bg-brand-50 py-6 text-brand ring-1 ring-brand/15">
                <Camera size={26} /> <span className="text-xs font-bold">Capture</span>
              </button>
              <button onClick={() => galleryRef.current?.click()}
                className="flex flex-col items-center gap-2 rounded-2xl bg-slate-100 py-6 text-slate-700 ring-1 ring-slate-200">
                <ImagePlus size={26} /> <span className="text-xs font-bold">Gallery</span>
              </button>
              <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={onPickImage} />
              <input ref={galleryRef} type="file" accept="image/*" className="hidden" onChange={onPickImage} />
            </div>
          )}

          <div>
            <label className="mb-1.5 block text-xs font-semibold text-slate-600">Caption (optional)</label>
            <textarea value={caption} onChange={(e) => setCaption(e.target.value)}
              rows={2} placeholder="Say something about this update…"
              className="w-full resize-none rounded-xl border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-brand" />
          </div>

          <button onClick={publish} disabled={!preview}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-bold text-white shadow-lg shadow-brand/30 disabled:opacity-50">
            <Send size={15} /> Publish highlight
          </button>
        </div>
      </div>
    </div>
  );
}
