# Entra External ID – minimal app catalog (C# + React)

> Lightweight setup: one External tenant, one minimal ASP.NET Core API, one React SPA. Users sign in to your **External** tenant only, see only the apps they’re assigned to, and launch each app via its **User access URL** (or `loginUrl`/`homepage`). Unassigned users are blocked by Entra (AADSTS50105).

---

## 0) What you’ll create

* **External tenant** with **organizational branding** (logo/colors) and **User assignment required** on each enterprise app.
* **Catalog API (C#)** – queries Microsoft Graph for the signed-in user’s app assignments and returns launch links.
* **Catalog SPA (React)** – authenticates, calls the API, and renders the app catalog. Optional domain‑based routing via `domain_hint`.

---

## 1) Entra (External tenant) setup

1. **Create / switch to External tenant**

   * Create an External tenant (External ID for customers) if you don’t already have one.
2. **Brand the sign‑in page**

   * Entra ID → External Identities → Organizational branding → add logo, background, colors.
3. **Register apps**

   * **Catalog API** (confidential): Expose API scope `api://{API_CLIENT_ID}/App.Read`. Add client secret.
   * **Catalog SPA** (public): Redirect URIs `http://localhost:5173`, type SPA.
   * On the SPA, add **API permission** to the Catalog API (`App.Read`) and grant admin consent.
4. **Enterprise apps you want to list**

   * Add your SaaS or your own app instances under **Enterprise applications**.
   * Open each app → **Properties** → set **User assignment required? = Yes**.
   * (Optional) Copy **User access URL** from **Properties**. If the Graph `loginUrl` is empty for the app, paste the User access URL into **Notes** so the API can pick it up.
5. **Add users** to the External tenant (email sign‑in or local accounts) and **assign** them to the enterprise apps.

> Tip: Group assignments work; the API uses `/me/appRoleAssignments` which includes roles granted via direct group membership.

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
    "Instance": "https://login.microsoftonline.com/",
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
        var instance = cfg["AzureAd:Instance"];
        var tenantId = cfg["AzureAd:TenantId"];
        options.Authority = $"{instance}{tenantId}/v2.0";
        options.Audience = cfg["AzureAd:Audience"]; // api://<API_CLIENT_ID>
        options.TokenValidationParameters.ValidAudience = cfg["AzureAd:Audience"];
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

// Simple DTOs
record GraphList<T>([property: JsonPropertyName("value")] List<T> Value);
record AppRoleAssignment(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("resourceId")] string ResourceId,
    [property: JsonPropertyName("appRoleId")] string AppRoleId,
    [property: JsonPropertyName("resourceDisplayName")] string ResourceDisplayName
);

record ServicePrincipal(
    string? id,
    string? displayName,
    string? loginUrl,
    string? homepage,
    bool? appRoleAssignmentRequired,
    string? notes
);

record AppLink(string id, string name, string? launchUrl, bool? assignmentRequired);

app.MapGet("/api/apps", async (HttpContext http, IHttpClientFactory httpClientFactory, TokenCredential cred) =>
{
    var oid = http.User.FindFirst("oid")?.Value
              ?? http.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value;
    if (string.IsNullOrEmpty(oid)) return Results.Unauthorized();

    // App-only Graph token (Directory.Read.All app perm consented once)
    var token = await cred.GetTokenAsync(new TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }));

    var graph = httpClientFactory.CreateClient("graph");
    graph.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
    graph.DefaultRequestHeaders.Add("ConsistencyLevel", "eventual");

    // 1) Which apps is the user assigned to?
    var assignments = await graph.GetFromJsonAsync<GraphList<AppRoleAssignment>>($"users/{oid}/appRoleAssignments?$count=true");
    var spIds = (assignments?.Value ?? new()).Select(a => a.ResourceId).Distinct().ToList();

    // 2) Fetch each service principal to get launch URLs
    var results = new List<AppLink>();
    foreach (var spId in spIds)
    {
        var sp = await graph.GetFromJsonAsync<ServicePrincipal>($"servicePrincipals/{spId}?$select=id,displayName,loginUrl,homepage,appRoleAssignmentRequired,notes");
        if (sp is null) continue;

        // Prefer loginUrl; then homepage; then first URL found in notes (admin can paste User access URL there if needed)
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

> The API validates the JWT from the External tenant, then uses **app-only Graph** to enumerate the signed‑in user’s app assignments and resolve launch URLs.

---

## 3) React SPA – `CatalogSpa`

Create a Vite React app (or CRA if you prefer):

```bash
npm create vite@latest CatalogSpa -- --template react
cd CatalogSpa
npm i @azure/msal-browser @azure/msal-react
```

### `src/msal.js`

```javascript
import { PublicClientApplication } from "@azure/msal-browser";

export const msalConfig = {
  auth: {
    clientId: "<SPA_CLIENT_ID>",
    authority: "https://login.microsoftonline.com/<EXTERNAL_TENANT_ID>",
    redirectUri: "http://localhost:5173"
  },
  cache: { cacheLocation: "localStorage", storeAuthStateInCookie: false }
};

export const loginRequest = (email) => ({
  scopes: ["api://<API_CLIENT_ID>/App.Read"],
  loginHint: email || undefined,
  extraQueryParameters: email ? { domain_hint: email.split("@")[1] } : undefined
});

export const pca = new PublicClientApplication(msalConfig);
```

### `src/App.jsx`

```jsx
import { useEffect, useState } from "react";
import { MsalProvider, useMsal, useIsAuthenticated } from "@azure/msal-react";
import { pca, loginRequest } from "./msal";

const API_BASE = "http://localhost:5000"; // change if needed

function Catalog() {
  const { instance, accounts } = useMsal();
  const [email, setEmail] = useState("");
  const isAuthed = useIsAuthenticated();
  const [apps, setApps] = useState([]);
  const [loading, setLoading] = useState(false);

  const signIn = async () => {
    await instance.loginRedirect(loginRequest(email));
  };

  const loadApps = async () => {
    setLoading(true);
    try {
      const account = accounts[0];
      const token = await instance.acquireTokenSilent({ ...loginRequest(), account });
      const res = await fetch(`${API_BASE}/api/apps`, {
        headers: { Authorization: `Bearer ${token.accessToken}` }
      });
      const data = await res.json();
      setApps(data);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { if (isAuthed) loadApps(); }, [isAuthed]);

  if (!isAuthed) {
    return (
      <div className="p-8 max-w-md mx-auto">
        <h1>Sign in</h1>
        <p>Users authenticate only through your External tenant.</p>
        <input placeholder="you@company.com" value={email} onChange={(e)=>setEmail(e.target.value)} style={{width:'100%',padding:8,margin:'8px 0'}} />
        <button onClick={signIn}>Sign in</button>
      </div>
    );
  }

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

export default function App() {
  return (
    <MsalProvider instance={pca}>
      <Catalog />
    </MsalProvider>
  );
}
```

### Run it locally

```bash
# in CatalogApi
 dotnet run --urls http://localhost:5000

# in CatalogSpa
 npm run dev  # (Vite defaults to http://localhost:5173)
```

---

## 4) How launch links are resolved

The API prefers, in order:

1. `servicePrincipal.loginUrl` (what My Apps uses for most SAML/OIDC/linked apps).
2. `servicePrincipal.homepage`.
3. First URL found in **Notes** (paste the **User access URL** here if `loginUrl` is empty for that app type).

This keeps the catalog lightweight without needing extra storage.

---

## 5) Proving access control

* With **User assignment required = Yes** on an enterprise app, an **unassigned** user who opens the direct link is blocked by Entra with error **AADSTS50105**.
* An **assigned** user sees the app in the catalog and can launch it via the same link.

---

## 6) Optional: domain‑based routing

* The SPA passes `domain_hint` (derived from the email field) on the login request to nudge home realm discovery and show the right branding quickly.
* If you have multiple brands on your External tenant, create separate entry points (or tenant‑specific authorities) and toggle which one the SPA uses based on domain.

---

## 7) Security + notes

* The API uses **app‑only** Graph with `Directory.Read.All` to avoid high‑privilege delegated consent for every user. Lock down the API and keep the client secret safe.
* If you host on Azure, consider a **Managed Identity** for the API instead of a client secret.
* You can batch service principal lookups via Graph `$batch` for fewer network hops if your catalog is large.

---

## 8) Minimal test plan

1. Create two users: **Alice** (assigned to App A) and **Bob** (unassigned).
2. Alice signs in → catalog shows App A → **Launch** works.
3. Bob signs in → catalog shows empty state.
4. Bob tries App A’s direct link → Entra blocks with AADSTS50105.

---

**That’s it.** This is the lightest possible path: External tenant brand + app assignment, a tiny API to read assignments, and a tiny SPA to render and launch.
