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
├── js/site.js          Nav, reduced-motion video pause
├── assets/             Logo, favicon, simulator score clip
└── scripts/            Re-record the Watch simulator demo
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

1. **Home** — hero copy, looping Watch clip (a game from 0–0 through Game), three-platform trust row.
2. **Clip** — the hero video should autoplay, muted, and loop. A GIF lives at `assets/score-demo.gif` as a no-JS fallback.
3. **Nav** — Features, Platforms, How it works, FAQ, Get the app. On a narrow viewport, use the menu button.
4. **FAQ** — open/close accordion items.
5. **Support / Privacy / Terms / Contact** — inner pages, header and footer links, mailto addresses.
6. **Download** — store buttons are placeholders (`Coming soon`) until listings exist. Swap the `href` on each `.store-btn` in `index.html`.

Resize to ~390px width and to desktop. Check that the sticky header, watch mockup, and feature grid do not overflow.

## Re-record the Watch clip

Needs Xcode, a Watch simulator, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and `ffmpeg`.

```bash
website/scripts/record-score-demo.sh
```

That boots Apple Watch Series 11 (46mm), uninstalls leftover matches, and drives `MarketingDemoTests`: 15–0 (undo ring), 30–0, a Them tap that is undone, then 30–15, 40–15, Game, next game. Simulator video is trimmed to that sequence and encoded at 20 fps so the countdown ring keeps its in-between frames. GIF encode uses a single palette and `dither=none`. Override the device with `WATCH_UDID=…`.

## Publishing later

Point wristrally.com at this folder as the site root (GitHub Pages, Netlify, Cloudflare Pages, nginx, etc.). Add a `CNAME` file only if the host needs it. When App Store / Connect IQ / Play Store URLs exist, replace the three `#download` placeholders in `index.html`.
