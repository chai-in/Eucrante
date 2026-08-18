# Eucrante backend

This package is the user-owned Cloudflare half of Eucrante. It contains the narrow HTTPS API, private R2 job store, and a Cloudflare Container wrapper for the upstream Cobalt v11 image.

It is intentionally not a shared service. Each user deploys it into their own account and chooses their own Cloudflare Access policy. The R2 bucket is private and completed jobs have no automatic expiration.

Do not deploy yet. The first deployment requires an authenticated Wrangler session, a unique R2 bucket name, and an explicit review of the account-specific Access and WARP policy described in [`../Docs/CLOUDFLARE.md`](../Docs/CLOUDFLARE.md).
