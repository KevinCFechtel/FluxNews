# FluxNews App Icon Source

This folder contains the source artwork for the FluxNews Icon Composer icon.

## Brand colors

- FluxNews blue: `#27AED9`
- Default book: `#F5F5F5`
- Dark appearance book: `#27AED9`

## Icon Composer setup

Create/save the final Icon Composer document as:

`AppIcon.icon`

Use a 1024 × 1024 canvas for macOS.

### Background

Set the icon background directly in Icon Composer.

Default appearance:
- background: `#27AED9`

For Dark appearance:
- keep the desired existing/dark background treatment;
- do not recolor the complete icon blue;
- only the Book layer must use `#27AED9`.

### Foreground

Import:

`Artwork/01_Book.svg`

as the Book layer.

Default appearance:
- Book fill: `#F5F5F5`

Dark appearance:
- vary only the Book layer color/fill;
- Book fill: `#27AED9`

Do not replace the book artwork with a raster image and do not flatten the
background and book into one layer. Keeping the book separate is what allows
appearance-specific recoloring.

## Files

- `Artwork/01_Book.svg`
  Actual vector artwork to import into Icon Composer.
- `Reference/FluxNews_Default.svg`
  Visual reference for the original normal icon.
- `Reference/FluxNews_Dark_BookColor.svg`
  Color reference showing the requested blue book. The dark background in this
  reference is illustrative only and is not a prescribed production color.

## Xcode / repository result

The final repository should contain the `AppIcon.icon` file produced by Icon
Composer and may keep this source folder alongside it for maintainability.

The existing legacy `AppIcon.icns` can be retained during migration until the
Xcode/Icon Composer integration is confirmed.
