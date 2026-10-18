# Anasing landing page

A single-section Next.js App Router page for Anasing, inspired by the supplied minimal product-page reference. No external fonts, tracking, account, or backend.

```sh
cd landing
npm ci
npm run dev
```

Open http://localhost:3000. `npm run build` produces a static site in `out/`; `npm run typecheck` checks TypeScript. Deploy on Vercel by choosing **landing** as the root directory, or serve the contents of `out/` on a static host. The download button links to the GitHub beta release, where the DMG and corresponding sources must be uploaded before visitors can download them.

The page is responsive, uses English and Arabic copy, and includes the actual Anasing toolbar image in a small illustrative file-drag scene. Product requirements and the unsigned-beta notice are visible beside the download button.

License: AGPL-3.0-only; see the repository's LICENSE.
