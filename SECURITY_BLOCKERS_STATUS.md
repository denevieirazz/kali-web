# SECURITY_BLOCKERS_STATUS.md

**Scope:** POC1 only. No Stage 2, App Manager, Firefox or GIMP.

**Containment certification:** NOT PERFORMED. This document records blocker remediation and regression coverage only.

**xclock executed by this remediation:** NO.

## B-01 — capability bypass

**Causa raiz:** the CloudOS proxy path carried a capability token, but the Xpra TCP listener itself used `auth=allow`. Any local process able to reach the loopback-forwarded Xpra port could bypass the CloudOS capability path.

**Correção:** each real POC1 session now generates an independent 256-bit Xpra password. Xpra starts with `auth=env` and `XPRA_PASSWORD`; the HTML5 client receives the password only inside the already capability-protected session URL. `auth=allow` was removed from the real runtime listener. The listener remains bound to `127.0.0.1` only.

**Regressão:** `linux-runtime-poc.test.js` asserts `auth=env`, rejects `auth=allow`, requires the password environment and preserves localhost-only binding.

**Impacto:** direct access to the loopback Xpra transport no longer grants an authenticated Xpra session without the per-session secret. No new application or Stage 2 surface was added.

**Resultado:** **PASSOU** at code/regression-contract level. Physical containment is not certified here.

## B-02 — cross-session isolation

**Causa raiz:** `ownerId` came from the CloudOS Window and was not namespaced by the authenticated principal. Some session operations could therefore be addressed using a client-controlled owner identifier.

**Correção:** runtime owner IDs are now namespaced with a SHA-256-derived authenticated-principal prefix plus the CloudOS Window owner. Mutating routes validate that the target session belongs to that scoped owner. Health polling validates authenticated-principal ownership before exposing session health.

**Regressão:** `linux-runtime-poc.test.js` proves identical Window IDs under different authenticated principals resolve to different owner namespaces.

**Impacto:** sessions from different authenticated CloudOS principals no longer share the same owner namespace. Existing per-window lifecycle semantics remain.

**Resultado:** **PASSOU** at code/regression-contract level.

## B-03 — iframe same-origin containment risk

**Causa raiz:** the Xpra HTML5 response was proxied through the CloudOS origin and the iframe allowed same-origin behavior, allowing the embedded document to retain a same-origin relationship with CloudOS.

**Correção:** the Xpra proxy now injects an HTTP CSP `sandbox` directive without `allow-same-origin`. The embedded Xpra document is therefore forced into an opaque origin even if the iframe element still contains an `allow-same-origin` token. The proxy also strips `Set-Cookie`, applies `no-referrer`, `no-store`, and keeps `frame-ancestors 'self'`.

**Regressão:** `linux-runtime-poc.test.js` asserts that the emitted CSP contains the sandbox but never `allow-same-origin`, and verifies cookie stripping/referrer policy.

**Impacto:** parent/iframe DOM same-origin access is removed at the response policy boundary. This can intentionally make old `contentDocument`-based preflight telemetry unavailable; that telemetry must fail closed rather than weakening the sandbox.

**Resultado:** **PASSOU** at policy/regression-contract level. No containment certification is claimed.

## B-04 — WSL interoperability escape

**Causa raiz:** POC1 previously removed WSLg display variables but did not require WSL Windows interoperability to be disabled. A Linux child could therefore retain the WSLInterop execution bridge to Windows executables.

**Correção:** readiness now inspects `/proc/sys/fs/binfmt_misc/WSLInterop` inside the selected distro and fails closed with `WSL_INTEROP_ENABLED` unless the effective WSLInterop handler is absent/disabled. POC1 will not start a real Linux app while interoperability remains enabled. Applying `/etc/wsl.conf` and restarting the distro remains an operator action; POC1 does not mutate host configuration automatically.

**Regressão:** `linux-runtime-poc.test.js` asserts the effective WSLInterop probe and fail-closed readiness gate exist.

**Impacto:** POC1 refuses execution instead of silently inheriting the Linux-to-Windows executable bridge. No host setting is changed automatically.

**Resultado:** **PASSOU** at code/regression-contract level; the physical host must satisfy the gate before a real app can start.

## Final

| Blocker | Resultado |
|---|---|
| B-01 capability bypass | **PASSOU** |
| B-02 cross-session isolation | **PASSOU** |
| B-03 iframe same-origin containment risk | **PASSOU** |
| B-04 WSL interoperability escape | **PASSOU** |

**POC1 status:** containment minimally isolated at the implemented boundary level. **This is not a containment certification.** A physical validation remains separate and was not performed by this remediation.
