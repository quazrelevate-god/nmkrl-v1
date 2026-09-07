"use client";

/**
 * components/admin/charts.js
 * --------------------------
 * The dashboard's chart vocabulary.
 *
 * Every chart here used to be the same horizontal bar component with a
 * different colour, which made four different questions look like one. Each
 * form below is picked for the job its data actually does:
 *
 *   Trend over time ......... line, two series on ONE axis (same unit)
 *   Stage-to-stage drop ..... funnel, sequential ramp
 *   Part-to-whole ........... donut with the total as the hero figure
 *   Ordered-scale share ..... stacked bar on a sequential ramp
 *   Compare magnitude ....... ranked bars with the leader emphasised
 *   More than ~7 classes .... a table with inline meters, not more colour
 *
 * Palette. Every multi-hue set here was run through the CVD validator rather
 * than eyeballed. The two-series trend (blue/aqua) and the three-slot priority
 * donut (red/yellow/aqua) pass all six checks; both carry a contrast warning
 * against white, which is why every one of them is directly labelled rather
 * than relying on colour alone. The ageing ramp is sequential — one hue,
 * strictly descending luminance — so it is read as an order, not as identity.
 */

import { useState } from "react";

export const VIZ = {
  // Categorical — validated adjacent pairs, fixed order, never cycled.
  series1: "#2a78d6", // blue   — reported
  series2: "#1baf7a", // aqua   — resolved
  // Priority, ordered but conventionally coloured; legend carries the labels.
  high: "#e34948",
  medium: "#eda100",
  low: "#1baf7a",
  // Sequential blue ramp: light → dark, luminance .54 → .30 → .15 → .07.
  ramp: ["#a8c4ea", "#6d97d8", "#3a6cb4", "#1f4b8a"],
  grid: "#eef1f5",
  axis: "#94a3b8",
  ink: "#0f172a",
  muted: "#64748b",
};

/* ── Card shell ───────────────────────────────────────────────────────────
   Flat white with a hairline border — a CRM surface, not a glass panel. The
   charts sit on it, so it must not add colour of its own. */
export function ChartCard({ title, subtitle, right, children, className = "" }) {
  return (
    <div className={`rounded-2xl border border-slate-200 bg-white p-5 shadow-[0_1px_2px_rgba(15,23,42,0.04)] ${className}`}>
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[13px] font-bold tracking-tight text-slate-800">{title}</p>
          {subtitle && <p className="mt-0.5 text-[11px] text-slate-400">{subtitle}</p>}
        </div>
        {right}
      </div>
      {children}
    </div>
  );
}

export function Legend({ items }) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5">
      {items.map((i) => (
        <span key={i.label} className="flex items-center gap-1.5 text-[11px] text-slate-500">
          <span className="h-2 w-2 rounded-full" style={{ background: i.color }} />
          {i.label}
          {i.value != null && <b className="font-bold tabular-nums text-slate-700">{i.value}</b>}
        </span>
      ))}
    </div>
  );
}

function Empty({ children = "No data yet" }) {
  return <p className="py-10 text-center text-xs text-slate-400">{children}</p>;
}

/* ── Trend ────────────────────────────────────────────────────────────────
   Two series, same unit, one axis — never a second y-scale. Hover moves a
   crosshair and reads both values for that day. */
export function TrendChart({ series, height = 190 }) {
  const [hover, setHover] = useState(null);
  const days = series[0]?.points?.length || 0;
  if (!days) return <Empty>No grievances in this window</Empty>;

  const W = 720, H = height, PAD_L = 34, PAD_R = 12, PAD_T = 10, PAD_B = 24;
  const max = Math.max(1, ...series.flatMap((s) => s.points.map((p) => p.value)));
  const niceMax = Math.ceil(max / 4) * 4 || 4;
  const x = (i) => PAD_L + (i / Math.max(1, days - 1)) * (W - PAD_L - PAD_R);
  const y = (v) => PAD_T + (1 - v / niceMax) * (H - PAD_T - PAD_B);
  const ticks = [0, niceMax / 4, niceMax / 2, (niceMax * 3) / 4, niceMax];

  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ height }} role="img"
        onMouseLeave={() => setHover(null)}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PAD_L} x2={W - PAD_R} y1={y(t)} y2={y(t)} stroke={VIZ.grid} strokeWidth="1" />
            <text x={PAD_L - 7} y={y(t)} textAnchor="end" dominantBaseline="central"
              fontSize="10" fill={VIZ.axis}>{t}</text>
          </g>
        ))}

        {series.map((s) => (
          <g key={s.label}>
            {s.fill && (
              <path
                d={`M${x(0)},${y(0)} ${s.points.map((p, i) => `L${x(i)},${y(p.value)}`).join(" ")} L${x(days - 1)},${y(0)} Z`}
                fill={s.color} opacity="0.10" />
            )}
            <path
              d={s.points.map((p, i) => `${i ? "L" : "M"}${x(i)},${y(p.value)}`).join(" ")}
              fill="none" stroke={s.color} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
            {/* Emphasised endpoint — the value the reader actually wants. */}
            <circle cx={x(days - 1)} cy={y(s.points[days - 1].value)} r="4"
              fill={s.color} stroke="#fff" strokeWidth="2" />
          </g>
        ))}

        {hover != null && (
          <line x1={x(hover)} x2={x(hover)} y1={PAD_T} y2={H - PAD_B}
            stroke={VIZ.axis} strokeWidth="1" strokeDasharray="3 3" />
        )}

        {/* Date labels: first, middle, last only — one per day collides. */}
        {[0, Math.floor((days - 1) / 2), days - 1].map((i) => (
          <text key={i} x={x(i)} y={H - 7} textAnchor={i === 0 ? "start" : i === days - 1 ? "end" : "middle"}
            fontSize="10" fill={VIZ.axis}>{series[0].points[i].label}</text>
        ))}

        {/* Hit targets, wider than the marks. */}
        {series[0].points.map((_, i) => (
          <rect key={i} x={x(i) - (W - PAD_L - PAD_R) / days / 2} y={PAD_T}
            width={(W - PAD_L - PAD_R) / days} height={H - PAD_T - PAD_B}
            fill="transparent" onMouseEnter={() => setHover(i)} />
        ))}
      </svg>

      <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
        <Legend items={series.map((s) => ({ label: s.label, color: s.color }))} />
        {hover != null && (
          <span className="rounded-lg bg-slate-900 px-2.5 py-1 text-[11px] font-semibold text-white">
            {series[0].points[hover].label}
            {series.map((s) => (
              <span key={s.label} className="ml-2 tabular-nums">
                {s.label} <b>{s.points[hover].value}</b>
              </span>
            ))}
          </span>
        )}
      </div>
    </div>
  );
}

/* ── Funnel ───────────────────────────────────────────────────────────────
   Stages are ordered and each is a subset of the one before, so the width
   carries the drop-off and the ramp carries the order. */
export function Funnel({ stages }) {
  const top = Math.max(1, stages[0]?.value || 1);
  if (!stages.length) return <Empty />;
  return (
    <div className="space-y-1.5">
      {stages.map((s, i) => {
        const pct = (s.value / top) * 100;
        const keep = i === 0 ? 100 : Math.round((s.value / Math.max(1, stages[i - 1].value)) * 100);
        return (
          <div key={s.label} className="group">
            <div className="mb-1 flex items-baseline justify-between text-[11.5px]">
              <span className="font-semibold text-slate-600">{s.label}</span>
              <span className="tabular-nums text-slate-400">
                <b className="text-slate-800">{s.value}</b>
                {i > 0 && <span className="ml-1.5">{keep}% carried</span>}
              </span>
            </div>
            <div className="h-7 w-full rounded-md bg-slate-50">
              <div className="flex h-7 items-center justify-end rounded-md px-2 transition-[width] duration-500"
                style={{ width: `${Math.max(pct, 3)}%`, background: VIZ.ramp[Math.min(i, VIZ.ramp.length - 1)] }}>
                {pct > 14 && (
                  <span className="text-[10.5px] font-bold tabular-nums text-white">
                    {Math.round(pct)}%
                  </span>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* ── Donut ────────────────────────────────────────────────────────────────
   Part-to-whole with the total as the hero figure in the hole. Three slots,
   validated, and every one directly labelled beside the ring. */
export function Donut({ segments, total, label = "total" }) {
  const size = 132, stroke = 20, r = (size - stroke) / 2, circ = 2 * Math.PI * r;
  const sum = segments.reduce((s, x) => s + x.value, 0) || 1;
  let offset = 0;
  return (
    <div className="flex items-center gap-6">
      <svg width={size} height={size} className="shrink-0 -rotate-90" role="img">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#f1f5f9" strokeWidth={stroke} />
        {segments.map((s) => {
          const len = (s.value / sum) * circ;
          // 2px surface gap between adjacent fills.
          const el = (
            <circle key={s.label} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={s.color}
              strokeWidth={stroke} strokeDasharray={`${Math.max(0, len - 2)} ${circ - len + 2}`}
              strokeDashoffset={-offset} />
          );
          offset += len;
          return el;
        })}
        <g transform={`rotate(90 ${size / 2} ${size / 2})`}>
          <text x="50%" y="46%" textAnchor="middle" dominantBaseline="central"
            fontSize="26" fontWeight="800" fill={VIZ.ink}>{total}</text>
          <text x="50%" y="62%" textAnchor="middle" dominantBaseline="central"
            fontSize="9.5" fill={VIZ.muted} letterSpacing="0.06em">{label.toUpperCase()}</text>
        </g>
      </svg>
      <div className="min-w-0 flex-1 space-y-2.5">
        {segments.map((s) => (
          <div key={s.label} className="flex items-center gap-2.5">
            <span className="h-2.5 w-2.5 shrink-0 rounded-sm" style={{ background: s.color }} />
            <span className="flex-1 truncate text-[12.5px] font-semibold text-slate-700">{s.label}</span>
            <span className="tabular-nums text-[12.5px] font-bold text-slate-800">{s.value}</span>
            <span className="w-9 text-right tabular-nums text-[11px] text-slate-400">
              {Math.round((s.value / sum) * 100)}%
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Stacked share ────────────────────────────────────────────────────────
   An ordered scale (age buckets), so a sequential ramp — darker is older —
   with a 2px surface gap between segments and every band directly labelled. */
export function StackedShare({ segments, caption }) {
  const sum = segments.reduce((s, x) => s + x.value, 0);
  if (!sum) return <Empty>Nothing open right now</Empty>;
  return (
    <div>
      <div className="flex h-9 w-full gap-[2px] overflow-hidden rounded-lg">
        {segments.map((s, i) => s.value > 0 && (
          <div key={s.label} className="flex items-center justify-center first:rounded-l-lg last:rounded-r-lg"
            style={{ width: `${(s.value / sum) * 100}%`, background: VIZ.ramp[i] }}>
            {(s.value / sum) > 0.09 && (
              <span className={`text-[11px] font-bold tabular-nums ${i < 1 ? "text-slate-700" : "text-white"}`}>
                {s.value}
              </span>
            )}
          </div>
        ))}
      </div>
      <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 sm:grid-cols-4">
        {segments.map((s, i) => (
          <span key={s.label} className="flex items-center gap-1.5 text-[11px] text-slate-500">
            <span className="h-2 w-2 rounded-sm" style={{ background: VIZ.ramp[i] }} />
            {s.label}
          </span>
        ))}
      </div>
      {caption && <p className="mt-3 text-[11px] text-slate-400">{caption}</p>}
    </div>
  );
}

/* ── Ranked bars ──────────────────────────────────────────────────────────
   One hue with the leader emphasised, rather than a different colour per row:
   the story is "this one is biggest," which is emphasis, not identity. */
export function RankedBars({ data, empty = "No data", unit = "" }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  if (!data.length) return <Empty>{empty}</Empty>;
  return (
    <div className="space-y-3">
      {data.map((d, i) => (
        <div key={d.label}>
          <div className="mb-1 flex items-baseline justify-between gap-3 text-[12px]">
            <span className="truncate font-semibold text-slate-600">{d.label}</span>
            <span className="shrink-0 tabular-nums font-bold text-slate-800">{d.value}{unit}</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-slate-100">
            <div className="h-full rounded-full transition-[width] duration-500"
              style={{ width: `${(d.value / max) * 100}%`, background: i === 0 ? VIZ.series1 : "#c7d5e8" }} />
          </div>
        </div>
      ))}
    </div>
  );
}

/* ── Ranked table ─────────────────────────────────────────────────────────
   Past ~7 classes a table beats more colour. Inline meters keep it scannable
   without turning every row into its own series. */
export function RankedTable({ rows, headers = ["", "Count", "Share"], empty = "No data" }) {
  const total = rows.reduce((s, r) => s + r.value, 0) || 1;
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (!rows.length) return <Empty>{empty}</Empty>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-[12.5px]">
        <thead>
          <tr className="border-b border-slate-200">
            {headers.map((h, i) => (
              <th key={h || i} className={`pb-2 text-[10px] font-bold uppercase tracking-wider text-slate-400 ${i ? "text-right" : "text-left"}`}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={r.label} className="border-b border-slate-100 last:border-0">
              <td className="py-2 pr-3">
                <div className="flex items-center gap-2.5">
                  <span className="w-4 shrink-0 tabular-nums text-[11px] font-bold text-slate-300">{i + 1}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-semibold text-slate-700">{r.label}</span>
                    <span className="mt-1 block h-1.5 w-full max-w-[180px] overflow-hidden rounded-full bg-slate-100">
                      <span className="block h-full rounded-full"
                        style={{ width: `${(r.value / max) * 100}%`, background: i === 0 ? VIZ.series1 : "#c7d5e8" }} />
                    </span>
                  </span>
                </div>
              </td>
              <td className="py-2 text-right tabular-nums font-bold text-slate-800">{r.value}</td>
              <td className="py-2 text-right tabular-nums text-slate-400">{Math.round((r.value / total) * 100)}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ── Stat tile ────────────────────────────────────────────────────────────
   A single number is a stat tile, not a one-bar bar chart. */
export function StatTile({ label, value, suffix = "", delta, icon: Icon, tone = "text-slate-900" }) {
  const up = typeof delta === "number" && delta > 0;
  const down = typeof delta === "number" && delta < 0;
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-[0_1px_2px_rgba(15,23,42,0.04)]">
      <p className="mb-1.5 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400">
        {Icon && <Icon size={12} />} {label}
      </p>
      <p className={`text-[26px] font-extrabold leading-none tabular-nums ${tone}`}>
        {value}<span className="text-base font-bold text-slate-400">{suffix}</span>
      </p>
      {delta != null && (
        <p className={`mt-1.5 text-[11px] font-semibold tabular-nums ${up ? "text-emerald-600" : down ? "text-rose-600" : "text-slate-400"}`}>
          {up ? "▲" : down ? "▼" : "—"} {Math.abs(delta)}% vs prev. period
        </p>
      )}
    </div>
  );
}
