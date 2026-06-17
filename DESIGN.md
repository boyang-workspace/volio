# Volio Design System

Inspired by Apple Journal (iOS 26 / macOS Tahoe).

---

## Design Thesis

Volio is a quiet space for memories — a personal archive of a child's artwork. The design should feel like a **private journal for visual keepsakes**: calm, personal, and focused on the content. Every design decision serves the feeling of flipping through a carefully kept scrapbook.

**Memorable thing:** "This feels like a place for memories, not a tool for managing files."

---

## Visual Language

### Core Principles

| Principle | Application |
|---|---|
| **Content-first** | Images are full-bleed, text recedes into subtle hierarchy |
| **Quiet materials** | Soft gray backgrounds, thin borders, translucent chrome |
| **Generous whitespace** | Padding is spacious; breathing room around every piece |
| **Personal warmth** | Rounded corners, soft shadows, human-scale typography |
| **Journal-like** | The interface reads like a notebook, not a dashboard |

### Aesthetic Direction

- **Mood:** Calm, reflective, personal
- **Material analogy:** Smooth paper with a subtle glass overlay
- **Energy:** Gentle and unhurried — no sharp contrasts or loud colors
- **Architecture:** Content recedes and reveals itself through scrolling and selection

---

## Color System

### Token Map

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--background` | `oklch(96.5% 0.002 286)` | — | Page background |
| `--surface` | `oklch(100% 0 0)` | — | Cards, panels, inputs |
| `--overlay` | `oklch(100% 0 0)` | — | Modals, popovers |
| `--foreground` | `oklch(21% 0.006 286)` | — | Primary text |
| `--muted` | `oklch(55% 0.015 286)` | — | Secondary text, metadata |
| `--quiet` | `oklch(70% 0.01 286)` | — | Placeholders, captions |
| `--border` | `oklch(89% 0.004 286)` | — | Dividers, card borders |
| `--border-strong` | `oklch(82% 0.005 286)` | — | Hovered borders |
| `--accent` | `oklch(62% 0.195 254)` | — | Links, active states, buttons |

### Design Notes

- Near-monochrome with a single blue accent — Apple Journal's approach
- OKLCH color space for perceptual uniformity
- The accent blue (`#007aff`) is the same as iOS system blue
- Background sits between pure white and gray — warm, not clinical

---

## Typography

### Font Stack

```
font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
```

System native only — no custom font loading. Apple uses SF Pro; system-ui is the closest cross-platform equivalent.

### Type Scale

| Level | Size | Weight | Usage |
|---|---|---|---|
| Title | 16px | 700 | Artwork title in detail |
| Card title | 12px | 600 | Grid card labels |
| Body | 13px | 400 | Descriptions |
| Caption | 11px | 400 | Dates, metadata |
| Label | 10px | 700 | Section headers, uppercase + tracking |

### Line Length

- Detail text: max 65 characters per line
- Cards: naturally constrained by grid

---

## Spacing

Standard spacing unit: **4px**

| Token | Value | Usage |
|---|---|---|
| `--space-xs` | 4px | Tight icon gaps |
| `--space-sm` | 8px | Button padding, tag gaps |
| `--space-md` | 12px | Card grid gaps |
| `--space-lg` | 16px | Panel padding |
| `--space-xl` | 24px | Section spacing |
| `--space-2xl` | 32px | Page padding bottom |

---

## Layout

### Application Shell

```
┌──────────────┬──────────────────────┬──────────────┐
│    Sidebar   │    Main Content       │   Detail     │
│   190px      │    1fr                │   420px      │
├──────────────┴──────────────────────┴──────────────┤
│               100vh · min-width: 800px              │
└────────────────────────────────────────────────────┘
```

- 3-column layout for Mac screen real estate
- Detail pane slides away on smaller windows (responsive)
- Sidebar remains fixed

### Works Grid

- Auto-fill columns, `minmax(170px, 1fr)`
- 12px gap between cards
- Masonry variant uses CSS columns (`column-count: 5`)
- Timeline variant groups by date with a vertical axis

---

## Component Language

### Cards (Work Cards)

```
┌──────────────────┐
│                   │
│    Full-bleed     │
│    Thumbnail      │  aspect-ratio: 4/3
│                   │
├──────────────────┤
│ Title             │
│ Date              │  ← metadata
└──────────────────┘
```

- Rounded corners: 8px
- Thin border: 1px `--border`
- Shadow: subtle surface shadow
- Hover: border darkens, shadow deepens
- Active: accent border + focus ring

### Buttons

- Use HeroUI `Button` component
- Variants: solid (primary), ghost (secondary), light (tertiary)
- Sizes: sm (32px), md (38px), lg (44px)
- Border radius: 6px
- Transition: border-color, background, shadow — 150ms cubic-bezier

### Chips/Tags

- Rounded pill shape (9999px radius)
- Small type: 11px
- Colored variants: default (gray), accent, success, warning, danger
- Dismissable with hover-to-reveal close button

### Modals

- Backdrop: semi-transparent black (35%)
- Panel: white, 12px radius, 1px border
- Header: title + close button
- Body: form content with 16px padding
- Footer: action buttons

### Lightbox

- Full-viewport overlay
- Dark backdrop (85% black)
- Image: max 92vw × 90vh, contain
- Close button: floating pill in top-right

### Empty State

- Dashed border container
- Centered message + optional action
- Used when no artworks match the current filter

---

## Motion

### Duration & Easing

| Token | Value | Usage |
|---|---|---|
| Fast | 150ms | Hover, active states |
| Normal | 200ms | Panel transitions |
| Slow | 300ms | Modal enter/exit |

Easing: `cubic-bezier(0.16, 1, 0.3, 1)` — Apple-style spring-like deceleration

### Transitions

- Card hover: border-color + box-shadow
- Button active: `transform: scale(0.98)`
- Modal: fade + slight scale (opacity + transform)
- Sidebar nav: color change only (no layout shift)

---

## HeroUI Component Mapping

| Volio Element | HeroUI Component | Notes |
|---|---|---|
| Buttons | `<Button>` | `color="primary"`, `variant="solid"` |
| Cards | `<Card>` | Isolated, hover-shadowed |
| Chips/Tags | `<Chip>` | `variant="flat"`, `size="sm"` |
| Modal dialogs | `<Modal>` | `placement="center"` |
| Input fields | `<Input>` | `variant="bordered"`, `size="sm"` |
| Text areas | `<Textarea>` | `variant="bordered"` |
| Sidebar nav | `<Navbar>` or manual | Custom list with active state |
| Toolbar | Manual | Flex row with segmented control |
| Lightbox | Manual | Custom overlay |

The current vanilla implementation serves as the reference; HeroUI components will be introduced incrementally during the rewrite.

---

## Internationalization

Not yet implemented. All UI text is in English. Future: `react-i18next` with auto-detected system locale.

---

## Accessibility

- All interactive elements are focusable via keyboard
- Buttons use `<button>` elements (not divs masquerading as buttons)
- Images have descriptive `alt` text
- Color contrast ratios meet WCAG AA (4.5:1 for text, 3:1 for large text)
- Semantic HTML structure for screen readers

---

## File Location

This file lives at the project root: `DESIGN.md`

For HeroUI component API reference, see:
- https://heroui.com/docs/react/getting-started/quick-start
- https://heroui.com/docs/react/components/button
- https://heroui.com/docs/react/components/card
