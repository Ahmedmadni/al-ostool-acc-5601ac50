# ONEXA design system

Status: Gate 32 foundation implemented on 20 September 2026.

## Brand idea

The user-approved PNG is the sole authoritative ONEXA identity. It contains the complete OX symbol, ONEXA wordmark, and `ERP SYSTEM` descriptor as one composition. It must be used exactly as supplied: do not redraw, trace, recolor, crop, separate, restyle, or reconstruct any element.

## Canonical assets

- Original approved identity: `public/onexa-approved-logo.png`
- React image wrapper: `src/components/brand/onexa-brand.tsx`
- Social preview: `public/onexa-og.png` (same approved artwork)
- PWA icons: `public/onexa-mark-192.png` and `public/onexa-mark-512.png`

Do not redraw the mark inside pages. Use `OnexaBrandMark`, `OnexaBrandLockup`, or `BrandLogo`; all three resolve to the approved image.

## Color tokens

| Role | Light value | Usage |
| --- | --- | --- |
| Brand ink | `#0B1739` | Navigation and high-emphasis sections |
| Brand blue | `#1D4ED8` | Primary actions and the mark container |
| Brand cyan | `#0891B2` | Connected-data accents and secondary emphasis |
| Signal blue | `#2563EB` | Crossing stroke and the `X` in the wordmark |
| Brand amber | `#F59E0B` | Warnings and limited commercial emphasis |
| Canvas | `#F4F7FB` | Light application background |

Colors are exposed through semantic CSS variables. Components should use `primary`, `background`, `card`, `muted`, `border`, `success`, `warning`, and `destructive` instead of embedding new colors.

## Typography

- English: Manrope, weights 400–800.
- Arabic: Noto Kufi Arabic, weights 400–900.
- Numeric tables: use tabular numerals and keep figures left-to-right even inside Arabic pages.
- Product wordmark: uppercase ONEXA with controlled positive tracking.

## Layout principles

1. Use a 4px spacing base and a restrained radius scale.
2. Keep financial tables dense, while dashboards and setup screens may use larger cards.
3. Use solid surfaces, visible borders, and one elevation level for standard cards.
4. Reserve saturated blue for primary actions, active navigation, and selected states.
5. Support RTL and LTR using logical properties (`ms`, `me`, `ps`, `pe`, `start`, `end`).

## Accessibility

- Maintain WCAG AA contrast for text and interactive states.
- Never communicate status using color alone.
- Every icon-only action needs an accessible name.
- Focus rings use the semantic `ring` token and must remain visible in both themes.
- Motion must respect `prefers-reduced-motion`.

## Logo controls

- Minimum digital mark size: 24px.
- Minimum lockup height: 32px.
- Clear space: at least one quarter of the mark width on every side.
- Never stretch, rotate, add shadows inside the artwork, recolor individual paths, or place the lockup on low-contrast imagery.
