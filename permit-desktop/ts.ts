/* ============================================================
✅ PART A) BACKEND AUTO-START (Tauri sidecar)
===============================================================
Goal:
- Tauri starts your local Node backend automatically
- Frontend calls http://127.0.0.1:47831

We will:
1) Add a "sidecar" config to Tauri
2) Add build scripts so backend compiles and is copied into src-tauri/bin/
3) Add Tauri Rust code that spawns the sidecar at app launch
*/

/* ------------------------------------------------------------
1) Add/Update: src-tauri/tauri.conf.json
------------------------------------------------------------ */

{
  "build": {
    "beforeDevCommand": "npm run dev:all",
    "beforeBuildCommand": "npm run build:all",
    "devUrl": "http://localhost:5173",
    "frontendDist": "../dist"
  },
  "package": {
    "productName": "Permit Package Tracker",
    "version": "0.1.0"
  },
  "tauri": {
    "windows": [
      {
        "title": "Permit Package Tracker",
        "width": 1200,
        "height": 800
      }
    ],
    "bundle": {
      "active": true,
      "targets": "all"
    },
    "allowlist": {
      "shell": {
        "all": false,
        "open": true
      }
    },
    "security": {
      "csp": null
    }
  }
}

/* ------------------------------------------------------------
2) Add scripts in ROOT package.json (frontend root)
------------------------------------------------------------ */

{
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "tauri:dev": "tauri dev",
    "tauri:build": "tauri build",

    "backend:install": "cd backend && npm install",
    "backend:dev": "cd backend && npm run dev",
    "backend:build": "cd backend && npm run build",
    "backend:copy-bin": "node scripts/copy-backend-sidecar.mjs",

    "dev:all": "concurrently -k \"npm run dev\" \"npm run backend:dev\"",
    "build:all": "npm run backend:build && npm run backend:copy-bin && npm run build"
  },
  "devDependencies": {
    "concurrently": "^9.0.0"
  }
}

/* Install concurrently if you don’t have it:
   npm i -D concurrently
*/

/* ------------------------------------------------------------
3) Create: scripts/copy-backend-sidecar.mjs
This copies backend/dist/server.js to src-tauri/bin/
so Tauri can spawn it.
------------------------------------------------------------ */

import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const src = path.join(root, "backend", "dist", "server.js");
const binDir = path.join(root, "src-tauri", "bin");
const dest = path.join(binDir, "permit-backend.js");

if (!fs.existsSync(src)) {
  console.error("Missing backend build output:", src);
  process.exit(1);
}

fs.mkdirSync(binDir, { recursive: true });
fs.copyFileSync(src, dest);

console.log("✅ Copied backend sidecar to:", dest);


/* ------------------------------------------------------------
4) Auto-start sidecar from Rust on app launch:
Update: src-tauri/src/main.rs
------------------------------------------------------------ */

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{Manager};

fn main() {
  tauri::Builder::default()
    .setup(|app| {
      // Spawn node backend sidecar
      // NOTE: this runs a JS file. The user must have "node" available OR
      // you later swap this to a packaged backend binary.
      let handle = app.handle();

      tauri::async_runtime::spawn(async move {
        // In dev, backend runs via npm concurrently (dev:all)
        // In production build, we spawn the sidecar JS with node.
        #[cfg(not(debug_assertions))]
        {
          let sidecar_path = handle
            .path_resolver()
            .resolve_resource("bin/permit-backend.js")
            .expect("failed to resolve backend sidecar");

          let _child = std::process::Command::new("node")
            .arg(sidecar_path)
            .env("PORT", "47831")
            .spawn()
            .expect("failed to start backend sidecar");
        }
      });

      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

/* ============================================================
✅ PART B) BACKEND ENDPOINTS NEEDED for Permit Package Detail Page
===============================================================
Your current backend has upload + export zip + ai chat,
but Permit Detail page needs:
- GET permit package detail
- list docs
- toggle "verifiedComplete"
- mark Ready for Billing / Submit

Add these endpoints to backend/src/server.ts
============================================================ */

//
// 1) Get full permit package detail
//
app.get("/api/permit-packages/:permitPackageId", async (req, res) => {
  const db = getDb();
  const permitPackageId = req.params.permitPackageId;

  const pkg = await db
    .select()
    .from(permitPackages)
    .where((t, { eq }) => eq(t.id, permitPackageId))
    .get();

  if (!pkg) return res.status(404).json({ error: "permitPackage not found" });

  const cust = await db
    .select()
    .from(customers)
    .where((t, { eq }) => eq(t.id, pkg.customerId))
    .get();

  const county = await db
    .select()
    .from(counties)
    .where((t, { eq }) => eq(t.id, pkg.countyId))
    .get();

  const docs = await db
    .select()
    .from(permitDocuments)
    .where((t, { eq }) => eq(t.permitPackageId, pkg.id))
    .all();

  res.json({
    permitPackage: pkg,
    customer: cust ?? null,
    county: county ?? null,
    documents: docs
  });
});

//
// 2) Toggle document verifiedComplete
//
app.patch("/api/documents/:documentId/verify", async (req, res) => {
  const db = getDb();
  const documentId = req.params.documentId;
  const { verifiedComplete } = req.body ?? {};

  if (typeof verifiedComplete !== "boolean") {
    return res.status(400).json({ error: "verifiedComplete must be boolean" });
  }

  // SQLite update via better-sqlite3 raw style is easiest for now
  await db
    .update(permitDocuments)
    .set({ verifiedComplete })
    .where((t, { eq }) => eq(t.id, documentId))
    .run();

  res.json({ ok: true });
});

//
// 3) Mark permit package Ready For Billing
//
app.patch("/api/permit-packages/:permitPackageId/ready-for-billing", async (req, res) => {
  const db = getDb();
  const permitPackageId = req.params.permitPackageId;

  await db
    .update(permitPackages)
    .set({ status: "READY_FOR_BILLING" })
    .where((t, { eq }) => eq(t.id, permitPackageId))
    .run();

  res.json({ ok: true });
});

//
// 4) Submit to Billing
//
app.patch("/api/permit-packages/:permitPackageId/submit-to-billing", async (req, res) => {
  const db = getDb();
  const permitPackageId = req.params.permitPackageId;

  await db
    .update(permitPackages)
    .set({ status: "SUBMITTED_TO_BILLING" })
    .where((t, { eq }) => eq(t.id, permitPackageId))
    .run();

  res.json({ ok: true });
});


/* ============================================================
✅ PART C) React Permit Package Detail Page (Upload + Verify + Export ZIP)
===============================================================
This is a full working page that:
- loads package detail
- uploads docs
- toggles manual verification
- exports ZIP
- triggers ready-for-billing and submit-to-billing

Add: src/app/pages/PermitPackageDetailPage.tsx
============================================================ */

import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";

type PermitPackageStatus = "DRAFT" | "BUILDING" | "READY_FOR_BILLING" | "SUBMITTED_TO_BILLING";

type PermitPackage = {
  id: string;
  customerId: string;
  title: string;
  permitType: string;
  propertyAddress: string;
  countyId: string;
  status: PermitPackageStatus;
};

type Customer = {
  id: string;
  fullName: string;
  email?: string | null;
  phone?: string | null;
  address?: string | null;
};

type County = {
  id: string;
  name: string;
  state: string;
};

type PermitDocument = {
  id: string;
  permitPackageId: string;
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
  verifiedComplete: boolean;
};

type DetailResponse = {
  permitPackage: PermitPackage;
  customer: Customer | null;
  county: County | null;
  documents: PermitDocument[];
};

const API_BASE = "http://127.0.0.1:47831";

async function jsonFetch<T>(url: string, opts?: RequestInit): Promise<T> {
  const res = await fetch(url, opts);
  if (!res.ok) throw new Error(await res.text());
  return (await res.json()) as T;
}

export function PermitPackageDetailPage() {
  const { permitPackageId } = useParams<{ permitPackageId: string }>();

  const [data, setData] = useState<DetailResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const documents = data?.documents ?? [];

  const allDocsVerified = useMemo(() => {
    return documents.length > 0 && documents.every((d) => d.verifiedComplete);
  }, [documents]);

  async function refresh() {
    if (!permitPackageId) return;
    setLoading(true);
    setError(null);
    try {
      const out = await jsonFetch<DetailResponse>(`${API_BASE}/api/permit-packages/${permitPackageId}`);
      setData(out);
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [permitPackageId]);

  async function uploadFile(file: File) {
    if (!permitPackageId) return;
    setUploading(true);
    setError(null);

    try {
      const form = new FormData();
      form.append("file", file);

      // Optionally: form.append("documentRequirementId", "some-id")

      const res = await fetch(`${API_BASE}/api/permit-packages/${permitPackageId}/upload`, {
        method: "POST",
        body: form
      });

      if (!res.ok) throw new Error(await res.text());
      await refresh();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setUploading(false);
    }
  }

  async function toggleVerify(docId: string, verifiedComplete: boolean) {
    setError(null);
    try {
      await jsonFetch(`${API_BASE}/api/documents/${docId}/verify`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ verifiedComplete })
      });
      await refresh();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  }

  function downloadZip() {
    if (!permitPackageId) return;
    // Opens the ZIP stream download
    window.open(`${API_BASE}/api/permit-packages/${permitPackageId}/export-zip`, "_blank");
  }

  async function markReadyForBilling() {
    if (!permitPackageId) return;
    setError(null);
    try {
      await jsonFetch(`${API_BASE}/api/permit-packages/${permitPackageId}/ready-for-billing`, { method: "PATCH" });
      await refresh();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  }

  async function submitToBilling() {
    if (!permitPackageId) return;
    setError(null);
    try {
      await jsonFetch(`${API_BASE}/api/permit-packages/${permitPackageId}/submit-to-billing`, { method: "PATCH" });
      await refresh();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  }

  if (!permitPackageId) {
    return <div className="text-sm text-slate-600">Missing permitPackageId in route.</div>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Permit Package</h1>
          <div className="text-sm text-slate-600">
            Detail • Upload • Verify • Export ZIP • Billing Status
          </div>
        </div>

        <div className="flex gap-2">
          <button className="border rounded px-3 py-2" onClick={refresh} disabled={loading}>
            {loading ? "Refreshing..." : "Refresh"}
          </button>

          <button className="border rounded px-3 py-2" onClick={downloadZip} disabled={!data}>
            Export ZIP
          </button>

          <button
            className="border rounded px-3 py-2"
            onClick={markReadyForBilling}
            disabled={!data || !allDocsVerified}
            title={!allDocsVerified ? "All documents must be verified complete first" : ""}
          >
            Mark Ready for Billing
          </button>

          <button
            className="border rounded px-3 py-2"
            onClick={submitToBilling}
            disabled={!data || data.permitPackage.status !== "READY_FOR_BILLING"}
            title={data?.permitPackage.status !== "READY_FOR_BILLING" ? "Must be Ready for Billing first" : ""}
          >
            Submit to Billing
          </button>
        </div>
      </div>

      {error && <div className="border border-red-300 bg-red-50 text-red-800 p-3 rounded text-sm">{error}</div>}

      {!data ? (
        <div className="border rounded p-4 text-sm text-slate-600">
          {loading ? "Loading..." : "No data loaded."}
        </div>
      ) : (
        <>
          {/* Header / Summary */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="border rounded p-4">
              <div className="text-xs text-slate-500">Customer</div>
              <div className="font-semibold">{data.customer?.fullName ?? "Unknown"}</div>
              <div className="text-sm text-slate-600">{data.customer?.email ?? ""}</div>
              <div className="text-sm text-slate-600">{data.customer?.phone ?? ""}</div>
            </div>

            <div className="border rounded p-4">
              <div className="text-xs text-slate-500">Permit</div>
              <div className="font-semibold">{data.permitPackage.title}</div>
              <div className="text-sm text-slate-600">{data.permitPackage.permitType}</div>
              <div className="text-sm text-slate-600">{data.permitPackage.propertyAddress}</div>
            </div>

            <div className="border rounded p-4">
              <div className="text-xs text-slate-500">Florida County</div>
              <div className="font-semibold">{data.county?.name ?? data.permitPackage.countyId}</div>
              <div className="text-sm text-slate-600">
                Status: <span className="font-medium">{data.permitPackage.status}</span>
              </div>
              <div className="text-sm text-slate-600">
                Verified Complete:{" "}
                <span className={allDocsVerified ? "font-semibold" : "text-slate-500"}>
                  {allDocsVerified ? "YES" : "NO"}
                </span>
              </div>
            </div>
          </div>

          {/* Upload */}
          <div className="border rounded p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="font-semibold">Upload Document</div>
                <div className="text-sm text-slate-600">
                  Upload completed files only. After upload, use manual verification checkbox.
                </div>
              </div>

              <label className="border rounded px-3 py-2 cursor-pointer text-sm">
                {uploading ? "Uploading..." : "Choose File"}
                <input
                  type="file"
                  className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) uploadFile(f);
                  }}
                  disabled={uploading}
                />
              </label>
            </div>
          </div>

          {/* Documents Table */}
          <div className="border rounded p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="font-semibold">Documents</div>
                <div className="text-sm text-slate-600">
                  All docs must be uploaded + verified complete before billing.
                </div>
              </div>
              <div className="text-sm text-slate-500">{documents.length} file(s)</div>
            </div>

            <div className="overflow-auto">
              <table className="w-full text-sm border-collapse">
                <thead>
                  <tr className="text-left border-b">
                    <th className="py-2 pr-2">File</th>
                    <th className="py-2 pr-2">Type</th>
                    <th className="py-2 pr-2">Size</th>
                    <th className="py-2 pr-2">Verified Complete</th>
                  </tr>
                </thead>
                <tbody>
                  {documents.map((d) => (
                    <tr key={d.id} className="border-b last:border-b-0">
                      <td className="py-2 pr-2 font-medium">{d.fileName}</td>
                      <td className="py-2 pr-2 text-slate-600">{d.mimeType}</td>
                      <td className="py-2 pr-2 text-slate-600">{Math.round(d.fileSize / 1024)} KB</td>
                      <td className="py-2 pr-2">
                        <label className="inline-flex items-center gap-2">
                          <input
                            type="checkbox"
                            checked={d.verifiedComplete}
                            onChange={(e) => toggleVerify(d.id, e.target.checked)}
                          />
                          <span className="text-slate-700">
                            {d.verifiedComplete ? "Verified ✅" : "Not Verified"}
                          </span>
                        </label>
                      </td>
                    </tr>
                  ))}

                  {documents.length === 0 && (
                    <tr>
                      <td colSpan={4} className="py-3 text-slate-500">
                        No documents uploaded yet.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          {/* Billing Gate Explanation */}
          <div className="border rounded p-4 text-sm text-slate-700">
            <div className="font-semibold mb-1">Billing Rules</div>
            <ul className="list-disc ml-5 space-y-1">
              <li>All required documents must be uploaded.</li>
              <li>Each document must be manually checked "Verified Complete".</li>
              <li>Then you can mark Ready for Billing, and submit to billing.</li>
            </ul>
          </div>
        </>
      )}
    </div>
  );
}

/* ============================================================
✅ PART D) Add Route + Link It In
===============================================================
1) Add a route to your router:
src/app/routes.tsx
============================================================ */

import { PermitPackageDetailPage } from "./pages/PermitPackageDetailPage";

/* ...inside routes... */
{ path: "permit-packages/:permitPackageId", element: <PermitPackageDetailPage /> }


/* ============================================================
✅ PART E) Quick "Permit Package List" Link (Optional)
===============================================================
Update PermitPackagesPage to show clickable rows if you want:

- fetch /api/permit-packages list (you can add endpoint)
- link to /permit-packages/:id
============================================================ */