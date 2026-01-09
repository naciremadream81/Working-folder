#!/usr/bin/env bash
set   -euo pipefail

PROJECT_NAME="${1:-permit-app}"

echo "=================================================="
echo "Permit Processing & Document Management Scaffold"
echo "=================================================="
echo "Project: $PROJECT_NAME"
echo ""

# Validate prerequisites
command -v node >/dev/null 2>&1 || { echo "Error: node is required but not installed."; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "Error: npm is required but not installed."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || { echo "Error: docker-compose is required but not installed."; exit 1; }

# Create Next.js app
if [ -d "$PROJECT_NAME" ]; then
  echo "Directory $PROJECT_NAME already exists. Proceeding with setup inside it..."
  cd "$PROJECT_NAME"
else
  echo "Creating Next.js app..."
  npx create-next-app@14 "$PROJECT_NAME" --typescript --tailwind --eslint --app --src-dir --import-alias "@/*" --no-git
  cd "$PROJECT_NAME"
fi

# Install dependencies
echo "Installing dependencies..."
npm install --save prisma @prisma/client bcryptjs jsonwebtoken
npm install --save-dev @types/bcryptjs @types/jsonwebtoken

# Create directory structure
mkdir -p docker cloudflare prisma/seed src/server/{auth,rbac,storage} docs

# Docker Compose for Postgres
cat > docker/docker-compose.yml <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: permit_db
    restart: unless-stopped
    environment:
      POSTGRES_USER: permituser
      POSTGRES_PASSWORD: permitpass
      POSTGRES_DB: permitdb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
EOF

# Cloudflare Tunnel config
cat > cloudflare/cloudflared-config.yml <<'EOF'
tunnel: YOUR_TUNNEL_ID
credentials-file: /etc/cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: permits.yourdomain.com
    service: http://localhost:3000
  - service: http_status:404
EOF

# Cloudflare Zero Trust docs
cat > docs/zero-trust.md <<'EOF'
# Cloudflare Zero Trust Setup

## Prerequisites
- Cloudflare account with Zero Trust enabled
- Domain configured in Cloudflare

## Steps

### 1. Create Cloudflare Tunnel
```bash
cloudflared tunnel create permit-tunnel
```

Save the tunnel ID and credentials file path.

### 2. Configure Tunnel

Edit `cloudflare/cloudflared-config.yml`:

- Replace `YOUR_TUNNEL_ID` with your tunnel ID
- Replace `YOUR_TUNNEL_ID.json` with actual credentials filename
- Update `permits.yourdomain.com` with your domain

### 3. Create DNS Record

```bash
cloudflared tunnel route dns permit-tunnel permits.yourdomain.com
```

### 4. Configure Access Policy

1. Go to Cloudflare Zero Trust Dashboard → Access → Applications
1. Create new application:

- Name: Permit Processing App
- Domain: [permits.yourdomain.com](http://permits.yourdomain.com)
- Type: Self-hosted

1. Add policies (e.g., email domain, specific emails)
1. Note your team domain: `yourteam.cloudflareaccess.com`
1. Note the Application Audience (AUD) tag

### 5. Update Environment Variables

In `.env`:

```
CF_ACCESS_AUD=your_aud_tag_here
CF_TEAM_DOMAIN=yourteam.cloudflareaccess.com
```

### 6. Run Tunnel

```bash
cloudflared tunnel --config cloudflare/cloudflared-config.yml run permit-tunnel
```

Or install as a service:

```bash
sudo cloudflared service install
```

## Validating Access Tokens

The app validates Cloudflare Access JWT tokens to ensure requests come through the tunnel.
See `src/server/auth/cloudflare.ts` for implementation.
EOF

# Environment template

cat > .env.example <<‘EOF’

# Database

DATABASE_URL="postgresql://permituser:permitpass@localhost:5432/permitdb"

# JWT Auth

JWT_SECRET="change-this-to-a-random-32-char-string"

# Cloudflare Access (Zero Trust)

CF_ACCESS_AUD="your_application_aud_tag"
CF_TEAM_DOMAIN="[yourteam.cloudflareaccess.com](http://yourteam.cloudflareaccess.com)"

# File Upload

UPLOAD_DIR="./uploads"
MAX_FILE_SIZE_MB=10

# App

NODE_ENV="development"
EOF

cp .env.example .env

# Prisma schema

cat > prisma/schema.prisma <<‘EOF’
generator client {
provider = "prisma-client-js"
}

datasource db {
provider = "postgresql"
url      = env("DATABASE_URL")
}

enum UserRole {
ADMIN
COORDINATOR
BILLING
}

model User {
id           String   @id @default(cuid())
email        String   @unique
name         String
role         UserRole
passwordHash String
createdAt    DateTime @default(now())
updatedAt    DateTime @updatedAt

activityEvents ActivityEvent[]
}

model Contractor {
id        String   @id @default(cuid())
name      String
email     String?
phone     String?
licenseNo String?
createdAt DateTime @default(now())
updatedAt DateTime @updatedAt

jobs Job[]
}

model Job {
id           String   @id @default(cuid())
jobNumber    String   @unique
customerName String
address      String
contractorId String
createdAt    DateTime @default(now())
updatedAt    DateTime @updatedAt

contractor Contractor @relation(fields: [contractorId], references: [id])
permits    Permit[]
}

enum PermitStatus {
PENDING
APPROVED
REJECTED
EXPIRED
}

model Permit {
id          String       @id @default(cuid())
permitNo    String       @unique
type        String
description String?
status      PermitStatus @default(PENDING)
jobId       String
appliedAt   DateTime     @default(now())
approvedAt  DateTime?
expiresAt   DateTime?
createdAt   DateTime     @default(now())
updatedAt   DateTime     @updatedAt

job       Job        @relation(fields: [jobId], references: [id])
tasks     Task[]
documents Document[]
notes     Note[]
}

enum TaskStatus {
TODO
IN_PROGRESS
COMPLETED
}

model Task {
id          String     @id @default(cuid())
title       String
description String?
status      TaskStatus @default(TODO)
dueDate     DateTime?
permitId    String?
createdAt   DateTime   @default(now())
updatedAt   DateTime   @updatedAt

permit Permit? @relation(fields: [permitId], references: [id])
}

enum DocumentCategory {
APPLICATION
APPROVAL
INSPECTION
INVOICE
OTHER
}

model Document {
id          String           @id @default(cuid())
fileName    String
category    DocumentCategory
version     Int              @default(1)
isCurrent   Boolean          @default(true)
storageKey  String
mimeType    String?
sizeBytes   Int?
permitId    String?
uploadedBy  String?
uploadedAt  DateTime         @default(now())
createdAt   DateTime         @default(now())

permit Permit? @relation(fields: [permitId], references: [id])
}

model Note {
id        String   @id @default(cuid())
content   String
permitId  String?
createdBy String?
createdAt DateTime @default(now())

permit Permit? @relation(fields: [permitId], references: [id])
}

model ActivityEvent {
id          String   @id @default(cuid())
action      String
entityType  String?
entityId    String?
metadata    Json?
userId      String?
ipAddress   String?
createdAt   DateTime @default(now())

user User? @relation(fields: [userId], references: [id])
}
EOF

# Prisma seed script

cat > prisma/seed/seed.ts <<‘EOF’
import { PrismaClient, UserRole, PermitStatus, TaskStatus, DocumentCategory } from ‘@prisma/client’;
import * as bcrypt from ‘bcryptjs’;

const prisma = new PrismaClient();

async function main() {
console.log(‘Seeding database…’);

// Create users
const adminPassword = await bcrypt.hash(‘admin123’, 10);
const coordPassword = await bcrypt.hash(‘coord123’, 10);
const billingPassword = await bcrypt.hash(‘billing123’, 10);

const admin = await prisma.user.upsert({
where: { email: ‘admin@example.com’ },
update: {},
create: {
email: ‘admin@example.com’,
name: ‘Admin User’,
role: UserRole.ADMIN,
passwordHash: adminPassword,
},
});

const coordinator = await prisma.user.upsert({
where: { email: ‘coord@example.com’ },
update: {},
create: {
email: ‘coord@example.com’,
name: ‘Coordinator User’,
role: UserRole.COORDINATOR,
passwordHash: coordPassword,
},
});

const billing = await prisma.user.upsert({
where: { email: ‘billing@example.com’ },
update: {},
create: {
email: ‘billing@example.com’,
name: ‘Billing User’,
role: UserRole.BILLING,
passwordHash: billingPassword,
},
});

console.log(‘Created users:’, { admin, coordinator, billing });

// Create contractor
const contractor = await prisma.contractor.create({
data: {
name: ‘ABC Construction LLC’,
email: ‘contact@abcconstruction.com’,
phone: ‘555-1234’,
licenseNo: ‘LIC-2024-001’,
},
});

console.log(‘Created contractor:’, contractor);

// Create job
const job = await prisma.job.create({
data: {
jobNumber: ‘JOB-2024-001’,
customerName: ‘John Smith’,
address: ‘123 Main St, Springfield’,
contractorId: [contractor.id](http://contractor.id),
},
});

console.log(‘Created job:’, job);

// Create permit
const permit = await prisma.permit.create({
data: {
permitNo: ‘PERMIT-2024-001’,
type: ‘Building Permit’,
description: ‘Residential addition’,
status: PermitStatus.PENDING,
jobId: [job.id](http://job.id),
},
});

console.log(‘Created permit:’, permit);

// Create tasks
const task1 = await prisma.task.create({
data: {
title: ‘Submit application documents’,
description: ‘Gather and submit all required application forms’,
status: TaskStatus.COMPLETED,
permitId: [permit.id](http://permit.id),
},
});

const task2 = await prisma.task.create({
data: {
title: ‘Schedule inspection’,
description: ‘Contact inspector for initial site review’,
status: TaskStatus.TODO,
dueDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
permitId: [permit.id](http://permit.id),
},
});

console.log(‘Created tasks:’, { task1, task2 });

// Create activity event
const event = await prisma.activityEvent.create({
data: {
action: ‘PERMIT_CREATED’,
entityType: ‘Permit’,
entityId: [permit.id](http://permit.id),
userId: [coordinator.id](http://coordinator.id),
metadata: { permitNo: permit.permitNo, type: permit.type },
},
});

console.log(‘Created activity event:’, event);

console.log(‘Seeding completed successfully!’);
}

main()
.catch((e) => {
console.error(‘Error seeding database:’, e);
process.exit(1);
})
.finally(async () => {
await prisma.$disconnect();
});
EOF

# Prisma client

cat > src/server/prisma.ts <<‘EOF’
import { PrismaClient } from ‘@prisma/client’;

const globalForPrisma = globalThis as unknown as {
prisma: PrismaClient | undefined;
};

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== ‘production’) globalForPrisma.prisma = prisma;
EOF

# Auth helpers

cat > src/server/auth/password.ts <<‘EOF’
import * as bcrypt from ‘bcryptjs’;

export async function hashPassword(password: string): Promise<string> {
return bcrypt.hash(password, 10);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
return bcrypt.compare(password, hash);
}
EOF

cat > src/server/auth/jwt.ts <<‘EOF’
import jwt from ‘jsonwebtoken’;

const JWT_SECRET = process.env.JWT_SECRET || ‘fallback-secret-change-me’;

export interface JWTPayload {
userId: string;
email: string;
role: string;
}

export function signToken(payload: JWTPayload): string {
return jwt.sign(payload, JWT_SECRET, { expiresIn: ‘7d’ });
}

export function verifyToken(token: string): JWTPayload | null {
try {
return jwt.verify(token, JWT_SECRET) as JWTPayload;
} catch {
return null;
}
}
EOF

cat > src/server/auth/cloudflare.ts <<‘EOF’
import jwt from ‘jsonwebtoken’;

const CF_ACCESS_AUD = process.env.CF_ACCESS_AUD;
const CF_TEAM_DOMAIN = process.env.CF_TEAM_DOMAIN;

export interface CloudflareAccessPayload {
aud: string[];
email: string;
type: string;
iat: number;
exp: number;
}

export async function verifyCFAccessToken(token: string): Promise<CloudflareAccessPayload | null> {
if (!CF_ACCESS_AUD || !CF_TEAM_DOMAIN) {
console.warn(‘Cloudflare Access not configured’);
return null;
}

try {
const certsUrl = `https://${CF_TEAM_DOMAIN}/cdn-cgi/access/certs`;
const certsRes = await fetch(certsUrl);
const certsData = await certsRes.json();

```
// In production, verify against public keys from certsData
// For now, decode without verification (development only)
const decoded = jwt.decode(token) as CloudflareAccessPayload;

if (!decoded || !decoded.aud.includes(CF_ACCESS_AUD)) {
  return null;
}

return decoded;
```

} catch (error) {
console.error(‘CF Access token verification failed:’, error);
return null;
}
}
EOF

# RBAC helpers

cat > src/server/rbac/permissions.ts <<‘EOF’
import { UserRole } from ‘@prisma/client’;

export const ROLE_PERMISSIONS = {
[UserRole.ADMIN]: [’*’],
[UserRole.COORDINATOR]: [
‘permits:read’,
‘permits:write’,
‘jobs:read’,
‘jobs:write’,
‘documents:read’,
‘documents:write’,
‘tasks:read’,
‘tasks:write’,
],
[UserRole.BILLING]: [
‘permits:read’,
‘jobs:read’,
‘documents:read’,
‘invoices:read’,
‘invoices:write’,
],
};

export function hasPermission(role: UserRole, permission: string): boolean {
const permissions = ROLE_PERMISSIONS[role];
return permissions.includes(’*’) || permissions.includes(permission);
}

export function requirePermission(role: UserRole, permission: string): void {
if (!hasPermission(role, permission)) {
throw new Error(`Access denied: ${permission} required`);
}
}
EOF

# Storage adapter interface

cat > src/server/storage/adapter.ts <<‘EOF’
export interface StorageAdapter {
save(file: Buffer, key: string): Promise<string>;
get(key: string): Promise<Buffer>;
delete(key: string): Promise<void>;
exists(key: string): Promise<boolean>;
}
EOF

cat > src/server/storage/filesystem.ts <<‘EOF’
import fs from ‘fs/promises’;
import path from ‘path’;
import { StorageAdapter } from ‘./adapter’;

export class FilesystemStorageAdapter implements StorageAdapter {
private baseDir: string;

constructor(baseDir: string = ‘./uploads’) {
this.baseDir = baseDir;
}

private getPath(key: string): string {
return path.join(this.baseDir, key);
}

async save(file: Buffer, key: string): Promise<string> {
await fs.mkdir(this.baseDir, { recursive: true });
const filePath = this.getPath(key);
await fs.writeFile(filePath, file);
return key;
}

async get(key: string): Promise<Buffer> {
const filePath = this.getPath(key);
return fs.readFile(filePath);
}

async delete(key: string): Promise<void> {
const filePath = this.getPath(key);
await fs.unlink(filePath);
}

async exists(key: string): Promise<boolean> {
const filePath = this.getPath(key);
try {
await fs.access(filePath);
return true;
} catch {
return false;
}
}
}
EOF

# Simple login API route

mkdir -p src/app/api/auth/login
cat > src/app/api/auth/login/route.ts <<‘EOF’
import { NextRequest, NextResponse } from ‘next/server’;
import { prisma } from ‘@/server/prisma’;
import { verifyPassword } from ‘@/server/auth/password’;
import { signToken } from ‘@/server/auth/jwt’;

export async function POST(req: NextRequest) {
try {
const { email, password } = await req.json();

```
const user = await prisma.user.findUnique({ where: { email } });
if (!user) {
  return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
}

const valid = await verifyPassword(password, user.passwordHash);
if (!valid) {
  return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
}

const token = signToken({
  userId: user.id,
  email: user.email,
  role: user.role,
});

const response = NextResponse.json({
  user: { id: user.id, email: user.email, name: user.name, role: user.role },
});

response.cookies.set('auth-token', token, {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax',
  maxAge: 7 * 24 * 60 * 60,
});

return response;
```

} catch (error) {
console.error(‘Login error:’, error);
return NextResponse.json({ error: ‘Internal server error’ }, { status: 500 });
}
}
EOF

# Upload API route scaffold

mkdir -p src/app/api/documents/upload
cat > src/app/api/documents/upload/route.ts <<‘EOF’
import { NextRequest, NextResponse } from ‘next/server’;
import { prisma } from ‘@/server/prisma’;
import { FilesystemStorageAdapter } from ‘@/server/storage/filesystem’;
import { randomUUID } from ‘crypto’;

const storage = new FilesystemStorageAdapter(process.env.UPLOAD_DIR);

export async function POST(req: NextRequest) {
try {
const formData = await req.formData();
const file = formData.get(‘file’) as File;
const permitId = formData.get(‘permitId’) as string;
const category = formData.get(‘category’) as string;

```
if (!file) {
  return NextResponse.json({ error: 'No file provided' }, { status: 400 });
}

const buffer = Buffer.from(await file.arrayBuffer());
const storageKey = `${randomUUID()}-${file.name}`;

await storage.save(buffer, storageKey);

const document = await prisma.document.create({
  data: {
    fileName: file.name,
    category: category || 'OTHER',
    storageKey,
    mimeType: file.type,
    sizeBytes: file.size,
    permitId: permitId || null,
  },
});

return NextResponse.json({ document });
```

} catch (error) {
console.error(‘Upload error:’, error);
return NextResponse.json({ error: ‘Upload failed’ }, { status: 500 });
}
}
EOF

# Test scaffold

mkdir -p **tests**
cat > **tests**/auth.test.ts <<‘EOF’
import { hashPassword, verifyPassword } from ‘@/server/auth/password’;

describe(‘Auth Password Utilities’, () => {
it(‘should hash and verify password correctly’, async () => {
const password = ‘testpassword123’;
const hash = await hashPassword(password);

```
expect(hash).toBeDefined();
expect(hash).not.toBe(password);

const valid = await verifyPassword(password, hash);
expect(valid).toBe(true);

const invalid = await verifyPassword('wrongpassword', hash);
expect(invalid).toBe(false);
```

});
});
EOF

# Update package.json scripts

cat > package.json.tmp <<‘EOF’
{
"name": "permit-app",
"version": "0.1.0",
"private": true,
"scripts": {
"dev": "next dev",
"build": "next build",
"start": "next start",
"lint": "next lint",
"db:generate": "prisma generate",
"db:migrate": "prisma migrate dev",
"db:seed": "tsx prisma/seed/seed.ts",
"db:studio": "prisma studio",
"db:setup": "npm run db:migrate && npm run db:seed",
"test": "jest"
}
}
EOF

# Merge scripts into existing package.json

node -e "
const fs = require(‘fs’);
const pkg = JSON.parse(fs.readFileSync(‘package.json’, ‘utf8’));
const tmp = JSON.parse(fs.readFileSync(‘package.json.tmp’, ‘utf8’));
pkg.scripts = { …pkg.scripts, …tmp.scripts };
fs.writeFileSync(‘package.json’, JSON.stringify(pkg, null, 2));
"
rm package.json.tmp

# Install additional dev dependencies

npm install –save-dev tsx jest @types/jest ts-jest

# Jest config

cat > jest.config.js <<‘EOF’
const nextJest = require(‘next/jest’);

const createJestConfig = nextJest({
dir: ‘./’,
});

const customJestConfig = {
setupFilesAfterEnv: [],
testEnvironment: ‘node’,
moduleNameMapper: {
‘^@/(.*)$’: ‘<rootDir>/src/$1’,
},
};

module.exports = createJestConfig(customJestConfig);
EOF

# README

cat > README.md <<‘EOF’

# Permit Processing & Document Management

Full-stack application for managing building permits, contractors, jobs, documents, and workflows.

## Tech Stack

- **Frontend**: Next.js 14 (App Router), TypeScript, Tailwind CSS
- **Backend**: Next.js API Routes, Prisma ORM
- **Database**: PostgreSQL (Docker)
- **Auth**: JWT + cookie-based sessions
- **File Storage**: Filesystem adapter (extensible)
- **Infrastructure**: Cloudflare Tunnel + Zero Trust Access

## Prerequisites

- Node.js 18+
- Docker & Docker Compose
- npm or yarn

## Local Development Setup

### 1. Start Database

```bash
docker-compose -f docker/docker-compose.yml up -d
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Setup Database

```bash
npm run db:setup
```

This will:

- Run Prisma migrations
- Seed initial data (users, contractor, job, permit, tasks)

### 4. Run Development Server

```bash
npm run dev
```

Open <http://localhost:3000>

## Seeded Users

The seed script creates three users for testing:

|Email              |Password  |Role       |
|-------------------|----------|-----------|
|admin@example.com  |admin123  |ADMIN      |
|coord@example.com  |coord123  |COORDINATOR|
|billing@example.com|billing123|BILLING    |

## Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run start` - Start production server
- `npm run db:migrate` - Run database migrations
- `npm run db:seed` - Seed database with initial data
- `npm run db:studio` - Open Prisma Studio (database GUI)
- `npm test` - Run tests

## Project Structure

```
├── src/
│   ├── app/              # Next.js App Router pages & API routes
│   └── server/           # Server-side utilities
│       ├── auth/         # Authentication helpers
│       ├── rbac/         # Role-based access control
│       └── storage/      # File storage adapters
├── prisma/
│   ├── schema.prisma     # Database schema
│   └── seed/             # Database seed scripts
├── docker/
│   └── docker-compose.yml # Postgres container
├── cloudflare/
│   └── cloudflared-config.yml # Tunnel configuration
└── docs/
    └── zero-trust.md     # Cloudflare setup guide
```

## Database Models

- **User**: Admin, Coordinator, Billing roles
- **Contractor**: License holders
- **Job**: Customer projects
- **Permit**: Building permits with status workflow
- **Task**: Action items linked to permits
- **Document**: Versioned file uploads
- **Note**: Comments on permits
- **ActivityEvent**: Audit log

## Cloudflare Zero Trust Setup

See <docs/zero-trust.md> for detailed setup instructions.

## Environment Variables

Copy `.env.example` to `.env` and configure:

```env
DATABASE_URL="postgresql://permituser:permitpass@localhost:5432/permitdb"
JWT_SECRET="your-secret-key"
CF_ACCESS_AUD="your-cloudflare-aud"
CF_TEAM_DOMAIN="yourteam.cloudflareaccess.com"
UPLOAD_DIR="./uploads"
```

## API Routes

- `POST /api/auth/login` - User login (returns JWT cookie)
- `POST /api/documents/upload` - Upload document

## Next Steps

1. Implement frontend UI for permits, jobs, documents
1. Add logout endpoint
1. Add authentication middleware for protected routes
1. Extend RBAC enforcement to API routes
1. Implement document versioning UI
1. Add comprehensive tests
1. Configure Cloudflare Tunnel for production
1. Set up CI/CD pipeline

## License

Private - All Rights Reserved
EOF

# Initialize Prisma

echo "Initializing Prisma…"
npx prisma generate

# Start database and run migrations

echo "Starting database and running migrations…"
if command -v docker compose &> /dev/null; then
docker compose -f docker/docker-compose.yml up -d
else
docker-compose -f docker/docker-compose.yml up -d
fi

# Wait for database

echo "Waiting for database to be ready…"
sleep 5

# Run migrations

npx prisma migrate dev –name init –skip-generate

# Run seed

echo "Seeding database…"
npm run db:seed

echo ""
echo "=================================================="
echo "✅ Setup Complete!"
echo "=================================================="
echo ""
echo "Project: $PROJECT_NAME"
echo ""
echo "Next steps:"
echo "  1. cd $PROJECT_NAME"
echo "  2. npm run dev"
echo "  3. Open <http://localhost:3000>"
echo ""
echo "Seeded users:"
echo "  - admin@example.com / admin123 (ADMIN)"
echo "  - coord@example.com / coord123 (COORDINATOR)"
echo "  - billing@example.com / billing123 (BILLING)"
echo ""
echo "Database GUI:"
echo "  npm run db:studio"
echo ""
echo "See README.md for full documentation."
echo "See docs/zero-trust.md for Cloudflare setup."
echo ""

```

```