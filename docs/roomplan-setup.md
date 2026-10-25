# Home Camera → RoomPlan Integration

## What changed

Baseline repository commit: `f26498f` (includes product catalog and chat improvements on main).

- The Home camera and dotted-circle + button open the existing `ScanView` full screen.
- The app checks LiDAR support, requests camera permission, and starts a real `RoomCaptureView` scan.
- Tapping **Finish Scan** opens Apple's 3D result preview and shows estimated wall and furniture dimensions.
- The existing `RoomExporter` saves files locally on iPhone. **Use in Home** is enabled after the result has been saved.
- From Home, rotate or zoom the USDZ model and open **View measurements** to see dimensions or share files.
- On relaunch, the app restores the most recent readable scan. Earlier scan files remain available.
- Handles denied permission, unsupported devices, empty scans, processing delays, cancellation, and file save/export failures.
- The `RoomScanStarter/` reference project, product data, Claude chat service, and chat UI were not changed.
- Building a room from the example video, furniture placement, and payment are outside this change.

Scanning uses Apple RoomPlan/ARKit and local file storage only. No paid API, external server, or API key is required. Existing Claude chat remains a separate feature. Scan files are not automatically uploaded to the chat server.

## Apply the patch to an existing checkout

Do not overwrite a teammate's working files with an entire folder. First check `git status`, then commit or back up your changes. Replace the path below with the actual location of the downloaded patch.

```bash
git switch -c feat/home-roomplan
git apply --check ~/Downloads/tuck-roomplan.patch
git apply ~/Downloads/tuck-roomplan.patch
bash scripts/setup-local.sh
open Tuck.xcodeproj
```

If `--check` reports an error, do not run the second `git apply`. The patch may conflict with a teammate's newer changes. Share the error and `git status` so the changes can be reconciled. Do not use `git reset --hard` to discard teammate work. The patch also registers the new Swift files in the Xcode app and XCTest targets.

If you downloaded the full project ZIP, extract it separately from your existing folder and run only the last two commands from that folder. The ZIP does not contain `.git`, personal API keys, or user-specific Xcode settings.

## Run on iPhone 14 Pro (Xcode beginner guide)

1. Install and launch Xcode on your Mac once to finish installing the required iOS platform components. The deployment target is iOS 17; use an Xcode version that supports the iOS version on your iPhone.
2. In VS Code's terminal, open the repository and run `bash scripts/setup-local.sh`. This preserves an existing `Secrets.swift` and creates an empty-key file only if it is missing. Scanning does not require an API key, but the project references this file as a build input.
3. Open the root **`Tuck.xcodeproj`**, not `RoomScanStarter.xcodeproj`.
4. Connect the iPhone to your Mac with a cable, unlock it, and trust the computer on the phone.
5. In Xcode → Settings → Apple Accounts (called Accounts in some versions), sign in with your Apple Account.
6. Select the blue Tuck project on the left → TARGETS **Tuck** → Signing & Capabilities. Enable `Automatically manage signing` and choose your Personal Team or development team. Replace the team's Team ID from the repository with your own. If the Bundle Identifier is unavailable, change it to a unique value such as `com.yourname.tuck`.
7. On iPhone, enable **Developer Mode** under Settings → Privacy & Security, then follow the restart and confirmation prompts. If the option is missing, first check whether Xcode recognizes the device.
8. Select the **Tuck** scheme and your connected physical **iPhone 14 Pro** as the run destination.
9. Press ▶ or `⌘R` to build, install, and launch. Follow any permission or signing prompts in Xcode and on the phone.
10. Tap the Home camera, allow camera access, and slowly scan the room so the walls, floor, and furniture are visible. After tapping **Finish Scan**, wait for processing and saving to complete, rotate the 3D model, review dimensions, and tap **Use in Home**.

SF Pro is provided by SwiftUI's system font; no font files need to be installed. RoomPlan requires LiDAR, so Simulator shows an unsupported-device message instead of scanning. Verify scanning on an iPhone 14 Pro. The result is a structural/furniture model from RoomPlan, not a photorealistic reconstruction.

## Saved files and their meaning

Files are stored under `Documents/RoomScans/<scan ID>/` in the app:

| File | Contents |
| --- | --- |
| `room.json` | Dimensions, position, transform, and furniture labels for sharing with the team |
| `captured-room.json` | Apple's original CapturedRoom data |
| `room.usdz` | 3D model for preview and sharing |

Dimensions are estimates. Values are in meters; the UI displays centimeters. Wall and floor dimensions use each element's local axes, so the UI's height is not always world vertical. This feature does not calculate total room area or open space. See the [room.json contract](room-json-contract.md) for details.

- Scan results are saved automatically. **Use in Home** associates the saved room with Home.
- Canceling a rescan keeps the room currently saved to Home.
- If only USDZ export fails, the dimensions JSON remains. The app shows an error and offers **Retry Save**.
- Export files from the Files app under On My iPhone → Tuck, or use the app's share button.
- Deleting the app also deletes its local files. Share scans you need to keep.

## Verification status

The environment where this change was written was **Linux and did not have Xcode, Apple SDKs, or a connected iPhone**. An `xcodebuild` command was attempted but could not run (`command not found`). **iOS build success, passing XCTest results, and successful real LiDAR scanning have therefore not been verified.**

Checks performed:

- Swift syntax parser check (not the same as compiler type checking).
- Xcode project OpenStep format, target source references, Info.plist, and shared scheme structure.
- `git diff --check` and review of the changed files.
- Compared RoomPlan delegate/result handling and device support APIs against Apple documentation.

To check unsigned compilation with both SDKs on a Mac:

```bash
bash scripts/check-ios-build.sh
```

To run XCTest, select an iPhone **Simulator** in Xcode and choose **Product → Test (`⌘U`)**. Seven XCTest cases cover restoring scans, corrupt files, and ignoring callbacks after cancellation; they have not yet been run. From the command line, find a Simulator UDID with `xcrun simctl list devices available`, then run:

```bash
bash scripts/check-ios-build.sh YOUR_SIMULATOR_UDID
```

Build logs are written to `.build/logs/`. If the build fails, share the first red error message or the log.

On-device checklist:

- Confirm the camera and RoomPlan prompts appear after granting permission on first launch.
- After denying permission, confirm it can be enabled in Settings and retried.
- Scan walls and furniture, finish, review the 3D model and centimeter dimensions, save, and preview from Home.
- Fully quit and relaunch the app; confirm the same room and dimensions are restored.
- Rename an item in the result and confirm its label also appears on Home's measurement screen.
- Cancel a rescan and confirm the previous room remains. Background the app during a scan and confirm it recovers with a status or error message.
- Share JSON and USDZ files; rotate and zoom the 3D model.
- Confirm existing product cards, chat, keyboard, and sheet-drag behavior still work.

## Apple documentation

- [RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)
- [RoomCaptureViewDelegate](https://developer.apple.com/documentation/roomplan/roomcaptureviewdelegate)
- [Device support](https://developer.apple.com/documentation/roomplan/roomcapturesession/issupported)
- [Run your app on a device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
