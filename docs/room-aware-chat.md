# Room-aware chat

Branch: `codex/room-aware-chat`.

## Baseline

This local branch starts from the latest available exported `tuck-room-navigation` app snapshot, preserved as commit `2213ccd`. It does not claim to include later changes on GitHub main. The original working folders were not checked out or edited.

## Behavior

- Every Send reads a fresh, validated snapshot from the displayed 3D editor before calling Claude.
- Context includes room ID/name/revision, provenance (scanned or sample), selected object, furniture labels/categories/confidence, actual displayed dimensions, centers, rotations, world box corners and axis-aligned bounds, plus structural measurements.
- Current editor placement wins over the original scan. Moved/removed furniture is reflected even before saving.
- Each room has a separate in-memory chat history. Returning to a room restores its history; histories are not persisted across app relaunch.
- Switching rooms cancels in-flight work and rejects stale responses. Failed geometry capture restores the pending question and does not send stale geometry.
- Existing catalog/card formatting and streaming text remain intact. Product inches must be converted to meters (0.0254).
- Snapshot JSON is sent to the existing Claude API with the system context on each question. USDZ, camera images and raw video are not sent by this change.

## Limits

No `check_fit` tool, certified free-space detection, generated placement zones, door swing, drawer extension, walking-clearance verification or new placement automation is implemented here. The prompt explicitly disallows verified-fit claims. Bounding boxes are conservative approximations. Missing furniture aliases or ambiguous directions trigger clarification. A sample room is explicitly identified as sample geometry.

## Try in Xcode

1. Open `Tuck.xcodeproj` in the sibling project folder.
2. Run `bash scripts/setup-local.sh` if `Tuck/Services/Secrets.swift` is missing; add your existing API key locally. Secrets are excluded from the archive and Git.
3. Open/scan a room, select furniture, then ask: "What furniture is selected, and what are its dimensions in centimeters?"
4. Move that furniture, send another question, and verify changed coordinates. Ask about another room and switch back to verify history isolation.
5. If the preview is still loading, sending should preserve the question and request a retry.

## Validation

- 44 macOS core tests passed using a temporary test harness (RoomPlan capture initializers and Observation macros are omitted in that harness).
- Pure JavaScript checks passed for rotated bounds, unsaved moves, labels, selection, deleted objects and sample provenance: `node scripts/test-room-context.js`.
- iPhoneOS Debug build passed with signing disabled. The local compiler required `OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'` for macro expansion in this execution environment.
- No live Claude API request was made and no device installation was performed.

`room-aware-chat.patch` contains only the feature changes relative to `2213ccd`; applying it to older layouts may require adapting the integration points.
