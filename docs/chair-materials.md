# Three-chair appearance fix

Base: `7c8550bc42826de563f15d6a74f30243635535a0` (`main`).

Scope: Otio `sofa_007_brown`, Goda `sofa_027_brown`, Peacemaker `sofa_028_brown` only.

The old room shading path can overlay shadow-map artifacts on textured chairs. The latest base commit avoids these by displaying unlit color only, but also discards the normal/roughness material effects. This change keeps a separate neutral studio material for the three product chairs, with their original four maps and authored tangents. It avoids room shadow-map sampling on their surfaces while retaining cast floor shadows. It is not a pixel-exact reproduction of Apple's Quick Look lighting.

The reported faulty phone rendering was not available for a before/after device comparison. Neither a specific phone build nor a single cause of that device's artifacts has been established. This fix removes the runtime import/cache ambiguity and tests the output path directly against the supplied USDZ data.

## Asset preparation

`scripts/prepare-chair-materials.py` reads the USD material graph with OpenUSD. It does not infer color/normal texture roles from image filenames. It preserves all original triangles, vertex normals, UVs and tangents. Position changes are limited to the existing uniform catalog fit and bottom-centering. Original USDZ files remain unchanged.

Original 4096px color and normal images are reduced to 2048px, then stored as lossless PNG; the 2048px scalar maps remain at source resolution. This resolution cap matches the previous runtime converter and limits texture memory. There is no new retouching, texture synthesis, tint or API dependency. Normal/roughness/metal maps are uploaded as numeric data, and color is decoded/encoded as sRGB in the shader. Mipmaps prevent texture shimmer when zoomed out.

The generated folder is copied into the app bundle. `FurnitureModelLibrary` reads it directly; old Caches/FurnitureModels-v2/v3 files are ignored. No app deletion or manual cache clearing is required. Large encoded image strings are released after GPU upload, and native code no longer retains copies of all three payloads. WebGL caches uploaded resources for reuse after Remove/Try. App resources grow by approximately 86 MiB. Test memory/loading on the presentation phone.

If a source USDZ changes, run:

```sh
python -m pip install usd-core numpy Pillow
python scripts/prepare-chair-materials.py
python scripts/test-chair-materials.py
```

Commit generated files and `manifest.json` together. They are already prepared in this patch: the presenter does not need Python or to regenerate anything. The generator intentionally rejects unfamiliar mesh/material layouts.

## Checks performed here

- All three USDZ sources: full topology, UVs, normals and tangent signs match; all four prepared maps match the decoded/downsampled source pixels exactly; source/output hashes match the manifest.
- Real WebGL in headless Chromium: all three render together, indexed buffers, material maps, selection without tint, independence from shadow-map contents, rotate/remove/restore, and identical rendered pixels with the non-indexed/no-derivatives fallback.
- Existing editor interaction and room/chat context regression scripts pass.
- Modified Swift syntax parses; Xcode project resources parse and signing/build configuration objects are unchanged.

Not performed: Xcode build, XCTest execution, WKWebView on iOS, Quick Look pixel equivalence, iPhone load-time/memory measurement. The build script stops because this environment has no Xcode. Chromium software WebGL is useful shader verification, not device verification.

## Mac / demo check

1. Open the updated `Tuck.xcodeproj`. Keep your existing signing/team settings.
2. Product → Clean Build Folder (`Shift-Command-K`), then Run (`Command-R`). Run on a Simulator first if convenient.
3. Room 1 → Find a chair → Otio → Try. Repeat with Goda and Peacemaker. All three can be checked without LiDAR, including on a regular iPhone 15.
4. View front and rear. Select, move, rotate, Remove and Try again. Check the chair does not acquire dark shadow patches or a white selection tint.
5. Back → Save → reopen. Check saved positions and names, then test with all three visible for several minutes on the presentation phone.
6. Product → Test (`Command-U`) runs `FurnitureTests` including bundle/model/map checks.

RoomPlan scanning, home/product/chat UI, checkout, catalog data and signing settings are unchanged.
