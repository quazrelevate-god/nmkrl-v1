"use client";

/**
 * LocationDetector
 * ----------------
 * Resolves the device's current coordinate to its REAL Greater Chennai
 * Corporation zone + ward by calling the backend /api/locate endpoint, which
 * runs a point-in-polygon test against the GCC KML boundaries (replacing the
 * old mock 200-block grid).
 *
 * Pass `coords` ({ lat, lng }) from the parent (e.g. useGeolocation). The
 * component re-locates whenever the coordinate changes and renders a compact
 * maroon glass chip with the detected zone and ward.
 */

import { useEffect, useState } from "react";
import { MapPin, Loader2, Building2, Landmark } from "lucide-react";
import { locateBoundary } from "@/lib/api";

export default function LocationDetector({ coords, className = "", onResolved }) {
  const [loc, setLoc] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!coords) return;
    let cancelled = false;
    setLoading(true);
    setError(false);
    locateBoundary(coords.lat, coords.lng)
      .then((data) => {
        if (cancelled) return;
        setLoc(data);
        onResolved?.(data);
      })
      .catch(() => !cancelled && setError(true))
      .finally(() => !cancelled && setLoading(false));
    return () => { cancelled = true; };
  }, [coords?.lat, coords?.lng]); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <div className={`rounded-xl bg-white/90 px-3 py-1.5 shadow ring-1 ring-slate-200 ${className}`}>
        <span className="text-[10px] font-semibold text-red-500">Zone lookup failed</span>
      </div>
    );
  }

  // Still waiting on coords or the first /api/locate response.
  if (!coords || !loc) {
    return (
      <div className={`rounded-xl bg-white/90 px-3 py-1.5 shadow ring-1 ring-slate-200 ${className}`}>
        <span className="flex items-center gap-1.5 text-[10px] font-semibold text-slate-500">
          <Loader2 size={11} className="animate-spin" /> Detecting zone…
        </span>
      </div>
    );
  }

  // Outside GCC limits.
  if (!loc.inside) {
    return (
      <div className={`rounded-xl bg-white/90 px-3 py-1.5 text-right shadow ring-1 ring-slate-200 ${className}`}>
        <p className="text-[10px] font-bold text-slate-600">Outside GCC limits</p>
        <p className="text-[9px] text-slate-400">No ward boundary here</p>
      </div>
    );
  }

  const primaryAC = loc.detected_constituencies?.[0];
  return (
    <div className={`rounded-xl bg-white/90 px-3 py-1.5 text-right shadow ring-1 ring-brand/20 ${className}`}>
      <p className="flex items-center justify-end gap-1 text-[10px] font-bold text-brand">
        <Building2 size={11} /> Zone {loc.zone}
        {loc.zone_name ? <span className="font-semibold text-slate-600">· {titleCase(loc.zone_name)}</span> : null}
      </p>
      <p className="flex items-center justify-end gap-1 text-[9px] font-medium text-slate-500">
        <MapPin size={9} /> Ward {loc.ward}
      </p>
      {primaryAC && (
        <p className="flex items-center justify-end gap-1 text-[9px] font-semibold text-violet-600">
          <Landmark size={9} /> {shortAC(primaryAC)}
        </p>
      )}
    </div>
  );
}

/** "ANNA NAGAR" → "Anna Nagar" for display. */
function titleCase(s) {
  return String(s)
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** "20 - Anna Nagar" → "Anna Nagar" (drop the numeric AC code). */
function shortAC(s) {
  return String(s).replace(/^\d+\s*-\s*/, "");
}
