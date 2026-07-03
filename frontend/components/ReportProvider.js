"use client";

/**
 * ReportProvider
 * --------------
 * App-wide state for the Report pop-up. The [+] button in the pill nav opens it
 * from any section; MobileShell renders the actual <ReportModal> so it lives
 * inside the phone frame's stacking context (nav stays clickable above it).
 */

import { createContext, useContext, useState, useCallback } from "react";

const ReportContext = createContext(null);

export function useReport() {
  return useContext(ReportContext) || { open: false, openReport() {}, closeReport() {}, toggleReport() {} };
}

export default function ReportProvider({ children }) {
  const [open, setOpen] = useState(false);
  const openReport  = useCallback(() => setOpen(true), []);
  const closeReport = useCallback(() => setOpen(false), []);
  const toggleReport = useCallback(() => setOpen(o => !o), []);
  return (
    <ReportContext.Provider value={{ open, openReport, closeReport, toggleReport }}>
      {children}
    </ReportContext.Provider>
  );
}
