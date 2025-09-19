ADR: Choose Identity Broker — Keycloak vs Duende IdentityServer

Status: Proposed
Date: 2025-09-19
Context: We need an identity broker in front of Microsoft Entra ID (Azure AD). The broker will front our apps (OIDC/OAuth2), delegate authentication to Entra, and manage client registrations, flows, and session management. Two candidates: Keycloak and Duende IdentityServer.

Table of Contents

Goals & Scope

Options

Comparison Summary

Protocol & Feature Support

Licensing & Cost

Development Effort (est.)

Infrastructure Effort (est.)

Risks & Mitigations

Decision (Proposed)

Consequences

References

1) Goals & Scope

Use broker pattern: external authentication to Entra ID; issue tokens to our apps.

Support OIDC/OAuth2 (and optionally SAML for some legacy SPs).

Support many client apps (potentially hundreds+).

Operate in Kubernetes with HA, monitoring, and sensible backup/DR.

2) Options

Option A — Keycloak (open-source IdP) acting as an identity broker to Entra. 
Keycloak
+1

Option B — Duende IdentityServer (commercial .NET framework) used to build a custom OIDC provider that federates to Entra as an external provider. 
Duende Software Docs
+2
Duende Software Docs
+2

3) Comparison Summary
Dimension	Keycloak	Duende IdentityServer
Nature	Product with admin console & ready-to-run server	Framework/SDK you assemble into an auth server
Protocols	OIDC, OAuth2.0, SAML 2.0; built-in brokering	OIDC/OAuth2.x; brokering via ASP.NET external providers (no native SAML)
Entra as IdP	Built-in identity brokering to OIDC/SAML IdPs	Add Entra as external OIDC provider in ASP.NET
Admin UI	Rich, built-in	Build your own (or adopt a third-party)
Licensing	Apache 2.0 OSS; optional Red Hat build/support	Commercial subscription; $20k/yr Enterprise for unlimited clients
Dev Effort	Lower (configure & theme)	Higher (build login/consent/admin, glue code)
Infra Effort	Higher (Java, Postgres, clustering/caches)	Lower–Moderate (typical ASP.NET app footprint)

Citations: 
duendesoftware.com
+6
Keycloak
+6
Keycloak
+6

4) Protocol & Feature Support

Keycloak

OIDC & OAuth 2.0; SAML 2.0; identity brokering to external OIDC/SAML IdPs (fits Entra). 
Keycloak
+1

Clustering & distributed caches (Infinispan) for HA; requires a database (commonly PostgreSQL). 
Keycloak
+1

Duende IdentityServer

Standards-compliant OIDC/OAuth 2.x framework; OpenID Certified; you compose flows in ASP.NET Core. 
duendesoftware.com
+1

External providers (e.g., Entra) via standard ASP.NET authentication handlers; SAML would require separate components. 
Duende Software Docs
+1

5) Licensing & Cost

Keycloak: Apache 2.0 (no license fee). Optional enterprise support via Red Hat build of Keycloak. 
GitHub
+2
Red Hat Customer Portal
+2

Duende IdentityServer: Annual subscription. Enterprise Edition includes unlimited client IDs at $20,000 USD/year (matches our expectation for “unlimited”). Lower tiers cap client IDs (e.g., Business = 15 clients, with $500 per extra client). 
duendesoftware.com

You noted we’ll need the $20k USD Duende license for unlimited client IDs — that aligns with Duende’s Enterprise pricing. 
duendesoftware.com

6) Development Effort (rough estimate, initial rollout)

Assumptions: federation to Entra (OIDC), ~50–200 client apps over time, branded login/consent, basic self-service client registration for internal teams, audit logging, and CI/CD. Team skill: mixed; solid .NET capability available.

Keycloak

Config & federation to Entra: 16–40 hrs

Realm/clients/scopes/policies setup: 40–80 hrs

Themes (login/email/consent): 40–80 hrs

User federation/group mapping (if needed): 16–40 hrs

Automation (Terraform/Helm/CLI) & CI/CD: 40–80 hrs

Observability (Prometheus/Grafana), backups, runbooks: 32–56 hrs

Total dev/config effort: ~184–376 hrs (≈ 4.5–9.5 weeks for 1 FTE)

Duende IdentityServer

Project bootstrap & security hardening: 40–80 hrs

External login (Entra) & brokering UX: 40–80 hrs

Login/consent UI + session mgmt: 80–140 hrs

Client & scope admin (custom portal or adopt 3rd-party): 80–160 hrs

Token customization, claims mapping, refresh/offline tokens: 40–80 hrs

Automation, CI/CD, observability, runbooks: 40–80 hrs

Total dev effort: ~320–620 hrs (≈ 8–15.5 weeks for 1 FTE)

Rationale: Keycloak ships a production-ready server and admin UI; most work is configuration & theming. Duende is a framework—powerful, but you build/admin much of the surface yourself. 
Duende Software Docs

7) Infrastructure Effort (rough estimate, initial rollout)

Keycloak

Kubernetes deployment (HA), Postgres provisioning, secrets/keystores, ingress, horizontal scaling, Infinispan caches tuning, backups/DR: ~80–140 hrs

Ongoing ops (patch cadence, realm migrations, perf tuning): 2–4 days/quarter

References: DB dependency, clustering/caches. 
Keycloak
+1

Duende IdentityServer

Package as ASP.NET Core service; stateless deployment; choose backing store (for config/operational data) as needed; ingress, scaling, cert rotation: ~40–80 hrs

Ongoing ops: 1–2 days/quarter

References: It’s “run like any ASP.NET app”; infra tends to be lighter than Keycloak’s JVM + cache cluster. 
Duende Software Docs

These are conservative ranges; parallelizing work shortens calendar time.

8) Risks & Mitigations

Client scale with Duende: licensing must remain at Enterprise to avoid per-client creep. Mitigation: lock in Enterprise tier budgeting. 
duendesoftware.com

SAML needs: Keycloak has native SAML; Duende would require additional components. Mitigation: confirm SAML roadmap; if SAML is required, Keycloak reduces scope risk. 
Keycloak

Operational complexity (Keycloak): clustering/cache tuning and DB management add ops overhead. Mitigation: reference architectures and Red Hat build if support SLAs are needed. 
Keycloak
+2
Red Hat Developer
+2

Customization depth (Duende): higher upfront engineering. Mitigation: phased rollout; reuse company UI libraries; consider 3rd-party admin UI if acceptable. 
Duende Software Docs

9) Decision (Proposed)

Choose Keycloak as the identity broker in front of Entra ID.

Why:

Zero license fee (unless we opt into Red Hat support), versus $20k/yr for Duende at our client scale. 
duendesoftware.com
+1

Faster time-to-value due to built-in admin, flows, and SAML support. 
Keycloak

Well-trodden Entra brokering path. 
Keycloak

When to revisit: If we need deep, bespoke protocol behaviors and programmatic control that outstrip Keycloak’s SPIs/themes—or we want a purely .NET stack with minimal Java ops—Duende IdentityServer becomes attractive despite the license cost. 
Duende Software Docs

10) Consequences

Pros (Keycloak): lower TCO, quicker rollout, SAML covered, mature admin features.

Cons (Keycloak): more intricate ops (JVM, Postgres, cache clustering), upgrade hygiene needed.

Pros (Duende): maximal flexibility in .NET; slim runtime; easy to integrate in existing ASP.NET ecosystem.

Cons (Duende): license cost at our scale; higher initial dev; SAML requires add-ons.

11) References

Keycloak features & brokering (OIDC/OAuth2/SAML): 
Keycloak
+1

Keycloak storage & HA notes (Postgres, caches/Infinispan): 
Keycloak
+2
Keycloak
+2

Red Hat build of Keycloak (commercial support): 
Red Hat Customer Portal
+1

Duende IdentityServer docs & positioning (framework): 
Duende Software Docs

Duende external IdPs (Entra as external provider): 
Duende Software Docs
+1

Duende pricing (Enterprise $20k/yr, unlimited clients): 
duendesoftware.com
