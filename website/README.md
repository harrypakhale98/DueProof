# DueProof Website

Static marketing, privacy, and support website for DueProof.

## Preview

Open `index.html` directly in a browser, or serve the folder locally:

```sh
python3 -m http.server 8080 --directory website
```

Then visit:

```text
http://localhost:8080
```

## Files

- `index.html` - homepage and feature explainer.
- `privacy.html` - public privacy policy page.
- `support.html` - public support page.
- `styles.css` - shared responsive styling.
- `script.js` - mobile navigation and header polish.
- `assets/` - DueProof app icon assets.
- `site.webmanifest`, `favicon.png`, `apple-touch-icon.png`, `robots.txt`, `404.html` - hosting basics.

## Publish

This folder can be deployed as-is to any static host, including Cloudflare Pages, Vercel, Netlify, GitHub Pages, or S3-style hosting.

Before publishing:

1. Replace `support@dueproof.app` in `support.html` if the final domain or support inbox is different.
2. Update App Store links when the app is live.
3. Review `privacy.html` against the final App Store Connect privacy answers.
