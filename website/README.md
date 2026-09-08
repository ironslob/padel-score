# Wrist Rally website

Static marketing site for [wristrally.com](https://wristrally.com) — the padel scorekeeper for Apple Watch, Garmin, and Wear OS.

HTML, CSS, and a little JavaScript. No build step, no bundler, no backend.

```text
website/
├── index.html          Landing page
├── support.html
├── privacy.html
├── terms.html
├── contact.html
├── css/styles.css
├── js/site.js          Nav, watch bezel switcher, live score demo
└── assets/             Logo mark, favicon, padel ball
```

## Run locally

From the repo root, serve the `website` folder so relative asset paths resolve:

```bash
# Python 3 (usually preinstalled)
python3 -m http.server 8080 --directory website
```

Then open [http://localhost:8080](http://localhost:8080).

Other options:

```bash
# Node
npx --yes serve website -p 8080

# PHP
php -S localhost:8080 -t website
```

Opening `index.html` as a `file://` URL works for a quick look, but a local server is closer to production (fonts, and any future fetch).

## What to click when testing

1. **Home** — hero copy, three-platform trust row, interactive watch.
2. **Score demo** — tap Us / Them; scores should move 0 → 15 → 30 → 40 → game. Tap the same side again within 3 seconds to undo (ring on the button). Switch Apple Watch / Garmin / Wear OS bezels; the score UI stays the same.
3. **Nav** — Features, Platforms, How it works, FAQ, Get the app. On a narrow viewport, use the menu button.
4. **FAQ** — open/close accordion items.
5. **Support / Privacy / Terms / Contact** — inner pages, header and footer links, mailto addresses.
6. **Download** — store buttons are placeholders (`Coming soon`) until listings exist. Swap the `href` on each `.store-btn` in `index.html`.

Resize to ~390px width and to desktop. Check that the sticky header, watch mockup, and feature grid do not overflow.

## Publishing later

Point wristrally.com at this folder as the site root (GitHub Pages, Netlify, Cloudflare Pages, nginx, etc.). Add a `CNAME` file only if the host needs it. When App Store / Connect IQ / Play Store URLs exist, replace the three `#download` placeholders in `index.html`.
