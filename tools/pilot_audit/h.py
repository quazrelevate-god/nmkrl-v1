"""API harness for the pilot audit: talks to the scratch backend like the apps do."""
import json
import os

import requests

B = os.environ.get("B", "http://localhost:8005")
HERE = os.environ.get("AUDIT_DIR") or os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "cast.json")
IMG = os.path.join(HERE, "x.jpg")
if not os.path.exists(IMG):
    with open(IMG, "wb") as f:
        f.write(b"\xff\xd8\xff\xe0fakejpeg")

# Interior points of Tambaram wards (boundaries.ward_centroid).
WARD = {
    34: (12.936774, 80.137363),
    35: (12.944515, 80.139204),
    36: (12.9439, 80.144996),
    12: (12.960248, 80.134565),
}


def show(label, r):
    try:
        body = r.json()
    except Exception:
        body = r.text[:300]
    print(f"  {label}: {r.status_code} {json.dumps(body)[:260] if not isinstance(body, str) else body}")
    return body


class Admin:
    def __init__(self):
        r = requests.post(f"{B}/api/admin/auth/login", data={"username": "admin", "password": "nammakural"})
        self.tok = r.json()["token"]

    @property
    def h(self):
        return {"X-Admin-Token": self.tok}

    def get(self, path, **kw):
        return requests.get(f"{B}/api/admin{path}", headers=self.h, **kw)

    def post(self, path, data=None, files=None, **kw):
        return requests.post(f"{B}/api/admin{path}", headers=self.h, data=data, files=files, **kw)

    def issue(self, iid):
        rows = self.get("/issues").json()["issues"]
        return next((i for i in rows if i["id"] == iid), None)

    def create_coordinator(self, name, phone, ward):
        r = requests.post(f"{B}/api/admin/coordinators", headers=self.h,
                          json={"name": name, "phone": phone, "role": "Ward Coordinator", "home_ward": str(ward)})
        return r.json()


class Citizen:
    def __init__(self, name, phone):
        otp = requests.post(f"{B}/api/auth/request-otp", data={"phone": phone, "name": name}).json().get("dev_otp")
        d = requests.post(f"{B}/api/auth/login", data={"phone": phone, "name": name, "otp": otp}).json()
        self.tok, self.id, self.name, self.phone = d["token"], d["id"], name, phone

    @property
    def h(self):
        return {"X-Session-Token": self.tok}

    def report(self, ward, title="Test grievance", dlat=0.0, dlng=0.0, rid="", audio=True, image=True):
        lat, lng = WARD[ward]
        files = {}
        if image:
            files["image"] = ("photo.jpg", open(IMG, "rb"), "image/jpeg")
        if audio:
            files["audio"] = ("voice.m4a", b"\x00" * 64, "audio/mp4")
        data = {"user_id": "me", "title": title, "latitude": lat + dlat, "longitude": lng + dlng}
        if rid:
            data["client_request_id"] = rid
        return requests.post(f"{B}/api/issues/report", headers=self.h, data=data, files=files or None)

    def history(self):
        return requests.get(f"{B}/api/issues/history/me", headers=self.h).json().get("issues", [])

    def notes(self):
        return requests.get(f"{B}/api/notifications", headers=self.h,
                            params={"recipient_type": "citizen", "recipient_id": self.id, "limit": 50}).json()

    def post(self, path, data=None, files=None):
        return requests.post(f"{B}{path}", headers=self.h, data=data, files=files)

    def get(self, path, **kw):
        return requests.get(f"{B}{path}", headers=self.h, **kw)


class Coord:
    def __init__(self, name, phone):
        otp = requests.post(f"{B}/api/auth/coordinator/request-otp", data={"phone": phone, "name": name}).json().get("dev_otp")
        d = requests.post(f"{B}/api/auth/coordinator/login", data={"phone": phone, "name": name, "otp": otp}).json()
        self.tok, self.user, self.name = d["token"], d["username"], name
        self.ward = d.get("home_ward")

    @property
    def h(self):
        return {"X-Session-Token": self.tok}

    def act(self, iid, action, **fields):
        files = {}
        for k in ("photo", "voice"):
            if fields.pop(k, False):
                files[k] = open(IMG, "rb")
        fields.setdefault("coordinator", self.user)
        return requests.post(f"{B}/api/coordinator/issues/{iid}/{action}", headers=self.h,
                             data=fields, files=files or None)

    def feed(self):
        return requests.get(f"{B}/api/coordinator/constituency", headers=self.h,
                            params={"coordinator": self.user}).json()

    def wardfeed(self, n):
        return requests.get(f"{B}/api/coordinator/ward/{n}", headers=self.h,
                            params={"coordinator": self.user}).json()

    def notes(self):
        return requests.get(f"{B}/api/notifications", headers=self.h,
                            params={"recipient_type": "coordinator", "recipient_id": self.user, "limit": 50}).json()

    def get(self, path, **kw):
        return requests.get(f"{B}{path}", headers=self.h, **kw)


def kinds(notes):
    return [(n["kind"], (n.get("message") or "")[:60]) for n in notes.get("notifications", [])]
