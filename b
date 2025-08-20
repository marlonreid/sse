// scripts/build-meta.mjs
import { execSync } from "node:child_process";
import fs from "node:fs";
import pkg from "../package.json" assert { type: "json" };

function sh(cmd, fallback = "") {
  try { return execSync(cmd).toString().trim(); } catch { return fallback; }
}

const commit = process.env.GIT_COMMIT || sh("git rev-parse --short HEAD", "unknown");
const branch = process.env.GIT_BRANCH || sh("git rev-parse --abbrev-ref HEAD", "unknown");
const builtAt = new Date().toISOString();
const version = process.env.PKG_VERSION || pkg.version;

const content =
  `VITE_COMMIT=${commit}
VITE_BRANCH=${branch}
VITE_VERSION=${version}
VITE_BUILT_AT=${builtAt}
`;

fs.writeFileSync(".env.local", content);
console.log("[build-meta] wrote .env.local:\n" + content);
------------------------------------------------
{
  "scripts": {
    "predev": "node scripts/build-meta.mjs",
    "dev": "vite",
    "prebuild": "node scripts/build-meta.mjs",
    "build": "vite build",
    "preview": "vite preview"
  }
}

--------------------------------------------------------------
// src/buildInfo.ts
export const buildInfo = {
  commit: import.meta.env.VITE_COMMIT,
  branch: import.meta.env.VITE_BRANCH,
  version: import.meta.env.VITE_VERSION,
  builtAt: import.meta.env.VITE_BUILT_AT
} as const;
--------------------------------------------------------
// src/BuildStamp.tsx
import { buildInfo } from "./buildInfo";

export function BuildStamp() {
  return (
    <small style={{ opacity: 0.7 }}>
      v{buildInfo.version} · {buildInfo.commit} · {new Date(buildInfo.builtAt).toLocaleString()}
    </small>
  );
}
--------------------------------------
GIT_COMMIT=$GITHUB_SHA GIT_BRANCH=$GITHUB_REF_NAME npm run build
