"use client";

/**
 * MapView
 * -------
 * react-leaflet map for the Explore screen. Rendered client-only (the parent
 * page imports it with next/dynamic { ssr: false }) because Leaflet touches
 * `window` at import time.
 *
 * - The search radius circle is ANCHORED to the user's device location and
 *   never moves when the map is panned/dragged (deviceCenter prop).
 * - Colored pins per status (open = warning colors, closed = success green).
 * - Clicking a pin selects the issue; the parent renders the bottom sheet.
 */

import { useEffect, useMemo } from "react";
import {
  MapContainer,
  TileLayer,
  Marker,
  CircleMarker,
  useMap,
} from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import BoundaryLayer from "@/components/BoundaryLayer";

// Fix Leaflet's broken default icon detection in webpack/Next.js bundles.
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
});
import { statusMeta } from "@/lib/status";

/** Build a colored teardrop divIcon for a given status. */
function pinIcon(status, highlight = false) {
  const color = statusMeta(status).pin;
  const ring = highlight
    ? '<circle cx="13" cy="13" r="11" fill="none" stroke="#facc15" stroke-width="3"/>'
    : "";
  const html = `
    <div style="position:relative;width:26px;height:34px;">
      <svg width="26" height="34" viewBox="0 0 26 34" xmlns="http://www.w3.org/2000/svg">
        <path d="M13 0C5.8 0 0 5.8 0 13c0 9.2 13 21 13 21s13-11.8 13-21C26 5.8 20.2 0 13 0z" fill="${color}" fill-opacity="0.78" stroke="white" stroke-opacity="0.55" stroke-width="0.75"/>
        <circle cx="13" cy="13" r="5" fill="white" fill-opacity="0.92"/>
        ${ring}
      </svg>
    </div>`;
  return L.divIcon({
    html,
    className: "",
    iconSize: [26, 34],
    iconAnchor: [13, 34],
    popupAnchor: [0, -30],
  });
}

/** Imperatively recenter only when the device location actually changes. */
function Recenter({ center }) {
  const map = useMap();
  useEffect(() => {
    if (center) map.setView(center, map.getZoom());
  }, [center, map]);
  return null;
}

export default function MapView({
  center,        // device GPS location – fixed circle anchor
  issues,
  radius,
  selectedId,
  onSelect,
  boundaries = null,
  currentWard = null,
  scrollWheelZoom = true,
}) {
  const centerArr = useMemo(
    () => (center ? [center.lat, center.lng] : [13.0827, 80.2081]),
    [center]
  );

  return (
    <MapContainer
      center={centerArr}
      zoom={15}
      scrollWheelZoom={scrollWheelZoom}
      className="h-full w-full"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      <Recenter center={centerArr} />

      {/* Real GCC zone + ward boundaries (the ward outline replaces the old
          radius circle — only in-ward grievances are shown). */}
      <BoundaryLayer data={boundaries} highlightWard={currentWard} />

      {/* "You are here" dot */}
      <CircleMarker
        center={centerArr}
        radius={6}
        pathOptions={{ color: "#fff", weight: 2, fillColor: "#1a3556", fillOpacity: 1 }}
      />

      {issues.map((issue) => (
        <Marker
          key={issue.id}
          position={[issue.latitude, issue.longitude]}
          icon={pinIcon(issue.status, issue.id === selectedId)}
          eventHandlers={{ click: () => onSelect(issue) }}
        />
      ))}
    </MapContainer>
  );
}
