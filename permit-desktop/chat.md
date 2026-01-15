Perfect — packaging the backend as a real executable sidecar is the right move. That removes the “Node must be installed” requirement and makes your desktop installer self-contained.

Below is the cleanest, most reliable setup for Tauri + Node backend as a bundled sidecar binary, using pkg.

⸻

✅ Goal

When you run the desktop app:
	•	Tauri starts a backend executable automatically
	•	Backend listens on http://127.0.0.1:47831
	•	React UI calls it for:
	•	uploads
	•	ZIP export
	•	RAG indexing
	•	AI tool-calling

✅ Works even if the end-user has no Node installed

⸻

✅ Approach: Compile backend into a binary with pkg

Why pkg?

It packs your Node app into a single executable per platform.

Targets you want:
	•	Windows x64 → .exe
	•	macOS x64 + arm64
	•	Linux x64

⸻

1) Update backend to support binary packaging

A) Install pkg

From backend/:

cd backend
npm i -D pkg

B) Update backend/package.json

Add these fields:

{
  “bin”: “dist/server.js”,
  “pkg”: {
    “assets”: [
      “dist/**/*”
    ]
  },
  “scripts”: {
    “build”: “tsc -p tsconfig.json”,
    “sidecar:win”: “npm run build && pkg -t node20-win-x64 -o ../src-tauri/bin/permit-backend dist/server.js”,
    “sidecar:mac-arm”: “npm run build && pkg -t node20-macos-arm64 -o ../src-tauri/bin/permit-backend dist/server.js”,
    “sidecar:mac-x64”: “npm run build && pkg -t node20-macos-x64 -o ../src-tauri/bin/permit-backend dist/server.js”,
    “sidecar:linux”: “npm run build && pkg -t node20-linux-x64 -o ../src-tauri/bin/permit-backend dist/server.js”
  }
}

✅ Output binary will land at:

src-tauri/bin/permit-backend(.exe on Windows)


⸻

2) Tell Tauri to bundle the sidecar

Edit: src-tauri/tauri.conf.json

Add externalBin:

{
  “tauri”: {
    “bundle”: {
      “active”: true,
      “targets”: “all”,
      “externalBin”: [“bin/permit-backend”]
    }
  }
}

That tells Tauri to ship the binary inside your app bundle.

⸻

3) Spawn the sidecar properly (the correct Tauri way)

Edit: src-tauri/src/main.rs

Replace the old spawn code with this:

#![cfg_attr(not(debug_assertions), windows_subsystem = “windows”)]

use tauri::{Manager};
use tauri::api::process::{Command, CommandEvent};

fn main() {
  tauri::Builder::default()
    .setup(|app| {
      let app_handle = app.handle();

      // Spawn the bundled sidecar backend
      tauri::async_runtime::spawn(async move {
        let (mut rx, _child) = Command::new_sidecar(“permit-backend”)
          .expect(“failed to create sidecar command”)
          .env(“PORT”, “47831”)
          .spawn()
          .expect(“failed to spawn sidecar”);

        // Optional: log backend stdout/stderr (useful for debugging)
        while let Some(event) = rx.recv().await {
          if let CommandEvent::Stdout(line) = event {
            println!(“[backend] {}”, line);
          }
          if let CommandEvent::Stderr(line) = event {
            eprintln!(“[backend err] {}”, line);
          }
        }
      });

      Ok(())
    })
    .run(tauri::generate_context!())
    .expect(“error while running tauri application”);
}

✅ Now the backend starts automatically on app launch.

⸻

4) Add root scripts to build sidecar easily

In your root package.json (frontend root), add:

{
  “scripts”: {
    “backend:sidecar:win”: “cd backend && npm run sidecar:win”,
    “backend:sidecar:mac-arm”: “cd backend && npm run sidecar:mac-arm”,
    “backend:sidecar:mac-x64”: “cd backend && npm run sidecar:mac-x64”,
    “backend:sidecar:linux”: “cd backend && npm run sidecar:linux”
  }
}


⸻

5) Build process (what you actually run)

✅ Windows build:

npm run backend:sidecar:win
npm run tauri:build

✅ macOS Apple Silicon:

npm run backend:sidecar:mac-arm
npm run tauri:build

✅ macOS Intel:

npm run backend:sidecar:mac-x64
npm run tauri:build

✅ Linux:

npm run backend:sidecar:linux
npm run tauri:build


⸻

6) Important note about cross-compiling

You typically build the binary on the same OS you’re targeting.

So:
	•	Build Windows sidecar on Windows
	•	Build macOS sidecar on macOS
	•	Build Linux sidecar on Linux

(You can cross-build in CI with runners for each OS — that’s the normal pro approach.)

⸻

7) One real-world warning: better-sqlite3 + pkg

better-sqlite3 is a native module, so it must be available correctly in the packaged runtime.

✅ It usually works fine if:
	•	you build the sidecar on that same OS
	•	dependencies install cleanly before packaging

If you hit a native binding issue, the fallback that never fails is:

✅ switch backend sqlite driver to sqlite3 (slower, but safer)
OR
✅ use sql.js (pure JS) (local-first but different performance model)

Most of the time you won