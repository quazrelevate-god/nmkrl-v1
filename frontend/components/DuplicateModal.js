"use client";

import { AlertTriangle, X, ThumbsUp } from "lucide-react";
import { mediaUrl } from "@/lib/api";
import { statusMeta } from "@/lib/status";

export default function DuplicateModal({ issue, onUpvote, onSubmitAnyway, onClose, busy }) {
  if (!issue) return null;
  const meta = statusMeta(issue.status);

  return (
    <div className="absolute inset-0 z-[600] flex items-end justify-center bg-black/50 p-3">
      <div className="w-full rounded-2xl bg-white p-5 shadow-2xl">
        <div className="mb-3 flex items-start gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-amber-50">
            <AlertTriangle size={22} className="text-amber-600" />
          </div>
          <div className="flex-1">
            <h3 className="text-base font-bold text-slate-900">Duplicate Issue Found</h3>
            <p className="text-sm text-slate-500">
              An issue is already reported here and is under progress. Would you like to
              upvote it to increase priority instead?
            </p>
          </div>
          <button onClick={onClose} disabled={busy}><X size={18} className="text-slate-400" /></button>
        </div>

        {/* Existing issue preview */}
        <div className="mb-4 rounded-xl border border-slate-200 bg-slate-50 p-3">
          <div className="flex gap-3">
            {issue.image_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={mediaUrl(issue.image_url)} alt="existing" className="h-16 w-16 rounded-lg object-cover" />
            ) : (
              <div className="flex h-16 w-16 items-center justify-center rounded-lg bg-slate-200 text-2xl">🛣️</div>
            )}
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-slate-800">{issue.title}</p>
              {issue.area_name && (
                <p className="text-xs text-slate-500">{issue.area_name}</p>
              )}
              <div className="mt-1 flex flex-wrap items-center gap-2 text-xs">
                <span className={`rounded-full px-2 py-0.5 ${meta.badge}`}>{meta.label}</span>
                <span className="flex items-center gap-1 text-slate-500">
                  <ThumbsUp size={11} /> {issue.upvotes}
                </span>
                {issue.distance_m != null && (
                  <span className="text-slate-500">{Math.round(issue.distance_m)} m away</span>
                )}
              </div>
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-2">
          <button
            onClick={onUpvote}
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-brand py-3 text-sm font-semibold text-white disabled:opacity-60"
          >
            <ThumbsUp size={15} /> {busy ? "Working…" : "Upvote & Cancel"}
          </button>
          <button
            onClick={onSubmitAnyway}
            disabled={busy}
            className="w-full rounded-xl border border-slate-300 bg-white py-3 text-sm font-semibold text-slate-700 disabled:opacity-60"
          >
            Submit Anyway
          </button>
        </div>
      </div>
    </div>
  );
}
