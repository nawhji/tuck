# Main, RoomPlan and profile integration

Merge order: `feat/home-roomplan` first, then `feat/profile`. The profile branch already depended on the RoomPlan branch; the updated history preserves that relationship.

## Preserved behavior

- Both Home scan entry points open `DemoScanView` through one `isPresentingScan` state.
- Supported devices use `RoomCaptureContainer` / RoomPlan. Other devices use a regular camera and an English LiDAR warning.
- Finish always opens the bundled demo room, independently of scan success.
- A completed/saved actual scan is retained for measurements and Profile → My rooms.
- Home and profile share one `FavoritesStore`, so recommendation hearts and saved furniture use the same persisted list.
- The current local demo HTML interaction changes were carried into the integration. Personal debugger settings and API keys were not committed.

## Corrected integration problems

- Resolve conflicting Home/RoomStage/project-file implementations without replacing the demo with the real scan preview.
- Start RoomPlan only after its view controller appears (from the RoomPlan branch).
- Do not silently switch a supported device to AVCaptureSession after a RoomPlan failure; show the actual error and Retry instead.
- Ignore transient inactive scene phases; a real background transition cancels the scanner token before a fresh scan is started.
- Do not publish unchanged wall/object counts, and disable the built-in miniature while retaining RoomPlan overlays.
- Extend the scan panel's white background to the bottom safe area.
- Keep new UI copy and saved-room messages in English.

## Validation performed

- Updated RoomPlan branch: generic iOS arm64 unsigned build passed.
- RoomPlan + profile integration: generic iOS arm64 unsigned build passed.
- Simulator `build-for-testing` passed, including all 16 XCTest cases.
- 13 hardware-independent tests ran and passed on macOS using the production storage, favorites, home, chat/client and catalog implementations. The host harness omits only RoomPlan-specific initializers and the three scanner-dependent tests.
- Merge checks validate both updated heads against the recorded main, and profile after RoomPlan.

## Remaining physical-device checks

Real camera/RoomPlan, WKWebView GPU rendering, interruptions, and the reported iPhone 14 Pro hang were not reproduced in this environment. These checks do not establish that the hang is fixed.

Demo completion gives RoomPlan/save up to eight seconds, then opens the demo even if no result is ready. A scan that has not finished post-processing when the capture view is removed may not be saved. The UI therefore does not claim that every demo completion saved an actual scan. A disk export already underway can finish after the demo opens; reopen My rooms to refresh its list.

Signing and API keys are required only when running on a device / calling Claude. Build verification did not sign or install an app and did not call paid APIs.
