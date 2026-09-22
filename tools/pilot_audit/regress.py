"""Pilot audit v1 — backend regression checks (API level, no emulator).

Run against a FRESH scratch backend (Tambaram live, dev OTP on, no Gemini key):
  cd backend && DB_PATH=$D/audit.db UPLOAD_DIR=$D/uploads ALLOW_DEV_OTP=1 \
      APM_SMS_API_KEY= ADMIN_SECRET=x GEMINI_API_KEY= GOOGLE_API_KEY= \
      venv/bin/uvicorn main:app --port 8005
  AUDIT_DIR=$D backend/venv/bin/python tools/pilot_audit/regress.py

Each line is one audit item (see pilot-audit.html) and prints PASS or FAIL.
"""
import itertools
import os
import sqlite3
import threading
import time

import requests

from h import B, HERE, IMG, WARD, Admin, Citizen, Coord

DB = sqlite3.connect(os.path.join(HERE, "audit.db"), timeout=15)
results = []
_phones = itertools.count(1)


def check(item, ok, detail=""):
    results.append((item, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}  {item:4s} {detail}")


def citizen(name="Tester"):
    n = next(_phones)
    return Citizen(f"{name} {n}", f"93{n:08d}")


def q(sql, *a):
    return DB.execute(sql, a).fetchall()


a = Admin()
for n, p, w in [("Arun Kumar", "9100000001", 34), ("Bala Murugan", "9100000002", 34),
                ("Chitra Devi", "9100000003", 35)]:
    a.create_coordinator(n, p, w)
A = Coord("Arun Kumar", "9100000001")
Bc = Coord("Bala Murugan", "9100000002")
C = Coord("Chitra Devi", "9100000003")


def new_report(ward=34, **kw):
    c = citizen()
    r = c.report(ward, **kw)
    assert r.status_code == 200, r.text
    time.sleep(0.3)
    return c, r.json()["id"]


def walkin(ward=36, coord=""):
    return a.post("/issues", data={"title": "Walk-in", "ward": str(ward), "coordinator": coord}).json()["id"]


# H2 — claim race: exactly one winner
_, x = new_report(34)
res = {}
t = [threading.Thread(target=lambda k, c: res.__setitem__(k, c.act(x, "verify")), args=(k, c))
     for k, c in (("A", A), ("B", Bc))]
[th.start() for th in t]; [th.join() for th in t]
codes = sorted(r.status_code for r in res.values())
verifies = q("SELECT COUNT(*) FROM issue_events WHERE issue_id=? AND action='verify'", x)[0][0]
check("H2", codes == [200, 409] and verifies == 1, f"codes={codes} verify_events={verifies}")
loser = [r for r in res.values() if r.status_code == 409]
check("M5", loser and ("Arun Kumar" in loser[0].text or "Bala Murugan" in loser[0].text),
      loser[0].json().get("detail") if loser else "")

# H3 — acting on another office's grievance by id
chennai = q("SELECT id FROM issues WHERE corporation='chennai' AND status='SUBMITTED' LIMIT 1")[0][0]
r1 = A.act(chennai, "verify")
r2 = A.get(f"/api/coordinator/issues/{chennai}/timeline")
check("H3", r1.status_code == 404 and r2.status_code == 404, f"verify={r1.status_code} timeline={r2.status_code}")

# H1 — merged reporter must not receive the other reporter's details
p1, P = new_report(36, dlat=0.002)
p1.post(f"/api/issues/{P}/confirm", data={"phone": p1.phone, "name": p1.name})
p2, K = new_report(36, dlat=0.00205)
A.act(P, "verify")
assert A.act(K, "merge", parent_id=P).status_code == 200
h = p2.history()[0]
check("H1", not h.get("phone") and not h.get("name") and not h.get("created_by"),
      f"name={h.get('name')!r} phone={h.get('phone')!r}")

# H7 — merged report out of feeds, no support, supports moved
feed = requests.get(f"{B}/api/issues/ward/36").json()["issues"]
sup = citizen("Supporter")
up = sup.post(f"/api/issues/{K}/upvote", data={"user_id": "me", "name": sup.name})
cfeed = [i["id"] for i in A.feed()["issues"]]
check("H7", all(i["id"] != K for i in feed) and up.status_code == 409 and K not in cfeed,
      f"in_public={any(i['id']==K for i in feed)} upvote={up.status_code} in_coord_feed={K in cfeed}")

# M4 — merged reporter hears the parent's updates
A.act(P, "close", notes="fixed", photo=True, voice=True)
kinds2 = [n["kind"] for n in p2.notes()["notifications"]]
check("M4", "closed" in kinds2, f"merged reporter notices={kinds2}")

# H6 — no merge into a finished original
_, D1 = new_report(12, dlat=0.003)
A.act(D1, "verify")
A.act(D1, "mark_false", reason="Not a civic issue")
_, D2 = new_report(12, dlat=0.00305)
r = A.act(D2, "merge", parent_id=D1)
check("H6", r.status_code == 409, r.json().get("detail", "")[:80])

# H4 — walk-in closes outright, no notices to "admin"
w = walkin(34, A.user)
A.act(w, "close", notes="done", photo=True, voice=True)
st = q("SELECT status FROM issues WHERE id=?", w)[0][0]
bogus = q("SELECT COUNT(*) FROM notifications WHERE recipient_type='citizen' AND recipient_id='admin'")[0][0]
check("H4", st == "CLOSED" and bogus == 0, f"status={st} notices_to_admin={bogus}")

# H5 — AI failure is a failure, not a pothole
c5, g = new_report(12, title="Street Issue", dlat=0.006)
time.sleep(1.5)
row = q("SELECT title, transcript, processing_error FROM issues WHERE id=?", g)[0]
check("H5", "Pothole" not in row[0] and "Mock" not in (row[1] or "") and "Transcription failed" in (row[2] or ""),
      f"title={row[0]!r} error={row[2]!r}")

# M1 — reassign tells the previous owner
_, m1 = new_report(35, dlat=0.004)
Bc.act(m1, "verify")
a.post(f"/issues/{m1}/assign", data={"coordinator": A.user})
got = q("SELECT COUNT(*) FROM notifications WHERE recipient_id=? AND kind='unassigned' AND issue_id=?", Bc.user, m1)[0][0]
check("M1", got == 1, f"unassigned notices to previous owner={got}")

# M2 — admin assign of an unverified petition verifies it
_, m2 = new_report(35, dlat=-0.004)
a.post(f"/issues/{m2}/assign", data={"coordinator": Bc.user})
tr = Bc.act(m2, "transfer", department="Water")
check("M2", tr.status_code == 200, f"transfer after admin assign={tr.status_code}")

# M3 — unowned in-flight grievance can be claimed
m3 = walkin(36)
a.post(f"/issues/{m3}/forward")
cl = A.act(m3, "verify")
st3 = q("SELECT status, assigned_coordinator FROM issues WHERE id=?", m3)[0]
check("M3", cl.status_code == 200 and st3 == ("FORWARDED", A.user), f"{cl.status_code} {st3}")

# L1 — redirect releases the grievance
_, l1 = new_report(34, dlat=-0.004)
A.act(l1, "verify")
A.act(l1, "redirect", description="Needs another team")
cb = Bc.act(l1, "verify")
check("L1", cb.status_code == 200, f"other coordinator claim after redirect={cb.status_code}")

# M8 — daily limit + idempotent retry
c8 = citizen()
r1 = c8.report(36, dlat=0.007, rid="req-123")
r2 = c8.report(36, dlat=0.007, rid="req-123")
r3 = c8.report(36, dlat=0.0075, rid="req-456")
check("M8", r1.status_code == 200 and r2.status_code == 200 and r2.json()["id"] == r1.json()["id"]
      and r3.status_code == 429, f"first={r1.status_code} retry_same={r2.json().get('id')==r1.json().get('id')} second={r3.status_code}")

# M9 — photo + voice required; unsafe file types neutralised
c9 = citizen()
n1 = c9.report(36, dlat=0.008, audio=False)
f = {"image": ("x.html", b"<script>1</script>", "text/html"), "audio": ("v.m4a", b"\x00" * 64, "audio/mp4")}
n2 = requests.post(f"{B}/api/issues/report", headers=c9.h,
                   data={"user_id": "me", "latitude": WARD[36][0] + 0.008, "longitude": WARD[36][1]}, files=f)
check("M9", n1.status_code == 422 and n2.status_code == 200 and n2.json()["image_url"].endswith(".jpg")
      and n2.json().get("phone") == c9.phone,
      f"no_voice={n1.status_code} html_stored_as={n2.json().get('image_url','')[-5:]} phone_attached={n2.json().get('phone')==c9.phone}")

# M10 + M12 — stale flags; admin proof; rejected proof cleared
c10, m10 = new_report(35, dlat=0.006)
A.act(m10, "verify")
A.act(m10, "escalate", description="urgent")
A.act(m10, "transfer", department="Roads")
esc = q("SELECT escalated_at FROM issues WHERE id=?", m10)[0][0]
A.act(m10, "close", notes="fixed", photo=True, voice=True)
c10.post(f"/api/issues/{m10}/verify", data={"user_id": "me", "response": "REJECTED"})
after_reject = q("SELECT closure_image_url, closed_at FROM issues WHERE id=?", m10)[0]
empty_close = a.post(f"/issues/{m10}/close", data={})
A.act(m10, "close", notes="fixed again", photo=True, voice=True)
c10.post(f"/api/issues/{m10}/verify", data={"user_id": "me", "response": "APPROVED"})
rej = q("SELECT rejected_at, status FROM issues WHERE id=?", m10)[0]
check("M10", esc is None and rej[0] is None and rej[1] == "CLOSED", f"escalated_after_transfer={esc} rejected_at_after_close={rej[0]}")
check("M12", empty_close.status_code == 400 and after_reject == (None, None),
      f"empty_admin_close={empty_close.status_code} after_reject={after_reject}")

# M13 — only the newest phone keeps push
c13 = citizen()
requests.post(f"{B}/api/notifications/register", headers=c13.h,
              json={"token": "T1", "recipient_type": "citizen", "recipient_id": c13.id, "platform": "android"})
c13b = Citizen(c13.name, c13.phone)
requests.post(f"{B}/api/notifications/register", headers=c13b.h,
              json={"token": "T2", "recipient_type": "citizen", "recipient_id": c13b.id, "platform": "android"})
toks = q("SELECT token FROM device_tokens WHERE recipient_id=?", c13.id)
check("M13", [t[0] for t in toks] == ["T2"], f"tokens={toks}")

# M15 — no self-support, no support on finished grievances
own = p1.post(f"/api/issues/{P}/upvote", data={"user_id": "me", "name": p1.name})
fin = sup.post(f"/api/issues/{D1}/upvote", data={"user_id": "me", "name": sup.name})
check("M15", own.status_code == 403 and fin.status_code == 409, f"own={own.status_code} false_grievance={fin.status_code}")

# M17 — a repeat of a transferred grievance is flagged
_, f1 = new_report(12, dlat=-0.003)
A.act(f1, "verify"); A.act(f1, "transfer", department="Sewage")
_, f2 = new_report(12, dlat=-0.00302)
time.sleep(1.5)
dup = q("SELECT possible_duplicate_id FROM issues WHERE id=?", f2)[0][0]
check("M17", dup == f1, f"possible_duplicate_id={'set' if dup else None}")

# L2 — retry keeps routing and does not re-announce
before_n = q("SELECT COUNT(*) FROM notifications WHERE issue_id=? AND kind='new_grievance'", f1)[0][0]
a.post(f"/issues/{f1}/reprocess")
time.sleep(1.5)
after = q("SELECT department FROM issues WHERE id=?", f1)[0][0]
after_n = q("SELECT COUNT(*) FROM notifications WHERE issue_id=? AND kind='new_grievance'", f1)[0][0]
check("L2", after == "Sewage" and after_n == before_n, f"department={after} new_grievance {before_n}->{after_n}")

# H8 — disabling releases work, stops alerts, signs the account out
_, h8 = new_report(35, dlat=0.009)
C.act(h8, "verify")
requests.patch(f"{B}/api/admin/coordinators/{C.user}", headers=a.h, json={"status": "disabled"})
freed = q("SELECT assigned_coordinator FROM issues WHERE id=?", h8)[0][0]
walkin(35)
alerts = q("SELECT COUNT(*) FROM notifications WHERE recipient_id=? AND kind='new_grievance' AND created_at > "
           "(SELECT MAX(created_at) FROM issue_events WHERE action='release')", C.user)[0][0]
me = C.get("/api/coordinator/me")
claim = A.act(h8, "verify")
check("H8", freed == "" and alerts == 0 and me.status_code == 401 and claim.status_code == 200,
      f"released={freed == ''} alerts_after_disable={alerts} session={me.status_code} arun_claims={claim.status_code}")

passed = sum(ok for _, ok in results)
print(f"\n{passed}/{len(results)} passed")
