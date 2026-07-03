"use client";

/**
 * WardLayer
 * ---------
 * Draws the 200-block ward grid on a Leaflet map (used by both the citizen map
 * and the admin heatmap). Every block is outlined; numbers are labelled when
 * zoomed in enough (to avoid clutter at city scale). The user's current ward
 * (``highlight``) is always filled + labelled.
 */

import { Fragment, useEffect, useState } from "react";
import { Rectangle, Tooltip, useMap, useMapEvents } from "react-leaflet";

export default function WardLayer({ wards, highlight }) {
  const map = useMap();
  const [zoom, setZoom] = useState(map.getZoom());
  useMapEvents({ zoomend: () => setZoom(map.getZoom()) });
  useEffect(() => { setZoom(map.getZoom()); }, [map]);

  if (!wards?.length) return null;
  const showLabels = zoom >= 14;

  return (
    <>
      {wards.map((w) => {
        const bounds = [[w.lat_min, w.lng_min], [w.lat_max, w.lng_max]];
        const isHi = w.number === highlight;
        const label = isHi || showLabels;
        return (
          <Fragment key={w.number}>
            <Rectangle
              bounds={bounds}
              pathOptions={{
                color: isHi ? "#7c3aed" : "#64748b",
                weight: isHi ? 2 : 0.6,
                opacity: isHi ? 0.9 : 0.4,
                fill: isHi,
                fillColor: "#7c3aed",
                fillOpacity: isHi ? 0.12 : 0,
              }}
              interactive={false}
            >
              {label && (
                <Tooltip permanent direction="center" className={`ward-label ${isHi ? "ward-label--hi" : ""}`}>
                  {w.number}
                </Tooltip>
              )}
            </Rectangle>
          </Fragment>
        );
      })}
    </>
  );
}
