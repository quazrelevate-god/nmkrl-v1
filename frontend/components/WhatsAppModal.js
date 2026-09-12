"use client";

/**
 * WhatsAppModal
 * -------------
 * Dispatches a grievance to the routed responsible officer on WhatsApp.
 *
 * This used to be a mock: "Send" set a flag and nothing left the browser, even
 * though the routing chain had already resolved a named officer and the admin
 * console held their number. It opens that officer's chat now, with the
 * message pre-typed, and tells the caller so the ticket can move to Forwarded
 * — sending IS forwarding, which is why there is no longer a second button
 * claiming to do it.
 *
 * With no number on file it falls back to WhatsApp's share sheet, the same
 * behaviour the coordinator app has, rather than pretending it dispatched.
 */

import { useState } from "react";
import { X, Send, Check, MapPin, CalendarClock } from "lucide-react";
import { departmentMeta, slaDeadline } from "@/lib/departments";
import { ticketNumber } from "@/lib/ticket";

export default function WhatsAppModal({ issue, officer, contact, onDispatched, onClose }) {
  const [sent, setSent] = useState(false);
  if (!issue) return null;

  const mobile = (contact?.mobile || "").replace(/\D/g, "");
  const officerName = contact?.name || officer || "";

  const dept = issue.department || "Unassigned";
  const meta = departmentMeta(dept);
  const deadline = slaDeadline(issue.created_at, dept).toLocaleDateString("en-IN", {
    day: "numeric", month: "short", year: "numeric",
  });
  const highlights = (issue.summary_highlights || []).join(", ");
  const loc = issue.area_name
    ? `${issue.area_name} (${issue.latitude?.toFixed(5)}, ${issue.longitude?.toFixed(5)})`
    : `${issue.latitude?.toFixed(5)}, ${issue.longitude?.toFixed(5)}`;

  const message =
`🏛️ *FixMyStreet Grievance Dispatch*

*Ticket:* ${ticketNumber(issue.id)}
*Ward No:* ${issue.ward_no ?? "—"}
*Issue:* ${issue.title}
*Details:* ${issue.transcript || highlights || "—"}
*Location:* ${loc}
*Reported:* ${new Date(issue.created_at).toLocaleDateString("en-IN")}
*SLA Deadline:* ${deadline}${officerName ? `\n*Responsible officer:* ${officerName}` : ""}

Kindly action this grievance before the SLA deadline.`;

  function dispatch() {
    // Stored numbers are local 10-digit; prefix India's country code.
    const e164 = mobile.length === 10 ? `91${mobile}` : mobile;
    const url = e164
      ? `https://wa.me/${e164}?text=${encodeURIComponent(message)}`
      : `https://wa.me/?text=${encodeURIComponent(message)}`;
    window.open(url, "_blank", "noopener,noreferrer");
    setSent(true);
    onDispatched?.();
  }

  return (
    <div className="fixed inset-0 z-[700] flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-2xl" onClick={(e) => e.stopPropagation()}>
        {/* WhatsApp-style header */}
        <div className="flex items-center justify-between bg-[#075E54] px-4 py-3 text-white">
          <div className="flex items-center gap-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#25D366] text-base font-bold">W</div>
            <div>
              <p className="text-sm font-bold leading-tight">{meta.short} Dept.</p>
              <p className="text-[11px] text-emerald-100">{meta.phone}</p>
            </div>
          </div>
          <button onClick={onClose} className="rounded-full p-1 hover:bg-white/10">
            <X size={18} />
          </button>
        </div>

        {/* Upcoming-feature notice */}
        <div className="bg-amber-50 px-4 py-1.5 text-center text-[11px] font-medium text-amber-700">
          {mobile ? `Dispatching to +91 ${mobile}` : "No number configured for this officer"}
        </div>

        {/* Chat surface */}
        <div className="space-y-2 bg-[#ECE5DD] px-4 py-4" style={{ minHeight: 200 }}>
          <div className="ml-auto max-w-[90%] rounded-xl rounded-tr-none bg-[#DCF8C6] p-3 shadow-sm">
            <pre className="whitespace-pre-wrap font-sans text-[12px] leading-snug text-slate-800">{message}</pre>
            <div className="mt-1 flex items-center justify-end gap-2 text-[10px] text-slate-500">
              <span className="flex items-center gap-0.5"><MapPin size={9} /> Ward {issue.ward_no ?? "—"}</span>
              <span className="flex items-center gap-0.5"><CalendarClock size={9} /> SLA {deadline}</span>
              {sent && <Check size={11} className="text-[#34B7F1]" />}
            </div>
          </div>
          {sent && (
            <p className="text-center text-[11px] font-medium text-emerald-700">✓ Message queued for {meta.short} Department (demo)</p>
          )}
        </div>

        {/* Send bar */}
        <div className="flex items-center gap-2 border-t border-slate-200 bg-white px-3 py-2.5">
          <div className="flex-1 truncate rounded-full bg-slate-100 px-4 py-2 text-xs text-slate-500">
            {sent
              ? "Opened in WhatsApp — ticket marked Forwarded."
              : mobile
                ? `To ${officerName || "the officer"} · +91 ${mobile}`
                : "No officer number on file — pick a contact in WhatsApp"}
          </div>
          <button
            onClick={dispatch}
            disabled={sent}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-[#25D366] text-white shadow disabled:opacity-60"
          >
            {sent ? <Check size={18} /> : <Send size={16} />}
          </button>
        </div>
      </div>
    </div>
  );
}
