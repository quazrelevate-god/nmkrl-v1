"use client";

import { useCallback, useState } from "react";
import SplashScreen from "./SplashScreen";

export default function SplashWrapper({ children }) {
  const [showSplash, setShowSplash] = useState(true);
  const handleDone = useCallback(() => setShowSplash(false), []);

  return (
    <>
      {showSplash && <SplashScreen onDone={handleDone} />}
      {children}
    </>
  );
}
