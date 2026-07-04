"use client";

/**
 * LiquidBackground
 * ----------------
 * Slow-drifting organic "liquid" gradient blobs that live behind the frosted
 * glass panels to give the admin real refracted depth. The blobs also react
 * subtly to the cursor (parallax) for cursor-responsive depth.
 */

import { useEffect, useRef } from "react";

export default function LiquidBackground() {
  const ref = useRef(null);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const blobs = root.querySelectorAll(".blob");
    let raf = 0;

    const onMove = (e) => {
      const cx = e.clientX / window.innerWidth - 0.5;
      const cy = e.clientY / window.innerHeight - 0.5;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        blobs.forEach((b, i) => {
          const depth = (i + 1) * 14; // deeper blobs move more
          b.style.transform = `translate(${cx * depth}px, ${cy * depth}px)`;
        });
      });
    };

    window.addEventListener("pointermove", onMove);
    return () => { window.removeEventListener("pointermove", onMove); cancelAnimationFrame(raf); };
  }, []);

  return (
    <div ref={ref} className="admin-liquid" aria-hidden>
      <span className="blob blob-a" />
      <span className="blob blob-b" />
      <span className="blob blob-c" />
      <span className="blob blob-d" />
    </div>
  );
}
