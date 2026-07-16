"use client";

/**
 * CommentSection
 * --------------
 * Reddit-style comment thread that lives INLINE, as the lower half of the
 * post's enveloping card (never a slide-up sheet, never floating). Collapsed it
 * previews the top threads; "View all" expands it in place — the page keeps
 * scrolling normally, and the section stays glued to its post. Threaded replies
 * show a clear vertical connector line. Solid white surface.
 */

import { useState } from "react";
import {
  ArrowBigUp, ArrowBigDown, CornerDownRight, MoreHorizontal, ChevronDown,
  ChevronUp, ListFilter, CheckCircle2, Send,
} from "lucide-react";

/** Role-tag text colours keyed by the comment's roleTint. */
export const ROLE_TINT = {
  resident: "text-emerald-600",
  volunteer: "text-violet-600",
  official: "text-brand",
  reporter: "text-amber-600",
};

const PREVIEW = 2; // top-level threads shown before "View all"

function countAll(nodes = []) {
  return nodes.reduce((s, n) => s + 1 + countAll(n.replies || []), 0);
}

/** Green "Official Update" callout shown under a comment. */
function OfficialUpdate({ data }) {
  return (
    <div className="mt-2 rounded-xl bg-emerald-50 px-3 py-2.5 ring-1 ring-emerald-100">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-1.5 text-[12px] font-bold text-emerald-700">
          <CheckCircle2 size={13} className="fill-emerald-500 text-white" /> Official Update
        </span>
        <span className="text-[11px] text-emerald-600/70">{data.time}</span>
      </div>
      <p className="mt-1 text-[13px] leading-snug text-emerald-900">
        <span className="font-bold">{data.team}:</span> {data.text}
      </p>
    </div>
  );
}

/** One comment node + its nested replies (with a visible thread line). */
function Comment({ node, depth, onReply }) {
  const [voted, setVoted] = useState(0); // -1 down, 0 none, 1 up
  const [replying, setReplying] = useState(false);
  const [draft, setDraft] = useState("");
  const score = node.upvotes + voted;

  function submitReply() {
    const t = draft.trim();
    if (!t) return;
    onReply(node.id, t);
    setDraft("");
    setReplying(false);
  }

  return (
    <div>
      <div className="flex gap-2.5">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={node.avatar} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover ring-2 ring-white" />
        <div className="min-w-0 flex-1">
          {/* identity */}
          <div className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
            <span className="text-[13px] font-bold text-slate-900">{node.name}</span>
            {node.role && (
              <span className={`text-[11px] font-semibold ${ROLE_TINT[node.roleTint] || "text-slate-500"}`}>{node.role}</span>
            )}
            <span className="text-[11px] text-slate-400">· {node.time}</span>
          </div>

          {/* body */}
          <p className="mt-1 text-[13.5px] leading-snug text-slate-700">{node.text}</p>

          {/* official update box */}
          {node.official && <OfficialUpdate data={node.official} />}

          {/* actions */}
          <div className="mt-1.5 flex items-center gap-4 text-[12px] font-semibold text-slate-400">
            <span className="flex items-center gap-1">
              <button
                onClick={() => setVoted((v) => (v === 1 ? 0 : 1))}
                className={voted === 1 ? "text-orange-500" : "hover:text-slate-600"}
                aria-label="Upvote comment"
              >
                <ArrowBigUp size={16} className={voted === 1 ? "fill-orange-500" : ""} />
              </button>
              <span className={`min-w-[16px] text-center ${voted === 1 ? "text-orange-500" : voted === -1 ? "text-indigo-500" : "text-slate-600"}`}>
                {score}
              </span>
              <button
                onClick={() => setVoted((v) => (v === -1 ? 0 : -1))}
                className={voted === -1 ? "text-indigo-500" : "hover:text-slate-600"}
                aria-label="Downvote comment"
              >
                <ArrowBigDown size={16} className={voted === -1 ? "fill-indigo-500" : ""} />
              </button>
            </span>
            <button onClick={() => setReplying((r) => !r)} className="flex items-center gap-1 hover:text-slate-600">
              <CornerDownRight size={13} /> Reply
            </button>
            <button className="hover:text-slate-600"><MoreHorizontal size={15} /></button>
          </div>

          {/* inline reply composer */}
          {replying && (
            <div className="mt-2 flex items-center gap-2">
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") submitReply(); }}
                placeholder={`Reply to ${node.name}…`}
                className="min-w-0 flex-1 rounded-full border border-slate-200 bg-white px-3 py-1.5 text-xs outline-none focus:border-brand"
                autoFocus
              />
              <button onClick={submitReply} className="text-brand" aria-label="Send reply"><Send size={15} /></button>
            </div>
          )}
        </div>
      </div>

      {/* nested replies — clear vertical thread line */}
      {node.replies?.length > 0 && (
        <div className="ml-4 mt-3 space-y-3 border-l-2 border-slate-200 pl-4">
          {node.replies.map((child) => (
            <Comment key={child.id} node={child} depth={depth + 1} onReply={onReply} />
          ))}
        </div>
      )}
    </div>
  );
}

export default function CommentSection({ post, expanded, onToggle }) {
  const [tree, setTree] = useState(post.comments || []);
  const [draft, setDraft] = useState("");

  const total = countAll(tree);
  const shown = expanded ? tree : tree.slice(0, PREVIEW);
  const hiddenCount = total - countAll(shown);

  function mkNode(text) {
    return {
      id: `me-${tree.length}-${text.length}-${Math.min(9999, text.charCodeAt(0) || 0)}`,
      name: "You", avatar: "https://i.pravatar.cc/120?img=68", time: "now",
      text, role: "You", roleTint: "resident", upvotes: 0, official: null, replies: [],
    };
  }
  function addReply(parentId, text) {
    const reply = mkNode(text);
    const insert = (nodes) => nodes.map((n) =>
      n.id === parentId ? { ...n, replies: [...(n.replies || []), reply] } : { ...n, replies: insert(n.replies || []) }
    );
    setTree((t) => insert(t));
  }
  function addTop() {
    const t = draft.trim();
    if (!t) return;
    setTree((prev) => [...prev, mkNode(t)]);
    setDraft("");
  }

  if (total === 0) return null;

  return (
    <section className="mt-1.5 rounded-[21px] bg-white p-3.5 shadow-[0_3px_14px_-6px_rgba(15,23,42,0.14)]">
      {/* header */}
      <div className="mb-3 flex items-center justify-between px-1">
        <h4 className="text-[15px] font-extrabold text-slate-900">{total} Comments</h4>
        <div className="flex items-center gap-2">
          <button className="flex items-center gap-1 rounded-lg px-2 py-1 text-[12px] font-bold text-slate-500 hover:bg-slate-100">
            Top <ChevronDown size={13} />
          </button>
          <button className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-100" aria-label="Filter comments">
            <ListFilter size={15} />
          </button>
        </div>
      </div>

      {/* threads */}
      <div className="space-y-4">
        {shown.map((node) => (
          <Comment key={node.id} node={node} depth={0} onReply={addReply} />
        ))}
      </div>

      {/* expand / collapse */}
      {(hiddenCount > 0 || expanded) && (
        <button
          onClick={onToggle}
          className="mt-3 flex w-full items-center justify-center gap-1 rounded-xl bg-slate-50 py-2.5 text-[13px] font-bold text-brand ring-1 ring-slate-100 hover:bg-slate-100"
        >
          {expanded
            ? <>Show less <ChevronUp size={14} /></>
            : <>View all {total} comments <ChevronDown size={14} /></>}
        </button>
      )}

      {/* inline composer — only when the thread is fully open */}
      {expanded && (
        <div className="mt-3 flex items-center gap-2 border-t border-slate-100 pt-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="https://i.pravatar.cc/120?img=68" alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") addTop(); }}
            placeholder="Add a comment…"
            className="min-w-0 flex-1 rounded-full border border-slate-200 bg-white px-4 py-2 text-sm outline-none focus:border-brand"
          />
          <button onClick={addTop} className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand text-white" aria-label="Post comment">
            <Send size={15} />
          </button>
        </div>
      )}
    </section>
  );
}
