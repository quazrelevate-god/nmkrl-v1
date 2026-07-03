"use client";

/**
 * CommentThread
 * -------------
 * Glass bottom-sheet with a thread-style (nested) comment layout — connecting
 * lines for replies, per-comment like/reply, and an add-comment composer.
 */

import { useEffect, useRef, useState } from "react";
import { X, Heart, CornerDownRight, Send, MessageCircle } from "lucide-react";

function Comment({ node, depth, liked, onLike, onReply }) {
  const [showReply, setShowReply] = useState(false);
  const [draft, setDraft] = useState("");
  const isLiked = liked[node.id];

  return (
    <div className={depth > 0 ? "relative pl-4" : ""}>
      {depth > 0 && <span className="absolute left-0 top-0 h-full w-px bg-slate-200" />}
      <div className="flex gap-2.5 py-2.5">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={node.avatar} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
        <div className="min-w-0 flex-1">
          <div className="rounded-2xl rounded-tl-sm bg-slate-100/80 px-3 py-2">
            <p className="text-xs font-bold text-slate-800">{node.name}</p>
            <p className="text-sm leading-snug text-slate-700">{node.text}</p>
          </div>
          <div className="mt-1 flex items-center gap-4 pl-1 text-[11px] font-medium text-slate-400">
            <span>{node.time}</span>
            <button onClick={() => onLike(node.id)} className={`flex items-center gap-1 ${isLiked ? "text-red-500" : ""}`}>
              <Heart size={12} className={isLiked ? "fill-red-500" : ""} /> {node.likes + (isLiked ? 1 : 0)}
            </button>
            <button onClick={() => setShowReply(s => !s)} className="flex items-center gap-1 hover:text-slate-600">
              <CornerDownRight size={12} /> Reply
            </button>
          </div>

          {showReply && (
            <div className="mt-2 flex items-center gap-2">
              <input
                value={draft}
                onChange={e => setDraft(e.target.value)}
                onKeyDown={e => { if (e.key === "Enter" && draft.trim()) { onReply(node.id, draft.trim()); setDraft(""); setShowReply(false); } }}
                placeholder={`Reply to ${node.name}…`}
                className="flex-1 rounded-full border border-slate-200 bg-white px-3 py-1.5 text-xs outline-none focus:border-brand"
                autoFocus
              />
              <button
                onClick={() => { if (draft.trim()) { onReply(node.id, draft.trim()); setDraft(""); setShowReply(false); } }}
                className="text-brand"
              ><Send size={15} /></button>
            </div>
          )}

          {node.replies?.length > 0 && (
            <div className="mt-1">
              {node.replies.map(child => (
                <Comment key={child.id} node={child} depth={depth + 1} liked={liked} onLike={onLike} onReply={onReply} />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function CommentThread({ post, onClose }) {
  const [tree, setTree] = useState(post?.comments || []);
  const [liked, setLiked] = useState({});
  const [draft, setDraft] = useState("");
  const rootRef = useRef(null);

  // Lock background scroll while the sheet is open: freeze the feed's scroll
  // container and swallow wheel/touch that isn't inside the comment list, so
  // the page can only scroll again once the sheet is closed.
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const scrollParent = root.closest(".overflow-y-auto");
    const prev = scrollParent?.style.overflow;
    if (scrollParent) scrollParent.style.overflow = "hidden";

    const block = (e) => {
      if (e.target.closest?.("[data-comment-scroll]")) { e.stopPropagation(); return; }
      e.preventDefault();
      e.stopPropagation();
    };
    root.addEventListener("wheel", block, { passive: false });
    root.addEventListener("touchmove", block, { passive: false });
    return () => {
      if (scrollParent) scrollParent.style.overflow = prev || "";
      root.removeEventListener("wheel", block);
      root.removeEventListener("touchmove", block);
    };
  }, []);

  if (!post) return null;

  function likeNode(id) { setLiked(l => ({ ...l, [id]: !l[id] })); }

  function addReply(parentId, text) {
    const reply = { id: `r${Date.now()}`, name: "You", avatar: "https://i.pravatar.cc/120?img=68", time: "now", text, likes: 0, replies: [] };
    const insert = (nodes) => nodes.map(n =>
      n.id === parentId ? { ...n, replies: [...(n.replies || []), reply] } : { ...n, replies: insert(n.replies || []) }
    );
    setTree(t => insert(t));
  }

  function addTop() {
    const t = draft.trim();
    if (!t) return;
    setTree(prev => [...prev, { id: `t${Date.now()}`, name: "You", avatar: "https://i.pravatar.cc/120?img=68", time: "now", text: t, likes: 0, replies: [] }]);
    setDraft("");
  }

  const count = (nodes) => nodes.reduce((s, n) => s + 1 + count(n.replies || []), 0);

  return (
    <div ref={rootRef} className="fixed inset-0 z-[750] flex items-end">
      <div className="animate-scrim-in absolute inset-0 bg-slate-900/50 backdrop-blur-md" onClick={onClose} />
      <div className="animate-sheet-up glass-strong relative z-10 flex max-h-[82%] w-full flex-col rounded-t-3xl">
        <div className="mx-auto mb-1 mt-2.5 h-1 w-10 shrink-0 rounded-full bg-slate-300" />
        <div className="flex shrink-0 items-center justify-between px-4 pb-2">
          <h3 className="flex items-center gap-1.5 text-sm font-bold text-slate-900">
            <MessageCircle size={15} /> {count(tree)} Comments
          </h3>
          <button onClick={onClose} className="rounded-full p-1 text-slate-400 hover:bg-slate-200/60"><X size={18} /></button>
        </div>

        <div data-comment-scroll className="no-scrollbar flex-1 overflow-y-auto px-4">
          {tree.length === 0 ? (
            <p className="py-10 text-center text-sm text-slate-400">No comments yet. Start the conversation.</p>
          ) : (
            tree.map(node => (
              <Comment key={node.id} node={node} depth={0} liked={liked} onLike={likeNode} onReply={addReply} />
            ))
          )}
        </div>

        <div className="flex shrink-0 items-center gap-2 border-t border-white/50 px-3 py-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="https://i.pravatar.cc/120?img=68" alt="" className="h-8 w-8 rounded-full object-cover" />
          <input
            value={draft}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => e.key === "Enter" && addTop()}
            placeholder="Add a comment…"
            className="flex-1 rounded-full border border-slate-200 bg-white/80 px-4 py-2.5 text-sm outline-none focus:border-brand"
          />
          <button onClick={addTop} className="flex h-10 w-10 items-center justify-center rounded-full bg-brand text-white">
            <Send size={16} />
          </button>
        </div>
      </div>
    </div>
  );
}
