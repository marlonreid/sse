import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, useNavigate } from "react-router-dom";
import { PublicClientApplication } from "@azure/msal-browser";
import { MsalProvider, useMsal } from "@azure/msal-react";

// --- MSAL config ---
const tenantSubdomain = "your-tenant-subdomain";   // e.g. "woodgrove"
const tenantId = "YOUR_EXTERNAL_TENANT_GUID";
const spaClientId = "YOUR_SPA_APP_CLIENT_ID";
const apiScope = "api://YOUR_API_APP_CLIENT_ID/Catalog.Read";

const msalConfig = {
  auth: {
    clientId: spaClientId,
    authority: `https://${tenantSubdomain}.ciamlogin.com/${tenantId}/`,
    redirectUri: `${window.location.origin}/auth`,
    postLogoutRedirectUri: `${window.location.origin}/`
  },
  cache: { cacheLocation: "localStorage" }
};
const pca = new PublicClientApplication(msalConfig);

function buildLoginRequest(domainHint) {
  return {
    scopes: [apiScope, "openid", "profile"],
    ...(domainHint ? { domainHint } : {})
  };
}

// --- helpers ---
function getDomainHint() {
  const url = new URL(window.location.href);
  const q = url.searchParams.get("dh");
  if (q) return q;
  const hostMap = {
    "apps.contoso.com": "contoso.com"
  };
  return hostMap[window.location.hostname];
}

async function getUserApps(pca, account) {
  const req = buildLoginRequest(getDomainHint());
  const tokenResp = await pca.acquireTokenSilent({ ...req, account })
    .catch(() => pca.acquireTokenRedirect(req));
  const token = tokenResp.accessToken;
  const resp = await fetch("/me/apps", {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!resp.ok) throw new Error("API " + resp.status);
  return resp.json();
}

// --- components ---
function AuthCallback() {
  const { instance } = useMsal();
  const navigate = useNavigate();
  useEffect(() => {
    instance.handleRedirectPromise().finally(() => navigate("/"));
  }, [instance, navigate]);
  return <div>Signing you in…</div>;
}

function Catalog() {
  const { instance, accounts } = useMsal();
  const [apps, setApps] = useState(null);
  const [err, setErr] = useState(null);

  useEffect(() => {
    if (accounts.length === 0) return;
    getUserApps(instance, accounts[0])
      .then(setApps)
      .catch(e => setErr(e.message || String(e)));
  }, [instance, accounts]);

  if (err) return <div style={{color:"crimson"}}>Error: {err}</div>;
  if (apps === null) return <div>Loading your apps…</div>;
  if (apps.length === 0) return <div>No assigned apps yet.</div>;

  return (
    <div style={{ maxWidth: 900, margin:"2rem auto", fontFamily:"system-ui" }}>
      <h1>Your Applications</h1>
      <ul style={{ listStyle:"none", padding:0, display:"grid", gap:12 }}>
        {apps.map(a => (
          <li key={a.servicePrincipalId}
              onClick={() => window.location.assign(a.userAccessUrl || a.loginUrl || a.homepage || "#")}
              style={{ border:"1px solid #ddd", borderRadius:12, padding:16, cursor:"pointer",
                       display:"flex", justifyContent:"space-between", alignItems:"center" }}>
            <div>
              <div style={{ fontWeight:600 }}>{a.displayName}</div>
              <div style={{ fontSize:12, color:"#555" }}>
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
  const { instance, accounts } = useMsal();
  const navigate = useNavigate();

  useEffect(() => {
    if (window.location.pathname === "/auth") return;
    if (accounts.length === 0) {
      instance.loginRedirect(buildLoginRequest(getDomainHint()));
    } else if (window.location.pathname === "/auth") {
      navigate("/");
    }
  }, [accounts, instance, navigate]);

  return (
    <Routes>
      <Route path="/auth" element={<AuthCallback />} />
      <Route path="/" element={<Catalog />} />
    </Routes>
  );
}

// --- render ---
ReactDOM.createRoot(document.getElementById("root")).render(
  <MsalProvider instance={pca}>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </MsalProvider>
);
