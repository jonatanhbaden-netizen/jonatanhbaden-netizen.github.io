# Design

- Fonts: Familjen Grotesk (headings/UI) + Source Sans 3 (body), both Google Fonts.
  Never Inter, Roboto, Open Sans or Lato.
- All design tokens are CSS custom properties in `web/shared/tokens.css`. No magic numbers.
- Mobile-first. Fluid type with `clamp()`.
- Max content width `min(90vw, 72rem)`, centred with `margin-inline: auto`.
- CSS Grid for layout, Flexbox for alignment.
- Every animation wrapped in `prefers-reduced-motion`.
- No `!important`.
