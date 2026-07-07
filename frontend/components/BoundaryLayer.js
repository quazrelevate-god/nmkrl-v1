"use client";

/**
 * BoundaryLayer
 * -------------
 * Draws the REAL Greater Chennai Corporation boundaries on a Leaflet map from
 * the GeoJSON served by /api/boundaries (replacing the old mock 200-rectangle
 * grid). Zones are bold coloured outlines; wards are thin outlines with a light
 * zone-tinted fill so the zone structure reads at a glance.
 *
 * Props:
 *   data          { zones, wards } GeoJSON FeatureCollections
 *   highlightWard ward number to emphasise (citizen's current ward)
 *   highlightZone zone roman numeral to emphasise (admin zone filter)
 *   showWards / showZones  toggle each layer
 */

import { useMemo } from "react";
import { GeoJSON } from "react-leaflet";

/** Stable-ish distinct colour per zone, derived from its name. */
function zoneColor(zone) {
  if (!zone) return "#94a3b8";
  let h = 0;
  for (let i = 0; i < zone.length; i++) h = (h * 31 + zone.charCodeAt(i)) % 360;
  return `hsl(${h}, 65%, 45%)`;
}

export default function BoundaryLayer({
  data,
  highlightWard = null,
  highlightZone = null,
  showWards = true,
  showZones = true,
}) {
  const hw = highlightWard != null ? String(highlightWard) : null;

  // Remount the ward layer when the highlight/filter changes so styles refresh.
  const wardKey = `w-${hw}-${highlightZone}`;

  const wardStyle = useMemo(
    () => (feature) => {
      const p = feature.properties;
      const isHi = hw != null && String(p.ward) === hw;
      const inZone = highlightZone && p.zone === highlightZone;
      const base = zoneColor(p.zone);
      if (isHi) {
        return { color: "#3f6a7d", weight: 2.5, fillColor: "#3f6a7d", fillOpacity: 0.22, opacity: 1 };
      }
      return {
        color: base,
        weight: 0.7,
        opacity: highlightZone ? (inZone ? 0.9 : 0.15) : 0.5,
        fillColor: base,
        fillOpacity: highlightZone ? (inZone ? 0.18 : 0.02) : 0.07,
      };
    },
    [hw, highlightZone]
  );

  const zoneStyle = useMemo(
    () => (feature) => {
      const p = feature.properties;
      const isHi = highlightZone && p.zone === highlightZone;
      return {
        color: zoneColor(p.zone),
        weight: isHi ? 3.5 : 2,
        opacity: highlightZone ? (isHi ? 1 : 0.25) : 0.8,
        fill: false,
      };
    },
    [highlightZone]
  );

  function onEachWard(feature, layer) {
    const p = feature.properties;
    layer.bindTooltip(
      `Ward ${p.ward}${p.zone ? ` · Zone ${p.zone}` : ""}`,
      { sticky: true, direction: "top" }
    );
  }

  function onEachZone(feature, layer) {
    const p = feature.properties;
    layer.bindTooltip(
      `Zone ${p.zone}${p.zone_name ? ` · ${p.zone_name}` : ""}`,
      { sticky: true, direction: "top", className: "font-semibold" }
    );
  }

  if (!data) return null;

  return (
    <>
      {showWards && data.wards && (
        <GeoJSON key={wardKey} data={data.wards} style={wardStyle} onEachFeature={onEachWard} />
      )}
      {showZones && data.zones && (
        <GeoJSON key={`z-${highlightZone}`} data={data.zones} style={zoneStyle} onEachFeature={onEachZone} interactive={false} />
      )}
    </>
  );
}
