# Chair placement fix

The existing Try/move/remove flow is retained. The material update is based on main `7c8550bc42826de563f15d6a74f30243635535a0`; see [chair-materials.md](chair-materials.md) for scope and verification.

## Resulting flow

Open Room 1 from Profile → My rooms. Find a chair searches the three prepared products locally. AI recommendation cards and local search call the same RoomPreviewController.toggleProduct action.

Try loads a prepared payload made from the actual supplied USDZ, registers textured triangle buffers with the existing WebGL renderer, adds one instance of that product, enables furniture move mode, and minimizes chat. Card membership is updated only after an acknowledged scene snapshot. Several different products can coexist; repeated taps do not duplicate a product that is loading or already placed.

Select a piece using its name or a hit in move mode. Drag to move along a world axis. The bottom toolbar renames it, rotates it by 15 degrees in either direction, or removes it. Turn move mode off using the existing move button to orbit the room camera; pinch still zooms. Both original sample furniture and newly added products use these controls.

RoomPreviewController is shared by placement, the move-mode button, the current viewport, and the existing Back → Save flow. RoomLayoutSnapshot now preserves optional label/productID fields, while legacy Room 1 snapshots without those keys remain readable. Source scanned-room geometry is retained. Reset current room restores furniture for the active room instead of replacing its walls with another room.

## Model resources

- sofa_007_brown.usdz — Otio Leather Lounge Chair
- sofa_027_brown.usdz — Goda Accent Chair
- sofa_028_brown.usdz — Peacemaker Accent Chair

The three original USDZ files stay unchanged and remain available to Quick Look. `ChairMaterials/*.tuckmodel` contains the original triangle topology, vertex normals, UV coordinates, tangent handedness and material connections. These are bundled resources, so Try does not import through SceneKit/Model I/O or reuse old `FurnitureModels-v2/v3` caches. There is no app-side conversion or model download.

`scripts/prepare-chair-materials.py` resolves each USD material's connections. The color image is numbered differently in 007 versus 027/028; names alone are not a reliable channel mapping. Original 4096px color/normal images are resized to 2048px to bound mobile GPU memory and saved losslessly as PNG; 2048px roughness/metal maps keep their resolution. Source pixels are not retouched or recolored. Uniform catalog fitting and bottom-centering retain the previous app's size convention and source proportions.

Only these three chairs use neutral studio lighting with their original color, normal, roughness and metallic maps. Data textures bypass browser color conversion, authored tangents preserve normal-map orientation, and mipmaps reduce distant texture shimmer. Selection does not tint the chairs. The room's warm tint, procedural grain and shadow-map sampling are excluded from their surface shader, so self-shadow artifacts cannot be added to their upholstery. Chairs still cast shadows on the floor. This deliberately favors demo appearance over room-accurate received shadows. Quick Look uses a different lighting environment; reflection positions/brightness are not pixel-identical.

Full original geometry is indexed, with a non-indexed fallback when WebGL lacks 32-bit element support. The renderer releases encoded geometry/image strings after upload; native code does not retain a separate three-model payload cache. Texture resolution is capped, but device memory/load speed still needs an iPhone check. The prepared resources add about 86 MiB to the app bundle; they avoid first-Try native mesh/texture conversion. Regenerate them only when source models change. See [chair-materials.md](chair-materials.md).

No model-generation API or external server is used. Existing AI chat and remote product images retain their existing network behavior.

## Verification

`node scripts/test-furniture-editor.cjs` verifies interaction with mock DOM/WebGL. `node scripts/test-room-context.js` covers chat bounds and selection. `python scripts/test-chair-materials.py` verifies original USDZ topology, UV/tangent data, material channel connections and every resized texture pixel. `node scripts/test-chair-webgl.cjs` exercises the real shaders and three full models in headless Chromium, including no selection tint, no received shadow-map changes, rotate/remove/restore, and identical indexed/fallback images.

These checks do not replace Xcode compilation/XCTest or iPhone testing. Run Product → Test on the Mac. `FurnitureTests` checks the bundled payloads and four decoded maps. Run Room 1 → Find a chair → Otio → Try, then Goda and Peacemaker. Inspect from front/back and after moving/rotating; remove/re-add and Back → Save → reopen. Also check normal UI speed with all three present. Try stays in Loading until registration completes.

Room-aware chat and dirty-layout/discard/save behavior are retained. Binary model buffers participate in live chat dimensions/bounds; edited names override labels, and removed products are excluded. RoomPlan capture, home UI, checkout, signing and personal settings are outside this material fix.
