# Chair placement fix

Current main used for this change: `28984078d484a84e51d68329f0be09e423049f45`.

The public main and feat/furniture-try-demo branches still routed card taps to selectedProductID only. The three original USDZ files were in data/ but were not app resources. A Try/Remove label therefore did not confirm a rendered placement.

## Resulting flow

Open Room 1 from Profile → My rooms. Find a chair searches the three prepared products locally. AI recommendation cards and local search call the same RoomPreviewController.toggleProduct action.

Try loads the actual supplied USDZ, registers textured triangle buffers with the existing WebGL renderer, adds one instance of that product, enables furniture move mode, and minimizes chat. Card membership is updated only after an acknowledged scene snapshot. Several different products can coexist; repeated taps do not duplicate a product that is loading or already placed.

Select a piece using its name, the furniture selector, or a hit in move mode. Drag to move along a world axis. The bottom toolbar renames it, rotates it by 15 degrees in either direction, or removes it. Turn move mode off using the existing move button to orbit the room camera; pinch still zooms. Both original sample furniture and newly added products use these controls.

RoomPreviewController is shared by placement, the move-mode button, the current viewport, and the existing Back → Save flow. RoomLayoutSnapshot now preserves optional label/productID fields, while legacy Room 1 snapshots without those keys remain readable. Source scanned-room geometry is retained. Reset current room restores furniture for the active room instead of replacing its walls with another room.

## Model resources

- sofa_007_brown.usdz — Otio Leather Lounge Chair
- sofa_027_brown.usdz — Goda Accent Chair
- sofa_028_brown.usdz — Peacemaker Accent Chair

The repository contains original files, not the previously mentioned reduced models. The app includes the originals in Copy Bundle Resources. Apple's SceneKit/Model I/O imports them off the main actor, carries diffuse texture colors/UVs into the existing WebGL renderer, and caches converted data in Caches/FurnitureModels-v2. Uniform scaling fits the catalog dimensions in meters and bottom-centers the mesh; this preserves source proportions and remains approximate. Source animations and normal/metallic texture maps are not reproduced.

No model-generation API or external server is used. Existing AI chat and remote product images retain their existing network behavior.

## Verification

Executed here: JavaScript syntax, actual editor logic using mock DOM/WebGL with synthetic chair buffers, ray-picked pointer movement, furniture rotation, camera orbit mode, Try deduplication, three simultaneous models, original furniture removal, deletion/card snapshot synchronization, renamed placement restore, switching between scanned and demo rooms, and reset preserving the current scanned source. Resource registration and package application are separately checked.

Not executed here: Xcode compilation/XCTest, GPU shader compilation, actual USDZ imports, native sheet/keyboard behavior, model appearance/heading, or iPhone memory/loading performance. A Mac/iPhone is required for these checks. The Node tests are not visual or device tests.

## Presentation check on the Mac

Build the app, then Product → Test. FurnitureTests imports all three actual bundled models and checks texture data. Run Room 1 → Find a chair → Otio → Try. Check the visible model and its heading/scale. Drag, rotate, rename, and remove it; reopen search to verify Try returns. Repeat with Goda and Peacemaker, then test Back → Save → reopen. A first model import can take time; Loading stays visible and duplicate taps are disabled.

Room-aware chat and dirty-layout/discard/save behavior from the latest main are retained. Binary model buffers participate in live chat dimensions and bounds, edited names override category labels, and removed products are excluded. Native Xcode tests were not run here.
