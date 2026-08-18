# Eucrante backend

This package is the user-owned Cloudflare half of Eucrante. It contains the narrow HTTPS API, private R2 job store, and a Cloudflare Container wrapper for the upstream Cobalt v11 image.

It is intentionally not a shared service. Each user deploys it into their own account and chooses their own Cloudflare Access policy. The R2 bucket is private and completed jobs have no automatic expiration.

Before deploying, authenticate Wrangler, choose a unique R2 bucket and custom hostname, and review the account-specific Access and WARP policy described in [`../Docs/CLOUDFLARE.md`](../Docs/CLOUDFLARE.md).

The maintainer stack has been exercised end to end with an Access-protected custom domain, a WARP posture requirement, the pinned Cobalt container, and R2 create/read/delete operations. Each user still deploys and owns an independent copy.

Cobalt intentionally emits signed media transfers at the root `/tunnel` path even when its control API is mounted below `/v1/cobalt/`. The Worker forwards only that documented root media path plus the namespaced control API; unrelated container routes remain private.
