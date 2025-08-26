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
}
