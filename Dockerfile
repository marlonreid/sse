import React, { useEffect, useState } from "react";
import { PublicClientApplication } from "@azure/msal-browser";
import { MsalProvider, useMsal } from "@azure/msal-react";

const tenantSubdomain = "your-tenant-subdomain";
const tenantId = "YOUR_EXTERNAL_TENANT_GUID";
const spaClientId = "YOUR_SPA_APP_CLIENT_ID";
const apiScope = "api://YOUR_API_APP_CLIENT_ID/Catalog.Read";

const msalConfig = {
  auth: {
    clientId: spaClientId,
    authority: `https://${tenantSubdomain}.ciamlogin.com/${tenantId}/`,
    redirectUri: `${window.location.origin}/auth`,
  },
  cache: { cacheLocation: "localStorage" }
};
const pca = new PublicClientApplication(msalConfig);

function buildLoginRequest(domainHint) {
  return { scopes: [apiScope, "openid", "profile"], ...(domainHint ? { domainHint } : {}) };
}

function getDomainHint() {
  const url = new URL(window.location.href);
  return url.searchParams.get("dh") || undefined;
}

async function getUserApps(pca, account) {
  const req = buildLoginRequest(getDomainHint());
  const tokenResp = await pca.acquireTokenSilent({ ...req, account })
    .catch(() => pca.acquireTokenRedirect(req));
  const resp = await fetch("/me/apps", {
    headers: { Authorization: `Bearer ${tokenResp.accessToken}` }
  });
  return resp.json();
}

function Catalog() {
  const { instance, accounts } = useMsal();
  const [apps, setApps] = useState(null);

  useEffect(() => {
    instance.handleRedirectPromise().then(() => {
      if (accounts.length === 0) {
        instance.loginRedirect(buildLoginRequest(getDomainHint()));
      } else {
        getUserApps(instance, accounts[0]).then(setApps);
      }
    });
  }, [instance, accounts]);

  if (!apps) return <div>Loading…</div>;
  if (apps.length === 0) return <div>No assigned apps.</div>;

  return (
    <ul>
      {apps.map(a => (
        <li key={a.servicePrincipalId}>
          <a href={a.userAccessUrl || a.loginUrl || a.homepage}>{a.displayName}</a>
        </li>
      ))}
    </ul>
  );
}

function App() {
  return (
    <MsalProvider instance={pca}>
      <Catalog />
    </MsalProvider>
  );
}

export default App;
