# Entra External ID – minimal app catalog (C# + React)

> Lightweight setup: one External tenant, one minimal ASP.NET Core API, one React SPA. Users sign in to your **External** tenant only, see only the apps they’re assigned to, and launch each app via its **User access URL** (or `loginUrl`/`homepage`). Unassigned users are blocked by Entra (AADSTS50105).

---

## 0) What you’ll create

* **External tenant** with **organizational branding** (logo/colors) and **User assignment required** on each enterprise app.
* **Catalog API (C#)** – queries Microsoft Graph for the signed-in user’s app assignments and returns launch links.
* **Catalog SPA (React)** – authenticates, calls the API, and renders the app catalog. Domain‑based routing is automatic (use `domain_hint` from the SPA’s own URL).

---

## 1) Entra (External tenant) setup

1. **Create / switch to External tenant**

   * Create an External tenant (External ID for customers) if you don’t already have one.
2. **Brand the sign‑in page**

   * Entra ID → External Identities → Organizational branding → add logo, background, colors.
3. **Register apps** (in the External tenant)

   * **Catalog API** (confidential): Expose API scope `api://{API_CLIENT_ID}/App.Read`. Add client secret.
   * **Catalog SPA** (public): Redirect URIs `http://localhost:5173`, type SPA.
   * On the SPA, add **API permission** to the Catalog API (`App.Read`) and grant admin consent.
4. **Enterprise apps you want to list**

   * Add your SaaS or your own app instances under **Enterprise applications**.
   * Open each app → **Properties** → set **User assignment required? = Yes**.
   * (Optional) Copy **User access URL** from **Properties**. If the Graph `loginUrl` is empty for the app, paste the User access URL into **Notes** so the API can pick it up.
5. **Add users** to the External tenant (email sign‑in or local accounts) and **assign** them to the enterprise apps.

> Tip: Group assignments work; the API uses `/users/{id}/appRoleAssignments` which includes roles granted via direct group membership.

---

## 2) C# minimal API – `CatalogApi`

Create a new empty web project:

```bash
mkdir CatalogApi && cd CatalogApi
 dotnet new web -n CatalogApi
```

### `appsettings.json`

```json
{
  "AzureAd": {
    "Authority": "https://<yourTenantSubdomain>.ciamlogin.com/<EXTERNAL_TENANT_ID>/v2.0",
    "TenantId": "<EXTERNAL_TENANT_ID>",
    "Audience": "api://<API_CLIENT_ID>",
    "ClientId": "<API_CLIENT_ID>",
    "ClientSecret": "<API_CLIENT_SECRET>"
  },
  "Cors": {
    "AllowedOrigins": ["http://localhost:5173"]
  }
}
```

### `Program.cs`

```csharp
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure.Core;
using Azure.Identity;
using Microsoft.AspNetCore.Authentication.JwtBearer;

var builder = WebApplication.CreateBuilder(args);
var cfg = builder.Configuration;

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = cfg["AzureAd:Authority"]; // CIAM authority
        options.Audience  = cfg["AzureAd:Audience"];  // api://<API_CLIENT_ID>
    });

builder.Services.AddAuthorization();

builder.Services.AddCors(o =>
{
    o.AddDefaultPolicy(p =>
        p.WithOrigins(cfg.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
         .AllowAnyHeader().AllowAnyMethod());
});

builder.Services.AddHttpClient("graph", c =>
{
    c.BaseAddress = new Uri("https://graph.microsoft.com/v1.0/");
});

builder.Services.AddSingleton<TokenCredential>(sp =>
    new ClientSecretCredential(
        cfg["AzureAd:TenantId"],
        cfg["AzureAd:ClientId"],
        cfg["AzureAd:ClientSecret"]));

var app = builder.Build();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

// DTOs
record GraphList<T>([property: JsonPropertyName("value")] List<T> Value);
record AppRoleAssignment(string Id, string ResourceId, string AppRoleId, string ResourceDisplayName);
record ServicePrincipal(string? id, string? displayName, string? loginUrl, string? homepage, bool? appRoleAssignmentRequired, string? notes);
record AppLink(string id, string name, string? launchUrl, bool? assignmentRequired);

app.MapGet("/api/apps", async (HttpContext http, IHttpClientFactory httpClientFactory, TokenCredential cred) =>
{
    var oid = http.User.FindFirst("oid")?.Value
              ?? http.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    if (string.IsNullOrEmpty(oid)) return Results.Unauthorized();

    var token = await cred.GetTokenAsync(new TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }));

    var graph = httpClientFactory.CreateClient("graph");
    graph.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
    graph.DefaultRequestHeaders.Add("ConsistencyLevel", "eventual");

    var assignments = await graph.GetFromJsonAsync<GraphList<AppRoleAssignment>>($"users/{oid}/appRoleAssignments?$count=true");
    var spIds = (assignments?.Value ?? new()).Select(a => a.ResourceId).Distinct().ToList();

    var results = new List<AppLink>();
    foreach (var spId in spIds)
    {
        var sp = await graph.GetFromJsonAsync<ServicePrincipal>($"servicePrincipals/{spId}?$select=id,displayName,loginUrl,homepage,appRoleAssignmentRequired,notes");
        if (sp is null) continue;

        string? launch = sp.loginUrl ?? sp.homepage;
        if (launch is null && !string.IsNullOrWhiteSpace(sp.notes))
        {
            var maybeUrl = System.Text.RegularExpressions.Regex.Match(sp.notes, "https?://\\S+").Value;
            if (!string.IsNullOrWhiteSpace(maybeUrl)) launch = maybeUrl;
        }

        results.Add(new AppLink(sp.id!, sp.displayName ?? "(Unnamed App)", launch, sp.appRoleAssignmentRequired));
    }

    return Results.Ok(results.OrderBy(r => r.name));
}).RequireAuthorization();

app.Run();
```

> The API validates the JWT from the External tenant using the **CIAM authority**, then uses **app-only Graph** (`Directory.Read.All`) to enumerate the signed‑in user’s app assignments and resolve launch URLs.

---

## 3) React SPA – `CatalogSpa`

Create a Vite React app (or CRA if you prefer):

```bash
npm create vite@latest CatalogSpa -- --template react
cd CatalogSpa
npm i @azure/msal-browser @azure/msal-react react-router-dom
```

### `src/msal.js`

```javascript
import { PublicClientApplication } from "@azure/msal-browser";

// Pull domain from the UI URL, e.g., https://acme.example.com -> example.com
const urlHost = window.location.hostname;
const domainHint = urlHost.includes(".") ? urlHost.split(".").slice(-2).join(".") : undefined;

export const msalConfig = {
  auth: {
    clientId: "<SPA_CLIENT_ID>",
    authority: "https://<yourTenantSubdomain>.ciamlogin.com/<EXTERNAL_TENANT_ID>",
    redirectUri: window.location.origin + "/auth" // add explicit /auth redirect route
  },
  cache: { cacheLocation: "localStorage", storeAuthStateInCookie: false }
};

export const loginRequest = {
  scopes: ["api://<API_CLIENT_ID>/App.Read"],
  extraQueryParameters: domainHint ? { domain_hint: domainHint } : {}
};

export const pca = new PublicClientApplication(msalConfig);
```

### `src/App.jsx`

```jsx
import { useEffect, useState } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { MsalProvider, useMsal, useIsAuthenticated } from "@azure/msal-react";
import { pca, loginRequest } from "./msal";

const API_BASE = "http://localhost:5000";

function AuthRedirect() {
  // lightweight page for MSAL to land on after auth
  return (
    <div style={{padding:24}}>
      <h2>Signing you in…</h2>
    </div>
  );
}

function Catalog() {
  const { instance, accounts, inProgress } = useMsal();
  const isAuthed = useIsAuthenticated();
  const [apps, setApps] = useState([]);
  const [loading, setLoading] = useState(false);

  // Auto-redirect to Entra if not signed in (no sign-in screen)
  useEffect(() => {
    if (!isAuthed && inProgress === "none") {
      instance.loginRedirect(loginRequest);
    }
  }, [isAuthed, inProgress, instance]);

  useEffect(() => {
    const loadApps = async () => {
      setLoading(true);
      try {
        const account = accounts[0];
        const token = await instance.acquireTokenSilent({ ...loginRequest, account });
        const res = await fetch(`${API_BASE}/api/apps`, {
          headers: { Authorization: `Bearer ${token.accessToken}` }
        });
        const data = await res.json();
        setApps(data);
      } finally {
        setLoading(false);
      }
    };
    if (isAuthed) loadApps();
  }, [isAuthed, accounts, instance]);

  if (!isAuthed) return null; // while on /auth redirect

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <h1>Your Apps</h1>
      {loading && <p>Loading…</p>}
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fill,minmax(260px,1fr))',gap:16}}>
        {apps.map(app => (
          <div key={app.id} style={{border:'1px solid #eee',borderRadius:12,padding:16}}>
            <div style={{fontWeight:600,marginBottom:8}}>{app.name}</div>
            <div style={{fontSize:12,opacity:0.7,marginBottom:8}}>
              {app.assignmentRequired ? "Assignment required" : "Open to all (tenant)"}
            </div>
            <button disabled={!app.launchUrl} onClick={()=> window.open(app.launchUrl, "_blank") }>
              {app.launchUrl ? "Launch" : "No launch URL"}
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

function Root() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/auth" element={<AuthRedirect />} />
        <Route path="/*" element={<Catalog />} />
      </Routes>
    </BrowserRouter>
  );
}

export default function App() {
  return (
    <MsalProvider instance={pca}>
      <Root />
    </MsalProvider>
  );
}
```

### Redirect route `/auth`

In `vite.config.js` or your hosting platform, ensure `/auth` points back to `index.html` so MSAL can process the login redirect.

---

## 4) How launch links are resolved

1. `servicePrincipal.loginUrl`
2. `servicePrincipal.homepage`
3. First URL found in **Notes** (User access URL if needed).

---

## 5) Proving access control

* With **User assignment required = Yes**, unassigned users get **AADSTS50105** if they try to launch directly.
* Assigned users see their apps in the catalog.

---

## 6) Domain‑based routing

* The SPA automatically sets `domain_hint` based on the SPA’s **own URL hostname**. No need for the user to type their email.
* Host separate subdomains per customer/brand, and the SPA passes the correct hint to Entra.

---

## 7) Security + notes

* API uses **app‑only** Graph with `Directory.Read.All`.
* Prefer Managed Identity in Azure instead of storing client secret.
* You can batch Graph calls with `$batch` for large catalogs.

---

## 8) Minimal test plan

1. Create two users: **Alice** (assigned) and **Bob** (unassigned).
2. Alice logs in via SPA URL → catalog shows her app(s) → launch works.
3. Bob logs in → empty catalog.
4. Bob tries direct link → Entra blocks with AADSTS50105.

---

**That’s it.** External tenant brand + assignments, tiny API + SPA. With `/auth` redirect and domain‑based `domain_hint`, the user experience is seamless.
