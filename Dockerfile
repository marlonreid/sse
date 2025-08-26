import React, { useEffect, useState } from "react";
import { PublicClientApplication } from "@azure/msal-browser";
import { MsalProvider, useMsal } from "@azure/msal-react";

// ---- CONFIG ----
const tenantSubdomain = "your-tenant-subdomain"; // e.g. "woodgrove"
const tenantId = "YOUR_EXTERNAL_TENANT_GUID";
const spaClientId = "YOUR_SPA_APP_CLIENT_ID";
const apiScope = "api://YOUR_API_APP_CLIENT_ID/Catalog.Read";

const msalConfig = {
  auth: {
    clientId: spaClientId,
    authority: `https://${tenantSubdomain}.ciamlogin.com/${tenantId}/`,
    redirectUri: `${window.location.origin}/auth`,
  },
  cache: { cacheLocation: "localStorage" },
};

// Create a single PCA and kick off initialization ONCE.
const pca = new PublicClientApplication(msalConfig);
const initPromise = pca.initialize();

// ---- HELPERS ----
function buildLoginRequest(domainHint) {
  return { scopes: [apiScope, "openid", "profile"], ...(domainHint ? { domainHint } : {}) };
}
function getDomainHint() {
  const url = new URL(window.location.href);
  return url.searchParams.get("dh") || undefined;
}
async function getUserApps(pca, account) {
  const req = buildLoginRequest(getDomainHint());
  const tokenResp =
    (await pca.acquireTokenSilent({ ...req, account }).catch(() => pca.acquireTokenRedirect(req))) || {};
  const resp = await fetch("/me/apps", {
    headers: { Authorization: `Bearer ${tokenResp.accessToken}` },
  });
  if (!resp.ok) throw new Error("API " + resp.status);
  return resp.json();
}

// ---- UI ----
function Catalog() {
  const { instance } = useMsal();
  const [apps, setApps] = useState(null);
  const [err, setErr] = useState(null);

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        // 1) Ensure MSAL is initialized
        await initPromise;

        // 2) Complete any pending redirect and normalize URL
        await instance.handleRedirectPromise();
        if (window.location.pathname === "/auth") {
          try {
            window.history.replaceState(null, "", "/");
          } catch {}
        }

        // 3) Ensure account
        let account = instance.getAllAccounts()[0];
        if (!account) {
          await instance.loginRedirect(buildLoginRequest(getDomainHint()));
          return; // navigation away
        }

        // 4) Call API for assigned apps
        const data = await getUserApps(instance, account);
        if (!mounted) return;
        setApps(data);
      } catch (e) {
        if (!mounted) return;
        setErr(e?.message || String(e));
      }
    })();
    return () => {
      mounted = false;
    };
  }, [instance]);

  if (err) return <div style={{ color: "crimson" }}>Error: {err}</div>;
  if (apps === null) return <div>Loading…</div>;
  if (apps.length === 0) return <div>No assigned apps.</div>;

  return (
    <div style={{ maxWidth: 900, margin: "2rem auto", fontFamily: "system-ui, sans-serif" }}>
      <h1>Your Applications</h1>
      <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 12 }}>
        {apps.map((a) => (
          <li
            key={a.servicePrincipalId}
            onClick={() =>
              window.location.assign(a.userAccessUrl || a.loginUrl || a.homepage || "#")
            }
            style={{
              border: "1px solid #ddd",
              borderRadius: 12,
              padding: 16,
              cursor: "pointer",
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
            }}
          >
            <div>
              <div style={{ fontWeight: 600 }}>{a.displayName}</div>
              <div style={{ fontSize: 12, color: "#555" }}>
                {a.homepage || a.loginUrl || a.userAccessUrl}
              </div>
            </div>
            {a.appRoleAssignmentRequired && <span title="Assignment required">🔒</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}

function App() {
  // We still render the provider immediately; children wait for initPromise above.
  return (
    <MsalProvider instance={pca}>
      <Catalog />
    </MsalProvider>
  );
}

export default App;
