"use client";

/**
 * AdminHeatMap
 * ------------
 * Dependency-free density "heatmap" for the authority dashboard. Grievances are
 * aggregated **per ward** (one warm blob per ward), so the layer stays fast even
 * with thousands of reports while still reading as a density map. Overlapping/
 * adjacent ward blobs accumulate opacity, so hotspots glow.
 *
 *   mode="upvotes"   → weight each ward by its total upvotes (demand intensity)
 *   mode="complaints"→ weight each ward by its complaint count (raw density)
 */

import { useEffect, useMemo, useState } from "react";
import { MapContainer, TileLayer, CircleMarker, Tooltip, useMap, useMapEvents } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import BoundaryLayer from "@/components/BoundaryLayer";

function Recenter({ center }) {
  const map = useMap();
  useEffect(() => { if (center) map.setView(center, map.getZoom()); }, [center, map]);
  return null;
}

// Traffic-light density scale: low → green, medium → orange, high → red.
function heatColor(t) {
  if (t < 0.34) return "#16a34a"; // green — low density
  if (t < 0.67) return "#f59e0b"; // orange — medium
  return "#dc2626";               // red — high density
}

/**
 * Crisp per-ward density dots. Instead of soft stacked blobs (which bloom into
 * a cloudy cluster when zoomed out), each ward is one clean dot whose size is
 * clamped: it shrinks as you zoom out and stops shrinking at a floor, so the
 * dots stay distinct and never overlap into a smear.
 */
function DensityDots({ points, mode }) {
  const map = useMap();
  const [zoom, setZoom] = useState(map.getZoom());
  useMapEvents({ zoomend: () => setZoom(map.getZoom()) });

  // zoom 11 → 0.5 (small dots, no overlap) … zoom 15+ → 1 (full size). Clamped.
  const zScale = Math.max(0.5, Math.min(1, (zoom - 11) / 4));

  return points.map((p) => {
    const r = Math.max(4.5, Math.min(18, (7 + p.t * 11) * zScale));
    return (
      <CircleMarker
        key={p.key}
        center={[p.lat, p.lng]}
        radius={r}
        pathOptions={{ color: "#ffffff", weight: 1.5, fillColor: heatColor(p.t), fillOpacity: 0.9 }}
      >
        <Tooltip direction="top" offset={[0, -4]}>
          <span className="text-xs font-semibold">
            Ward {p.ward ?? "—"}{p.zone ? ` · Zone ${p.zone}` : ""}
          </span>
          <br />
          {mode === "upvotes" ? `${p.upvotes} total upvotes` : `${p.count} complaints`}
        </Tooltip>
      </CircleMarker>
    );
  });
}

/**
 * StatusOverlay — when a KPI filter is active, plot each matching grievance at
 * its own coordinate as a coloured dot (matching the KPI's font colour) instead
 * of the aggregated density blobs.
 */
function StatusOverlay({ issues, color }) {
  const map = useMap();
  const [zoom, setZoom] = useState(map.getZoom());
  useMapEvents({ zoomend: () => setZoom(map.getZoom()) });
  const zScale = Math.max(0.5, Math.min(1, (zoom - 11) / 4));
  const r = Math.max(3.5, Math.min(9, 6 * zScale));

  return issues.map((i, idx) => (
    <CircleMarker
      key={i.id || idx}
      center={[i.latitude, i.longitude]}
      radius={r}
      pathOptions={{ color: "#ffffff", weight: 1, fillColor: color, fillOpacity: 0.82 }}
    >
      <Tooltip direction="top" offset={[0, -4]}>
        <span className="text-xs font-semibold">{i.title || "Grievance"}</span>
        <br />
        Ward {i.ward_no ?? "—"}{i.zone ? ` · Zone ${i.zone}` : ""}
      </Tooltip>
    </CircleMarker>
  ));
}

export default function AdminHeatMap({
  issues, mode = "complaints", center, boundaries = null,
  highlightZone = null, highlightWard = null, overlay = null,
}) {
  const centerArr = useMemo(
    () => (center ? [center.lat, center.lng] : [13.0827, 80.2081]),
    [center]
  );

  // Aggregate by real ward → one weighted blob per ward (keeps the layer light).
  const points = useMemo(() => {
    const byWard = new Map();
    for (const i of issues) {
      if (i.latitude == null || i.longitude == null) continue;
      const key = i.ward_no ?? `${i.latitude},${i.longitude}`;
      const e = byWard.get(key) || { key, ward: i.ward_no, zone: i.zone, sumLat: 0, sumLng: 0, count: 0, upvotes: 0 };
      e.sumLat += i.latitude;
      e.sumLng += i.longitude;
      e.count += 1;
      e.upvotes += i.upvotes || 0;
      byWard.set(key, e);
    }
    const arr = [...byWard.values()].map(e => ({
      key: e.key,
      ward: e.ward,
      zone: e.zone,
      lat: e.sumLat / e.count,
      lng: e.sumLng / e.count,
      count: e.count,
      upvotes: e.upvotes,
      w: mode === "upvotes" ? e.upvotes : e.count,
    }));
    const max = Math.max(1, ...arr.map(p => p.w));
    return arr.map(p => ({ ...p, t: p.w / max }));
  }, [issues, mode]);

  return (
    <MapContainer center={centerArr} zoom={12} scrollWheelZoom className="h-full w-full">
      <TileLayer
        attribution='&copy; OpenStreetMap'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Recenter center={centerArr} />
      <BoundaryLayer data={boundaries} highlightZone={highlightZone} highlightWard={highlightWard} />
      {overlay
        ? <StatusOverlay issues={overlay.issues} color={overlay.color} />
        : <DensityDots points={points} mode={mode} />}
    </MapContainer>
  );
}
