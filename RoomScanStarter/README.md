# RoomScanStarter — RoomPlan Scanner for Hackathons

A native iOS app that shows RoomPlan's wall and furniture outlines with a room miniature in the camera view, then displays the 3D result and measurements on the same screen.

## Run it

1. Extract the project and open `RoomScanStarter.xcodeproj` in Xcode.
2. Select your Apple Account **Team** under Project → TARGETS → RoomScanStarter → **Signing & Capabilities**. A Personal Team works for a demo on your own device; complete any signing prompts from Xcode.
3. Set a unique **Bundle Identifier**, for example `com.yourname.furniture.RoomScanStarter`.
4. Connect a **physical iPhone or iPad with LiDAR** to your Mac and select it as the run destination. Follow prompts to trust the Mac and enable Developer Mode.
5. Press Run (`⌘R`), allow camera access, choose **Start Room Scan**, slowly scan the walls, floor, and furniture, then tap **Finish Scan**.
6. Inspect the 3D result. Review furniture and structural dimensions below, optionally give an item a name such as `vanity`, and tap **Save Name**.
7. Use **Share JSON** or **Share 3D Model** to AirDrop or save the files.

The project uses SwiftUI and Swift and targets **iOS/iPadOS 17**. It needs no package installation, API key, or backend. RoomPlan itself is available from iOS 16, but this sample targets iOS 17. Camera usage text and file-sharing settings are in `Info.plist`.

**You can edit Swift files in VS Code. Build, sign, and install the app with Xcode on a Mac.** Simulator cannot scan a real room. The app checks the device with `RoomCaptureSession.isSupported`.

## Add it to a GitHub repository

Copy the `RoomScanStarter` folder into the existing repository. If the team has web or backend code, it can live under `ios/RoomScanStarter`. Keep `.xcodeproj` beside the inner `RoomScanStarter` source folder.

```bash
# From the root of your repository, after copying the folder as RoomScanStarter
git status
git add RoomScanStarter
git commit -m "feat: add RoomPlan scanning and room export"
git push -u origin HEAD
```

Open the repository in VS Code to edit Swift files, then run the app with `⌘R` in Xcode. To add scanning to an existing SwiftUI app, add the five `.swift` files other than `RoomScanStarterApp.swift` to its app target and show `ContentView()`. Add `NSCameraUsageDescription` to that target's `Info.plist`. Use only one `@main` entry point.

## File responsibilities

| File | Responsibility |
| --- | --- |
| `RoomScanStarterApp.swift` | App entry point |
| `ContentView.swift` | Scan flow, 3D result, measurements, name editing, and sharing |
| `RoomCaptureContainer.swift` | Connects SwiftUI to Apple's `RoomCaptureView` and handles scan callbacks |
| `RoomScanner.swift` | Permissions, scan lifecycle, view state, and results |
| `RoomDocument.swift` | Shared JSON structure and extraction of position, rotation, and dimensions |
| `RoomExporter.swift` | Saves JSON and USDZ files |

## How scanning works

The app presents `RoomCaptureView` and calls `captureSession.run(configuration:)`. The white outlines, scan guidance, and small room preview are built-in RoomPlan UI. The finish action calls `captureSession.stop(pauseARSession: true)`. The processed `CapturedRoom` is delivered through `captureView(didPresent:error:)`.

Do not remove `RoomCaptureView` immediately after stopping the scan. Keep it mounted until processing and the 3D result are complete. Then save JSON and USDZ. USDZ export runs away from the main thread. Each callback checks the scan ID so a delayed callback from an earlier scan cannot overwrite a newer scan.

## Exported files

Each scan is saved under `Documents/RoomScans/<scan ID>/` in the app. On iPhone, it is also accessible from Files → On My iPhone → Room Scan → RoomScans.

| File | Purpose |
| --- | --- |
| `room.json` | Dimensions, coordinates, and labels for the web frontend and AI/backend |
| `captured-room.json` | Original structural data encoding Apple's complete `CapturedRoom` |
| `room.usdz` | 3D model for Apple's viewer and other USDZ-compatible tools |

If JSON saves but USDZ export fails, the JSON is kept and a retry button is shown. Renaming furniture updates `room.json` while preserving Apple's original category in the native JSON. Files remain after relaunch, but this minimal sample does not automatically restore the last scan into its screen.

## JSON contract for the team

See [`examples/room.example.json`](examples/room.example.json) for the complete structure. **The example values are fictional and were not measured from the attached video.**

```json
{
  "id": "furniture identifier",
  "kind": "object",
  "category": "table",
  "label": "vanity",
  "confidence": "high",
  "dimensions": { "width": 1.0, "height": 0.75, "depth": 0.4 },
  "position": { "x": 1.2, "y": -0.625, "z": -0.9 },
  "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1.2, -0.625, -0.9, 1]
}
```

- **Length units are meters.** The UI converts to centimeters by multiplying by 100.
- `dimensions.width/height/depth` are the element's **local x/y/z axis sizes**. Surfaces such as walls and floors can have zero thickness. A floor's local y-axis may not match world up; the displayed dimensions are along the local axes.
- `position` is the element center in world coordinates and matches the last column of `transform`.
- `transform` is a column-major array of 16 values representing a **4×4 matrix** from local coordinates to scan world coordinates. Include it to preserve rotation.
- World coordinates are right-handed with y pointing up. The origin is relative to the scan session, and **the floor is not necessarily at y=0**. Coordinates from different scans are not automatically aligned.
- `confidence` is RoomPlan's classification confidence, not a dimension error estimate.
- `objects` contains furniture; `walls/doors/windows/openings/floors` contains structural elements.
- `room.json` is a compact format for element dimensions and transforms. Use `captured-room.json` or `room.usdz` for detailed surface geometry and Apple-specific properties.

Example: rebuild a furniture box in Three.js on the web.

```js
// Use the web team's existing Three.js import for THREE.
const { width, height, depth } = object.dimensions;
const mesh = new THREE.Mesh(
  new THREE.BoxGeometry(width, height, depth),
  new THREE.MeshStandardMaterial({ color: 0xd8c4aa })
);
mesh.matrixAutoUpdate = false;
mesh.matrix.fromArray(object.transform); // Column-major array; do not apply position again.
mesh.userData.roomObjectId = object.id;
scene.add(mesh);
```

## Scope and integration points

- This project does **not** convert an arbitrary MP4 upload into a RoomPlan scan. RoomPlan scans directly with the device camera, LiDAR, and AR session. Reconstructing a room from an existing video requires a separate pipeline or a pre-scanned demo result.
- RoomPlan creates structural models of walls and furniture. It does not automatically create photorealistic textured rooms or detailed product models.
- RoomPlan categories cannot reliably identify every object as a `vanity`. For a demo, rename items in the list and send the ID and `transform` of the item where `label == "vanity"` to the AI.
- **Open-space and collision checks** require separate logic. This code records dimensions and transforms for detected furniture and structures. Account for occluded or missed objects; subtracting furniture footprints from the floor area is not enough to prove a placement will fit.
- Product recommendations, placement editing, server upload, and payment are not included. Send `room.json` to the web team to reconstruct boxes or connect it to a 3D viewer through an appropriate conversion path. Link actual furniture assets and dimensions from product data separately.
- To add server upload, send `scanner.files?.json` to the API agreed with the server team. This sample does not hard-code a server URL or payment behavior.

## Verification

This project was prepared in an environment without Xcode or the iOS SDK. Static checks covered project structure, file references, the JSON example, and `Info.plist`, but **an Xcode build and a scan on a physical LiDAR device have not been verified**. On a real device, check scan → finish → 3D result → share JSON/3D → rename item → rescan.

## Apple documentation

- [RoomPlan overview](https://developer.apple.com/augmented-reality/roomplan/)
- [RoomCaptureView](https://developer.apple.com/documentation/roomplan/roomcaptureview)
- [Official RoomPlan sample](https://developer.apple.com/documentation/roomplan/create-a-3d-model-of-an-interior-room-by-guiding-the-user-through-an-ar-experience)
- [RoomCaptureViewDelegate](https://developer.apple.com/documentation/roomplan/roomcaptureviewdelegate)
- [CapturedRoom](https://developer.apple.com/documentation/roomplan/capturedroom)
