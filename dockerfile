import { useEffect, useState } from "react";
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
