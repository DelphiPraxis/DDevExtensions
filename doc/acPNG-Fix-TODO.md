# acPNG / AlphaControls PNG registration fix — separate WIP

Status (2026-07-19): the **registration-order arbiter is implemented** as its own feature
"Prefer proper PNG over AlphaControls" (`Source/FormDesignerHelpers/PreferProperPNG.pas`,
checkbox on the Form Designer options page, default off, all Delphi versions). It moves the
proper `TPNGGraphic` (unit `pngimage`; D2009+ also DDev's `FixAlphaControlsPNG` class when
compiled in) to the END of the VCL's global `TFileFormatsList`, because `FindClassName`/
`FindExt` iterate `Count-1 downto 0` — the LAST registered class wins. It runs on feature
activation and on every `ofnPackageInstalled`/`ofnPackageUninstalled`, and logs a dump of
the list plus the action taken to `%APPDATA%\DDevExtensions\PNGArbiter.log` (pre-move state
is logged before mutating). The list is reached via
`Source/FormDesignerHelpers/FileFormatsListHack.pas` (renamed from `uTLH.FileFormatsList`
— D7 rejects dotted unit names).

The `FixAlphaControlsPNG` DFM-converter is **enabled** (`INCLUDE_ACPNGFIX` defined,
2026-07-20) and no longer 2009-gated: pre-2009 IDEs statically link the patched PNGDelphi
from the repo copy in `Shared/PNGDelphi/` (pngimage.pas + pnglang.pas; zlib comes from the
Delphi 7 Lib). The copy carries a `DDEV_PNG_NOINIT` switch around its `RegisterGraphic`
define — both D7 build scripts pass `-DDDEV_PNG_NOINIT`, so the unit compiles WITHOUT
initialization-time self-registration and the option checkbox alone decides: when active,
pre-2009 registers the bundled `TPngImage` (ext 'png') plus the `TPNGGraphic` converter,
so IDEs with only a retail pngimage (TPNGObject era, no converter) — or none at all — get
working acPNG conversion and PNG round-tripping. An installed pngimage PACKAGE is never
touched (UnregisterGraphicClass works via InheritsFrom on a different class tree).

## Background / the problem
- **Delphi 7 has no native `pngimage`.** AlphaControls silently ships its own **acPNG** to
  compensate.
- acPNG does **not** store real PNG data in the DFM — it stores a **BMP with a wrong header**.
- The **class name** acPNG registers in the DFM does **not** match the one used by native
  `pngimage` (Delphi 2009+). So a DFM written by one can't be read correctly by the other.
- A fix already exists **inside `pngimage` itself** (a custom D7 build) that corrects the
  old→new format when loading (old acPNG BMP-with-wrong-header → proper PNG / class name).

## What DDevExtensions should add (the helper)
A helper that inspects the **IDE's graphic file-format registration** at runtime and reconciles
AlphaControls' acPNG with native `pngimage`:

1. Detect whether **both** AlphaControls (acPNG) **and** `pngimage` are present and loaded.
2. `TPicture`/`TPicture.RegisterFileFormat` keeps an ordered list and **the first match wins**
   (by extension / graphic class). If **acPNG is registered first**, Delphi would pick acPNG
   instead of `pngimage`.
3. So, when acPNG is loaded first, the helper must **remove acPNG's registration from the list**
   (or **move it below `pngimage`**), so that `pngimage` is chosen for PNG.

Effectively: ensure `pngimage` wins the format lookup over AlphaControls' acPNG.

## Where the pieces live
- `Code/DDevExtensions/Source/FormDesignerHelpers/PreferProperPNG.pas`
  — the implemented arbiter (see status above).
- `Code/DDevExtensions/Source/FormDesignerHelpers/FixAlphaControlsPNG.pas`
  — the old converter approach: subclasses `TPngImage`/`TBitmap` as `TPNGGraphic` and calls
  `TPicture.RegisterFileFormat('', 'Portable network graphics (AlphaControls)', TPNGGraphic)`.
  Still gated behind `INCLUDE_ACPNGFIX`; the arbiter promotes this class when it is compiled in.
- `Code/DDevExtensions/Source/FormDesignerHelpers/FileFormatsListHack.pas`
  — `TFileFormatsListHack` (a `TList`-based view of VCL's private `TFileFormatsList`) to
  add/remove/reorder registered formats by class name / extension / description; renamed from
  `uTLH.FileFormatsList.pas` (TetzkatLipHoka) because Delphi 7 rejects dotted unit names.

## Notes
- This is a **D2009+ concern** (where native `pngimage` exists alongside acPNG). On D7 there is
  no native `pngimage`; the D7 side is handled by the custom `pngimage` build's load-time fix.
- Re-enabling: define `INCLUDE_ACPNGFIX`, then finish `FixAlphaControlsPNG` to use the
  `TFileFormatsListHack` reconciliation instead of just registering another format.
