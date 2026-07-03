"use client";

/**
 * lib/hooks.js
 * ------------
 * Reusable client hooks:
 *   * useGeolocation - one-shot navigator.geolocation lookup with state.
 *   * useRecorder    - MediaRecorder wrapper producing an audio Blob + timer.
 */

import { useCallback, useEffect, useRef, useState } from "react";

// Fallback location (Anna Nagar, Chennai) when geolocation is denied/unavailable.
export const DEFAULT_LOCATION = { lat: 13.0827, lng: 80.2081, accuracy: null };

async function reverseGeocode(lat, lng) {
  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&zoom=16`,
      { headers: { "User-Agent": "FixMyStreetIndia/1.0 (civic grievance PoC)" } }
    );
    const data = await res.json();
    const a = data.address || {};
    return (
      a.suburb || a.neighbourhood || a.city_district ||
      a.city || a.town || a.village || ""
    );
  } catch {
    return "";
  }
}

export function useGeolocation() {
  const [coords, setCoords] = useState(null);
  const [areaName, setAreaName] = useState("");
  const [status, setStatus] = useState("loading"); // loading|ready|error|fallback
  const [error, setError] = useState(null);

  const locate = useCallback(() => {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setCoords(DEFAULT_LOCATION);
      setAreaName("");
      setStatus("fallback");
      return;
    }
    setStatus("loading");
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const c = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
        };
        setCoords(c);
        setStatus("ready");
        const name = await reverseGeocode(c.lat, c.lng);
        setAreaName(name);
      },
      (err) => {
        // Graceful fallback so the PoC stays usable without GPS permission.
        setError(err.message);
        setCoords(DEFAULT_LOCATION);
        setAreaName("");
        setStatus("fallback");
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    );
  }, []);

  useEffect(() => {
    locate();
  }, [locate]);

  return { coords, areaName, status, error, refresh: locate };
}

export function useRecorder() {
  const [isRecording, setIsRecording] = useState(false);
  const [audioBlob, setAudioBlob] = useState(null);
  const [audioUrl, setAudioUrl] = useState(null);
  const [seconds, setSeconds] = useState(0);
  const [error, setError] = useState(null);

  const mediaRecorderRef = useRef(null);
  const chunksRef = useRef([]);
  const timerRef = useRef(null);
  const streamRef = useRef(null);

  const start = useCallback(async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      chunksRef.current = [];

      // Prefer webm/opus; fall back to whatever the browser supports.
      const mime = MediaRecorder.isTypeSupported("audio/webm")
        ? "audio/webm"
        : "";
      const mr = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      mediaRecorderRef.current = mr;

      mr.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      mr.onstop = () => {
        const blob = new Blob(chunksRef.current, {
          type: mr.mimeType || "audio/webm",
        });
        setAudioBlob(blob);
        setAudioUrl(URL.createObjectURL(blob));
        // Release the mic.
        streamRef.current?.getTracks().forEach((t) => t.stop());
      };

      mr.start();
      setIsRecording(true);
      setSeconds(0);
      timerRef.current = setInterval(() => setSeconds((s) => s + 1), 1000);
    } catch (err) {
      setError(
        "Microphone access denied or unavailable. Please allow mic permission."
      );
    }
  }, []);

  const stop = useCallback(() => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
      clearInterval(timerRef.current);
    }
  }, [isRecording]);

  const reset = useCallback(() => {
    setAudioBlob(null);
    if (audioUrl) URL.revokeObjectURL(audioUrl);
    setAudioUrl(null);
    setSeconds(0);
  }, [audioUrl]);

  useEffect(() => () => clearInterval(timerRef.current), []);

  return { isRecording, audioBlob, audioUrl, seconds, error, start, stop, reset };
}
