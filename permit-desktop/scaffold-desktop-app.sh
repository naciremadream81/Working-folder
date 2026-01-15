#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Permit Package Tracker (Native Desktop) - Tauri + React + TS
# Local-first SQLite + Drizzle + Seeded 67 Florida Counties
# ============================================================
#
# What this scaffolds:
# - Tauri desktop app (Windows/macOS/Linux)
# - React + TypeScript (Vite)
# - SQLite (local) using better-sqlite3
# - Drizzle ORM schema + migrations
# - Seed script that inserts ALL 67 Florida counties
# - Starter UI pages + AI panel stub + ZIP export dependency
#
# Prereqs (recommended):
# - Node.js 18+ (or 20+)
# - Rust toolchain (for Tauri):
#     curl https://sh.rustup.rs -sSf | sh
# - System deps for Tauri (varies by OS)
#
# Run:
#   bash scaffold-permit-package-tracker.sh
#
# Then:
#   cd permit-package-tracker-desktop
#   npm run db:migrate
#   npm run db:seed
#   npm run dev
#   npm run tauri:dev
#
# ============================================================

APP_DIR="permit-package-tracker-desktop"
APP_NAME="Permit Package Tracker"

if [[ -d "$APP_DIR" ]]; then
  echo "ERROR: $APP_DIR already exists. Move/delete it then re-run."
  exit 1
fi

command -v node >/dev/null 2>&1 || { echo "ERROR: node not found."; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not found."; exit 1; }

echo "Creating Vite React+TS app..."
npm create vite@latest "$APP_DIR" -- --template react-ts >/dev/null

cd "$APP_DIR"

echo "Installing dependencies..."
npm install >/dev/null

# App dependencies
npm install \
  @tauri-apps/api \
  better-sqlite3 \
  drizzle-orm \
  zod \
  jszip \
  react-router-dom >/dev/null

# Dev deps
npm install -D \
  @tauri-apps/cli \
  drizzle-kit \
  tsx \
  @types/better-sqlite3 >/dev/null

echo "Initializing Tauri..."
npx tauri init \
  --app-name "$APP_NAME" \
  --window-title "$APP_NAME" \
  --dist-dir ../dist \
  --dev-path http://localhost:5173 >/dev/null

# ------------------------------------------------------------
# Create project structure
# ------------------------------------------------------------
echo "Creating folders..."
mkdir -p \
  src/app \
  src/app/layouts \
  src/app/pages \
  src/app/components \
  src/app/components/ui \
  src/lib \
  src/lib/db \
  src/lib/db/schema \
  src/lib/zip \
  src/lib/ai \
  src/lib/auth \
  src/lib/rbac \
  src/lib/fs \
  scripts \
  storage \
  drizzle

# ------------------------------------------------------------
# Configure package.json scripts
# ------------------------------------------------------------
echo "Updating package.json scripts..."
node - <<'NODE'
const fs = require("fs");
const path = require("path");

const pkgPath = path.join(process.cwd(), "package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));

pkg.scripts = {
  ...pkg.scripts,
  "dev": "vite",
  "build": "tsc -b && vite build",
  "preview": "vite preview",
  "tauri:dev": "tauri dev",
  "tauri:build": "tauri build",
  "db:migrate": "drizzle-kit push --config drizzle.config.ts",
  "db:seed": "tsx scripts/seed.ts",
  "db:reset": "tsx scripts/reset-db.ts"
};

pkg.type = "module";

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));
NODE

# ------------------------------------------------------------
# Create drizzle.config.ts
# ------------------------------------------------------------
cat > drizzle.config.ts <<'EOF'
import type { Config } from "drizzle-kit";
import path from "node:path";

export default {
  schema: "./src/lib/db/schema/index.ts",
  out: "./drizzle",
  dialect: "sqlite",
  dbCredentials: {
    url: path.join(process.cwd(), "storage", "app.sqlite"),
  },
  strict: true,
  verbose: true,
} satisfies Config;
EOF

# ------------------------------------------------------------
# DB: connection + schema
# ------------------------------------------------------------
cat > src/lib/db/index.ts <<'EOF'
import Database from "better-sqlite3";
import path from "node:path";
import fs from "node:fs";
import { drizzle } from "drizzle-orm/better-sqlite3";
import * as schema from "./schema";

const STORAGE_DIR = path.join(process.cwd(), "storage");
const DB_PATH = path.join(STORAGE_DIR, "app.sqlite");

function ensureStorageDir() {
  if (!fs.existsSync(STORAGE_DIR)) fs.mkdirSync(STORAGE_DIR, { recursive: true });
}

export function getSqlite() {
  ensureStorageDir();
  const sqlite = new Database(DB_PATH);
  sqlite.pragma("journal_mode = WAL");
  return sqlite;
}

export function getDb() {
  const sqlite = getSqlite();
  return drizzle(sqlite, { schema });
}

export const DB_FILE_PATH = DB_PATH;
EOF

cat > src/lib/db/schema/index.ts <<'EOF'
export * from "./tables";
EOF

cat > src/lib/db/schema/tables.ts <<'EOF'
import { sqliteTable, text, integer } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";

// Users (internal only)
export const users = sqliteTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  role: text("role", { enum: ["ADMIN", "COORDINATOR"] }).notNull(),
  isActive: integer("is_active", { mode: "boolean" }).notNull().default(true),
  createdAt: integer("created_at").notNull().default(sql`(unixepoch())`),
});

// Florida counties (seeded: all 67)
export const counties = sqliteTable("counties", {
  id: text("id").primaryKey(), // slug (e.g. "miami-dade")
  name: text("name").notNull().unique(),
  state: text("state").notNull().default("FL"),
  createdAt: integer("created_at").notNull().default(sql`(unixepoch())`),
});

// Customers
export const customers = sqliteTable("customers", {
  id: text("id").primaryKey(),
  fullName: text("full_name").notNull(),
  phone: text("phone"),
  email: text("email"),
  address: text("address"),
  notes: text("notes"),
  createdAt: integer("created_at").notNull().default(sql`(unixepoch())`),
  updatedAt: integer("updated_at").notNull().default(sql`(unixepoch())`),
});

// Contractors
export const contractors = sqliteTable("contractors", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  phone: text("phone"),
  email: text("email"),
  licenseNumber: text("license_number"),
  address: text("address"),
  notes: text("notes"),
  createdAt: integer("created_at").notNull().default(sql`(unixepoch())`),
  updatedAt: integer("updated_at").notNull().default(sql`(unixepoch())`),
});

// Permit Packages
export const permitPackages = sqliteTable("permit_packages", {
  id: text("id").primaryKey(),
  customerId: text("customer_id").notNull(),
  title: text("title").notNull(), // projectName
  permitType: text("permit_type").notNull(),
  propertyAddress: text("property_address").notNull(),
  countyId: text("county_id").notNull(), // references counties.id
  status: text("status", {
    enum: ["DRAFT", "BUILDING", "READY_FOR_BILLING", "SUBMITTED_TO_BILLING"],
  }).notNull().default("DRAFT"),
  assignedCoordinatorId: text("assigned_coordinator_id"),
  createdAt: integer("created_at").notNull().default(sql`(unixepoch())`),
  updatedAt: integer("updated_at").notNull().default(sql`(unixepoch())`),
});

// Permit Package ↔ Contractors (many-to-many)
export const permitPackageContractors = sqliteTable("permit_package_contractors", {
  id: text("id").primaryKey(),
  permitPackageId: text("permit_package_id").notNull(),
  contractorId: text("contractor_id").notNull(),
  roleType: text("role_type"), // GC/sub/etc
});

// Document Requirement templates
export const documentRequirements = sqliteTable("document_requirements", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  description: text("description"),
  category: text("category"),
  isRequired: integer("is_required", { mode: "boolean" }).notNull().default(true),
  sortOrder: integer("sort_order").notNull().default(0),
});

// Uploaded docs
export const permitDocuments = sqliteTable("permit_documents", {
  id: text("id").primaryKey(),
  permitPackageId: text("permit_package_id").notNull(),
  documentRequirementId: text("document_requirement_id"),
  fileName: text("file_name").notNull(),
  filePath: text("file_path").notNull(),
  fileSize: integer("file_size").notNull(),
  mimeType: text("mime_type").notNull(),
  uploadedByUserId: text("uploaded_by_user_id").notNull(),
  uploadedAt: integer("uploaded_at").notNull().default(sql`(unixepoch())`),
  verifiedComplete: integer("verified_complete", { mode: "boolean" }).notNull().default(false),
  verifiedByUserId: text("verified_by_user_id"),
  verifiedAt: integer("verified_at"),
  notes: text("notes"),
});

// Billing submission record
export const billingSubmissions = sqliteTable("billing_submissions", {
  id: text("id").primaryKey(),
  permitPackageId: text("permit_package_id").notNull(),
  submittedByUserId: text("submitted_by_user_id"),
  submittedAt: integer("submitted_at"),
  method: text("method").notNull().default("MANUAL"),
  status: text("status", { enum: ["NOT_SUBMITTED", "READY", "SUBMITTED"] }).notNull().default("NOT_SUBMITTED"),
  notes: text("notes"),
});

// Audit log
export const auditLogs = sqliteTable("audit_logs", {
  id: text("id").primaryKey(),
  actorUserId: text("actor_user_id").notNull(),
  actionType: text("action_type").notNull(),
  entityType: text("entity_type").notNull(),
  entityId: text("entity_id").notNull(),
  timestamp: integer("timestamp").notNull().default(sql`(unixepoch())`),
  detailsJson: text("details_json"),
});
EOF

# ------------------------------------------------------------
# Seed data: Florida counties (ALL 67)
# ------------------------------------------------------------
cat > scripts/seed.ts <<'EOF'
import { getDb } from "../src/lib/db";
import { counties, users } from "../src/lib/db/schema/tables";
import { eq } from "drizzle-orm";
import crypto from "node:crypto";

function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/\./g, "")
    .replace(/\s+/g, "-")
    .replace(/--+/g, "-")
    .replace(/'/g, "")
    .replace(/,/g, "");
}

// IMPORTANT: All 67 Florida counties
const FL_COUNTIES = [
  "Alachua","Baker","Bay","Bradford","Brevard","Broward","Calhoun","Charlotte","Citrus","Clay","Collier","Columbia",
  "DeSoto","Dixie","Duval","Escambia","Flagler","Franklin","Gadsden","Gilchrist","Glades","Gulf","Hamilton","Hardee",
  "Hendry","Hernando","Highlands","Hillsborough","Holmes","Indian River","Jackson","Jefferson","Lafayette","Lake","Lee",
  "Leon","Levy","Liberty","Madison","Manatee","Marion","Martin","Miami-Dade","Monroe","Nassau","Okaloosa","Okeechobee",
  "Orange","Osceola","Palm Beach","Pasco","Pinellas","Polk","Putnam","Santa Rosa","Sarasota","Seminole","St. Johns",
  "St. Lucie","Sumter","Suwannee","Taylor","Union","Volusia","Wakulla","Walton","Washington"
];

async function main() {
  const db = getDb();

  // Seed Counties
  for (const c of FL_COUNTIES) {
    const id = slugify(c);
    try {
      await db.insert(counties).values({ id, name: c, state: "FL" }).run();
    } catch {
      // likely unique conflict, ignore
    }
  }

  // Seed a default Admin user (local-only dev convenience)
  // Email: admin@local
  // Password: admin123
  // NOTE: Replace with real auth later; this is scaffolding.
  const adminEmail = "admin@local";
  const existing = await db.select().from(users).where(eq(users.email, adminEmail)).all();
  if (existing.length === 0) {
    const id = crypto.randomUUID();
    const passwordHash = crypto.createHash("sha256").update("admin123").digest("hex");
    await db.insert(users).values({
      id,
      email: adminEmail,
      passwordHash,
      role: "ADMIN",
      isActive: true,
    }).run();
  }

  console.log("Seed complete: 67 FL counties + default admin user.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
EOF

cat > scripts/reset-db.ts <<'EOF'
import fs from "node:fs";
import path from "node:path";
import { DB_FILE_PATH } from "../src/lib/db";

function main() {
  if (fs.existsSync(DB_FILE_PATH)) {
    fs.rmSync(DB_FILE_PATH);
    console.log("Deleted DB:", DB_FILE_PATH);
  } else {
    console.log("DB not found (nothing to delete).");
  }

  const storageDir = path.join(process.cwd(), "storage");
  if (!fs.existsSync(storageDir)) fs.mkdirSync(storageDir, { recursive: true });
}

main();
EOF

# ------------------------------------------------------------
# ZIP helper (bundle docs + summary.json)
# ------------------------------------------------------------
cat > src/lib/zip/exportPermitPackageZip.ts <<'EOF'
import JSZip from "jszip";

export type PermitPackageZipSummary = {
  customer: {
    id: string;
    fullName: string;
    email?: string | null;
    phone?: string | null;
    address?: string | null;
  };
  permitPackage: {
    id: string;
    title: string;
    permitType: string;
    propertyAddress: string;
    countyName: string;
    status: string;
  };
  contractors: Array<{
    id: string;
    name: string;
    phone?: string | null;
    email?: string | null;
    licenseNumber?: string | null;
  }>;
  documents: Array<{
    id: string;
    fileName: string;
    verifiedComplete: boolean;
  }>;
  generatedAtISO: string;
};

export async function createPermitPackageZip(args: {
  summary: PermitPackageZipSummary;
  files: Array<{ fileName: string; bytes: Uint8Array }>;
}) {
  const zip = new JSZip();
  zip.file("summary.json", JSON.stringify(args.summary, null, 2));

  const docsFolder = zip.folder("documents");
  for (const f of args.files) {
    docsFolder?.file(f.fileName, f.bytes);
  }

  const blob = await zip.generateAsync({ type: "blob" });
  return blob;
}
EOF

# ------------------------------------------------------------
# AI Agent stubs (tool-calling pattern placeholder)
# ------------------------------------------------------------
cat > src/lib/ai/agent.ts <<'EOF'
export type AgentToolCall =
  | { tool: "searchCustomerByName"; args: { name: string } }
  | { tool: "getPermitPackagesForCustomer"; args: { customerId: string } }
  | { tool: "getMissingDocs"; args: { permitPackageId: string } }
  | { tool: "createZipBundle"; args: { permitPackageId: string } };

export type AgentMessage = { role: "user" | "assistant"; content: string };

export async function runAgentLocalStub(messages: AgentMessage[]) {
  // This is a scaffold stub: You will replace this with real OpenAI tool-calling
  // or a local model later. For now, return a deterministic response.
  const last = messages[messages.length - 1]?.content ?? "";
  return {
    text:
      "AI not configured yet. Add your API key in Settings (future). You said: " +
      JSON.stringify(last),
    toolCalls: [] as AgentToolCall[],
  };
}
EOF

# ------------------------------------------------------------
# Basic RBAC
# ------------------------------------------------------------
cat > src/lib/rbac/roles.ts <<'EOF'
export type Role = "ADMIN" | "COORDINATOR";

export function canAccessAdmin(role: Role) {
  return role === "ADMIN";
}
EOF

# ------------------------------------------------------------
# Minimal app routing + pages
# ------------------------------------------------------------
cat > src/app/routes.tsx <<'EOF'
import { createBrowserRouter } from "react-router-dom";
import { AppLayout } from "./layouts/AppLayout";
import { DashboardPage } from "./pages/DashboardPage";
import { CustomersPage } from "./pages/CustomersPage";
import { PermitPackagesPage } from "./pages/PermitPackagesPage";
import { ContractorsPage } from "./pages/ContractorsPage";
import { BillingQueuePage } from "./pages/BillingQueuePage";
import { AdminPage } from "./pages/AdminPage";
import { AIAssistantPage } from "./pages/AIAssistantPage";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <AppLayout />,
    children: [
      { index: true, element: <DashboardPage /> },
      { path: "customers", element: <CustomersPage /> },
      { path: "permit-packages", element: <PermitPackagesPage /> },
      { path: "contractors", element: <ContractorsPage /> },
      { path: "billing", element: <BillingQueuePage /> },
      { path: "admin", element: <AdminPage /> },
      { path: "ai", element: <AIAssistantPage /> },
    ],
  },
]);
EOF

cat > src/app/layouts/AppLayout.tsx <<'EOF'
import { NavLink, Outlet } from "react-router-dom";

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `block px-3 py-2 rounded ${isActive ? "bg-slate-200" : "hover:bg-slate-100"}`;

export function AppLayout() {
  return (
    <div className="h-screen w-screen flex">
      <aside className="w-64 border-r p-3">
        <div className="font-bold text-lg mb-4">Permit Tracker</div>
        <nav className="space-y-1 text-sm">
          <NavLink to="/" className={navLinkClass}>Dashboard</NavLink>
          <NavLink to="/customers" className={navLinkClass}>Customers</NavLink>
          <NavLink to="/permit-packages" className={navLinkClass}>Permit Packages</NavLink>
          <NavLink to="/contractors" className={navLinkClass}>Contractors</NavLink>
          <NavLink to="/billing" className={navLinkClass}>Billing Queue</NavLink>
          <NavLink to="/admin" className={navLinkClass}>Admin</NavLink>
          <NavLink to="/ai" className={navLinkClass}>AI Assistant</NavLink>
        </nav>
        <div className="mt-6 text-xs text-slate-500">
          Local-first • SQLite • Offline-ready
        </div>
      </aside>

      <main className="flex-1 p-6 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}
EOF

cat > src/app/pages/DashboardPage.tsx <<'EOF'
export function DashboardPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Dashboard</h1>
      <p className="text-slate-600">
        Overview of permit packages, document completion, and billing readiness.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="border rounded p-4">
          <div className="text-sm text-slate-500">Packages</div>
          <div className="text-2xl font-bold">0</div>
        </div>
        <div className="border rounded p-4">
          <div className="text-sm text-slate-500">Missing Docs</div>
          <div className="text-2xl font-bold">0</div>
        </div>
        <div className="border rounded p-4">
          <div className="text-sm text-slate-500">Ready for Billing</div>
          <div className="text-2xl font-bold">0</div>
        </div>
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/CustomersPage.tsx <<'EOF'
export function CustomersPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Customers</h1>
      <p className="text-slate-600">Create/search customers and view their permit packages.</p>
      <div className="border rounded p-4 text-sm text-slate-600">
        Scaffold: customer list + create form will be implemented next.
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/PermitPackagesPage.tsx <<'EOF'
export function PermitPackagesPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Permit Packages</h1>
      <p className="text-slate-600">
        Track document checklists, upload files, verify completion, export ZIP, and submit to billing.
      </p>
      <div className="border rounded p-4 text-sm text-slate-600">
        Scaffold: permit package list + details view will be implemented next.
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/ContractorsPage.tsx <<'EOF'
export function ContractorsPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Contractors</h1>
      <p className="text-slate-600">
        Manage contractors. Select existing or add inline while building a permit package.
      </p>
      <div className="border rounded p-4 text-sm text-slate-600">
        Scaffold: contractor CRUD will be implemented next.
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/BillingQueuePage.tsx <<'EOF'
export function BillingQueuePage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Billing Queue</h1>
      <p className="text-slate-600">
        Packages become eligible only after all required docs are uploaded AND manually verified.
      </p>
      <div className="border rounded p-4 text-sm text-slate-600">
        Scaffold: billing queue list will be implemented next.
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/AdminPage.tsx <<'EOF'
export function AdminPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-2xl font-semibold">Admin</h1>
      <p className="text-slate-600">
        Admin dashboard: system overview, user management, and document requirement templates.
      </p>
      <div className="border rounded p-4 text-sm text-slate-600">
        Scaffold: user mgmt + requirements mgmt will be implemented next.
      </div>
    </div>
  );
}
EOF

cat > src/app/pages/AIAssistantPage.tsx <<'EOF'
import { useState } from "react";
import { runAgentLocalStub } from "../../lib/ai/agent";

export function AIAssistantPage() {
  const [input, setInput] = useState("");
  const [messages, setMessages] = useState<{ role: "user" | "assistant"; content: string }[]>([
    { role: "assistant", content: "Ask me for customer paperwork, missing docs, or ZIP bundles." },
  ]);

  async function onSend() {
    const text = input.trim();
    if (!text) return;
    setInput("");
    const next = [...messages, { role: "user", content: text }];
    setMessages(next);

    const res = await runAgentLocalStub(next);
    setMessages([...next, { role: "assistant", content: res.text }]);
  }

  return (
    <div className="space-y-3 max-w-3xl">
      <h1 className="text-2xl font-semibold">AI Assistant</h1>
      <p className="text-slate-600">
        Natural language workflow shortcuts (tool-calling agent pattern).
      </p>

      <div className="border rounded p-3 h-[420px] overflow-auto space-y-2 bg-white">
        {messages.map((m, idx) => (
          <div key={idx} className={m.role === "user" ? "text-right" : "text-left"}>
            <div className="inline-block max-w-[80%] rounded px-3 py-2 text-sm border">
              <span className="font-semibold mr-2">{m.role === "user" ? "You" : "AI"}:</span>
              {m.content}
            </div>
          </div>
        ))}
      </div>

      <div className="flex gap-2">
        <input
          className="flex-1 border rounded px-3 py-2"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder='Try: "Get John Smith’s paperwork"'
        />
        <button className="border rounded px-3 py-2" onClick={onSend}>
          Send
        </button>
      </div>
    </div>
  );
}
EOF

# ------------------------------------------------------------
# Replace src/main.tsx to use router
# ------------------------------------------------------------
cat > src/main.tsx <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import { RouterProvider } from "react-router-dom";
import { router } from "./app/routes";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
EOF

# ------------------------------------------------------------
# Tailwind (optional) - leaving default CSS for speed
# (You can add Tailwind later if you want; this script keeps it minimal)
# ------------------------------------------------------------

# ------------------------------------------------------------
# README
# ------------------------------------------------------------
cat > README.md <<'EOF'
# Permit Package Tracker (Native Desktop)

Native desktop permit package tracking app for internal teams.

## Stack
- Tauri + React + TypeScript (Vite)
- SQLite (local-first) + better-sqlite3
- Drizzle ORM
- JSZip for bulk ZIP export
- Offline-ready (AI requires internet unless replaced with local model)

## Seeded for Florida
This repo seeds **ALL 67 Florida counties** into the database.

## Quick Start
```bash
npm install
npm run db:migrate
npm run db:seed

# Run web UI dev (useful for fast UI work)
npm run dev

# Run full desktop app
npm run tauri:dev

Default Dev Admin
	•	email: admin@local
	•	password: admin123

Database
	•	SQLite file stored at: storage/app.sqlite

Next Steps (Implementation Roadmap)
	•	Implement authentication screens + local session storage
	•	CRUD: Customers, Contractors, Permit Packages
	•	Document checklist templates + per-package requirements
	•	Upload pipeline + preview + manual verification toggles
	•	Billing gate enforcement (required docs + manual verification)
	•	ZIP export button (documents + summary.json)
	•	AI tool-calling integration (OpenAI + internal functions)
EOF

----------------------------------------

Done

----------------------------------------

echo ""
echo "✅ Scaffold complete."
echo ""
echo "Next commands:"
echo "  cd $APP_DIR"
echo "  npm run db:migrate"
echo "  npm run db:seed"
echo "  npm run tauri:dev"
echo ""
echo "Notes:"
echo "- Florida counties are seeded by: scripts/seed.ts"
echo "- SQLite DB path: storage/app.sqlite"

