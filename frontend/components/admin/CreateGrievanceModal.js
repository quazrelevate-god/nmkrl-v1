"use client";

/**
 * CreateGrievanceModal
 * --------------------
 * Log a grievance at the MLA office. Not everyone uses the app — people bring
 * grievances in person — so staff record one here and it enters the same
 * workflow as a citizen report. It is created ACTIVE (the office logging it is
 * the verification) and can be handed straight to a coordinator or left in the
 * ward pool. Location comes from the chosen ward's centroid.
 */

import { useEffect, useMemo, useState } from "react";
import { X, Loader2, UserPlus, Camera } from "lucide-react";
import { adminCreateGrievance, fetchCoordinators } from "@/lib/api";
import { DEPARTMENTS } from "@/lib/departments";
import { constituenciesForWard } from "@/lib/constituencies";

const DEPARTMENT_NAMES = Object.keys(DEPARTMENTS);

export default function CreateGrievanceModal({ boundaries, onClose, onCreated }) {
  // The complete ward list, built here from boundaries so it is never narrowed
  // by whatever zone filter happens to be active on the Tickets page behind it.
  const wardOptions = useMemo(() => {
    const feats = boundaries?.wards?.features || [];
    return feats
      .map((f) => f.properties.ward)
      .filter(Boolean)
      .sort((a, b) => Number(a) - Number(b));
  }, [boundaries]);

  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [ward, setWard] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [department, setDepartment] = useState("");
  const [coordinator, setCoordinator] = useState("");
  const [photo, setPhoto] = useState(null);
  const [preview, setPreview] = useState(null);
  const [coords, setCoords] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    let alive = true;
    fetchCoordinators()
      .then((r) => { if (alive) setCoords(r.coordinators || []); })
      .catch(() => { if (alive) setCoords([]); });
    return () => { alive = false; };
  }, []);

  // Coordinator picker scoped to the chosen ward's constituency (active only).
  const pickCoords = useMemo(() => {
    const active = coords.filter((c) => (c.status || "active") === "active");
    if (!ward) return active;
    const acs = constituenciesForWard(ward);
    const inAc = active.filter((c) => acs.includes(c.constituency));
    return inAc.length ? inAc : active;
  }, [coords, ward]);

  const ready = title.trim() && ward;

  function pickPhoto(e) {
    const f = e.target.files?.[0];
    if (!f) return;
    setPhoto(f);
    setPreview(URL.createObjectURL(f));
  }

  async function submit() {
    setBusy(true); setError(null);
    try {
      const created = await adminCreateGrievance({
        title, description, name, phone, ward, department, coordinator, photo,
      });
      onCreated?.(created);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[800] flex items-center justify-center bg-slate-900/50 p-4" onClick={onClose}>
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-white shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="sticky top-0 flex items-center justify-between border-b border-slate-200 bg-white px-5 py-3.5">
          <div>
            <p className="text-[15px] font-extrabold text-slate-900">New grievance</p>
            <p className="text-[11.5px] text-slate-400">Log a report brought to the MLA office</p>
          </div>
          <button onClick={onClose} className="rounded-full p-1.5 text-slate-400 hover:bg-slate-100"><X size={18} /></button>
        </div>

        <div className="space-y-4 p-5">
          {error && <p className="rounded-lg bg-rose-50 px-3 py-2 text-[12px] font-semibold text-rose-600">{error}</p>}

          {/* Citizen */}
          <div className="grid grid-cols-2 gap-3">
            <Field label="Citizen name">
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Optional" className={inputCls} />
            </Field>
            <Field label="Mobile">
              <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Optional" inputMode="numeric" className={inputCls} />
            </Field>
          </div>

          {/* Ward + department */}
          <div className="grid grid-cols-2 gap-3">
            <Field label="Ward" required>
              <select value={ward} onChange={(e) => { setWard(e.target.value); setCoordinator(""); }} className={inputCls}>
                <option value="">Select ward…</option>
                {wardOptions.map((w) => <option key={w} value={w}>Ward {w}</option>)}
              </select>
            </Field>
            <Field label="Department">
              <select value={department} onChange={(e) => setDepartment(e.target.value)} className={inputCls}>
                <option value="">Not set — route later</option>
                {DEPARTMENT_NAMES.map((d) => <option key={d} value={d}>{d}</option>)}
              </select>
            </Field>
          </div>

          {/* Headline + description */}
          <Field label="Headline" required>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Broken streetlight near the market" className={inputCls} />
          </Field>
          <Field label="Description">
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3}
              placeholder="What the citizen reported, in their words." className={`${inputCls} resize-none`} />
          </Field>

          {/* Assign */}
          <Field label="Assign to coordinator">
            <div className="flex items-center gap-2">
              <UserPlus size={15} className="shrink-0 text-slate-400" />
              <select value={coordinator} onChange={(e) => setCoordinator(e.target.value)} className={inputCls}>
                <option value="">Leave in ward pool (unassigned)</option>
                {pickCoords.map((c) => (
                  <option key={c.username} value={c.username}>{c.name} · @{c.username} · Ward {c.home_ward}</option>
                ))}
              </select>
            </div>
            <p className="mt-1 text-[11px] text-slate-400">
              Unassigned grievances appear in the ward coordinator&apos;s queue to pick up.
            </p>
          </Field>

          {/* Photo */}
          <Field label="Photo">
            <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-dashed border-slate-300 p-3 hover:border-brand">
              <input type="file" accept="image/*" className="hidden" onChange={pickPhoto} />
              {preview ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={preview} alt="" className="h-12 w-12 rounded-lg object-cover ring-1 ring-slate-200" />
              ) : (
                <span className="flex h-12 w-12 items-center justify-center rounded-lg bg-slate-100 text-slate-400"><Camera size={18} /></span>
              )}
              <span className="text-[12.5px] font-semibold text-slate-600">{photo ? photo.name : "Attach a photo (optional)"}</span>
            </label>
          </Field>

          <button
            onClick={submit}
            disabled={!ready || busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-brand to-brand-dark py-3 text-[13.5px] font-bold text-white transition hover:brightness-95 disabled:opacity-45"
          >
            {busy ? <><Loader2 size={16} className="animate-spin" /> Creating…</> : "Create grievance"}
          </button>
          {!ready && <p className="-mt-1 text-center text-[11.5px] text-slate-400">A headline and a ward are required.</p>}
        </div>
      </div>
    </div>
  );
}

const inputCls = "w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-[13px] text-slate-800 outline-none focus:border-brand focus:ring-2 focus:ring-brand/15";

function Field({ label, required, children }) {
  return (
    <div>
      <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-slate-500">
        {label} {required && <span className="text-rose-500">*</span>}
      </p>
      {children}
    </div>
  );
}
