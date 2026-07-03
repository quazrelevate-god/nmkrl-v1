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

import { Fragment, useEffect, useMemo } from "react";
import { MapContainer, TileLayer, CircleMarker, Tooltip, useMap } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import WardLayer from "@/components/WardLayer";

function Recenter({ center }) {
  const map = useMap();
  useEffect(() => { if (center) map.setView(center, map.getZoom()); }, [center, map]);
  return null;
}

// Warm gradient stops from low → high intensity.
function heatColor(t) {
  if (t < 0.33) return "#f59e0b";
  if (t < 0.66) return "#dc2626";
  return "#7a1c1c";
}

export default function AdminHeatMap({ issues, mode = "complaints", center, wards = [] }) {
  const centerArr = useMemo(
    () => (center ? [center.lat, center.lng] : [13.0827, 80.2081]),
    [center]
  );

  // Aggregate by ward → one weighted blob per ward (keeps the layer light).
  const points = useMemo(() => {
    const byWard = new Map();
    for (const i of issues) {
      if (i.latitude == null || i.longitude == null) continue;
      const key = i.ward_no ?? `${i.latitude},${i.longitude}`;
      const e = byWard.get(key) || { key, sumLat: 0, sumLng: 0, count: 0, upvotes: 0 };
      e.sumLat += i.latitude;
      e.sumLng += i.longitude;
      e.count += 1;
      e.upvotes += i.upvotes || 0;
      byWard.set(key, e);
    }
    const arr = [...byWard.values()].map(e => ({
      key: e.key,
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
    <MapContainer center={centerArr} zoom={13} scrollWheelZoom className="h-full w-full">
      <TileLayer
        attribution='&copy; OpenStreetMap'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Recenter center={centerArr} />
      <WardLayer wards={wards} />

      {points.map((p) => {
        const color = heatColor(p.t);
        return (
          <Fragment key={p.key}>
            <CircleMarker
              center={[p.lat, p.lng]}
              radius={30 + p.t * 28}
              pathOptions={{ stroke: false, fillColor: color, fillOpacity: 0.14 }}
            />
            <CircleMarker
              center={[p.lat, p.lng]}
              radius={18 + p.t * 16}
              pathOptions={{ stroke: false, fillColor: color, fillOpacity: 0.24 }}
            />
            <CircleMarker
              center={[p.lat, p.lng]}
              radius={8 + p.t * 8}
              pathOptions={{ stroke: false, fillColor: color, fillOpacity: 0.6 }}
            >
              <Tooltip direction="top" offset={[0, -4]}>
                <span className="text-xs font-semibold">Ward {p.key}</span>
                <br />
                {mode === "upvotes" ? `${p.upvotes} total upvotes` : `${p.count} complaints`}
              </Tooltip>
            </CircleMarker>
          </Fragment>
        );
      })}
    </MapContainer>
  );
}
