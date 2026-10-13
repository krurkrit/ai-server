# Diagram rules (`diagrams/*.svg`)

What the three diagrams must show (two architecture diagrams for the guide, the development workflow for the team guide), and their palette, type, and line rules.

## Must match the guide

- `development-workflow.svg` shows the numbered steps of "The workflow" in `ai-setup-for-software-development.md`, with the same numbers, names, and tools. Blue boxes are steps that use the AI server; outlined boxes happen outside it (PC, GitHub, hosting, error tracker). Change both together.
- Only draw a line for a connection the guide actually sets up. Solid means it works by default; dashed means optional or manual.
- If a connection isn't really wired by the guide, **ask the user** whether to remove it, make it dashed, or add setup instructions. Don't decide silently.

## Palette

| Token | Color |
|---|---|
| Background | `#F8F9FA` |
| Text | `#34383C` |
| Muted text | `#52565B` |
| Primary / blue | `#1450A0` |
| Accent / orange | `#8A3F00` |
| Neutral fill | `#F1F3F5` |
| Dashed lines | `#8F94A0` |

Clusters use light tinted fills: blue `#EAF1FA` / `#B9CFE8`, orange `#FBF1E7` / `#E3C39A`.

## Type

Inter for text; JetBrains Mono for port numbers and digits.

| Element | Size / weight |
|---|---|
| Title | 18 / 700 |
| Box name | 13 / 700 |
| Subtext | 9.5 |
| Line labels | 11 |
| Cluster titles | 14 / 700 |

- In a two-line box, put the name baseline at 0.43 × height and the subtext at 0.745 × height.
- Both SVGs use viewBox width 1075, so equal font sizes render at the same size. Don't match sizes across different viewBox widths.

## Lines

- Orthogonal only (horizontal/vertical).
- Corners depend on whether the turn point is a junction:
  - **Sharp** at a junction: another line keeps going straight through the point where this line turns off (a T or branch point on a shared bus or trunk).
  - **Curved (radius 12, `Q`)** at a plain bend: nothing else continues past the point, e.g. the last box at either end of a bus, or a trunk turning at the margin.
- Two paths sharing a stretch must use the same corner type there, or they draw a visible seam.
- Every arrowhead needs a straight run of at least 16px into it.
- Labels sit beside lines and must not overlap boxes, other lines, or labels.

## Editing

- When scripting SVG edits, anchor the attribute regexes (`(?<![\w-])x=`, so they don't hit `rx` or `stroke-width`) and don't use `\g<1>` in sed.
- Check by rendering: open the SVG in the browser pane and screenshot it after every change.
- Then re-render its PNG for the Outline export at 2× (viewBox width × 2): wrap the SVG in an HTML page with zero margin and `overflow: hidden`, the SVG as `display: block` at its viewBox size (an inline SVG overflows by a few pixels and the PNG shows a scrollbar), and run headless Edge or Chrome with `--headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=<viewBox w>,<viewBox h> --virtual-time-budget=8000 --screenshot=outline-export/<name>.png`. The time budget lets the web fonts load; check the PNG shows Inter, not a fallback font.
- Every app that signs in through Dex (its own Dex button, or behind the sign-in gate) carries an "SSO" badge: a 36×16 pill (rx 8, fill `#F8F9FA`, text 9.5/700 `#1450A0`) inset 8px from the box's top-right corner. When the guide adds or removes Dex sign-in for an app, add or remove its badge. The legend's second row explains it.
- A new service box keeps the grid: same box size (155×90) and the same column centers as the rows above (178, 358, 538, 718, 898).
