# Profile integration

Base: `origin/feat/home-roomplan` at `a3f97fc`. This change depends on that RoomPlan branch.
Merge RoomPlan first, or compare this branch against `feat/home-roomplan` when reviewing.

## Implemented

- Home avatar opens a Profile sheet with the existing user name/initial.
- My rooms lists all readable local scans, newest first. Tap a room for existing 3D/measurement/share UI.
- Chat card hearts and Saved furniture use the same observable store.
- Hearts persist in Documents/saved-furniture.json. Removing a favorite in profile updates chat hearts.
- Saved furniture details show catalog information and a retailer link. No API key is needed to browse saved items.
- Orders opens an honest empty state. No sample purchases, payment data, or checkout calls are added.
- Existing account identity is still the HomeViewModel demo name; no login or name editing was introduced.

## Apply to your existing Mac repository

Use the repository where you pushed `feat/home-roomplan`, not the earlier standalone ZIP folder.
Save any uncommitted edits before switching branches; `git status` should be clean.

```bash
git switch feat/home-roomplan
git pull --ff-only origin feat/home-roomplan
git switch -c feat/profile
git apply --check ~/Downloads/tuck-profile.patch
git apply ~/Downloads/tuck-profile.patch
bash scripts/setup-local.sh
open Tuck.xcodeproj
```

If the check fails, stop and share the error instead of overwriting teammate changes.
The patch includes new Swift files AND Xcode source registration. Do not copy just the Swift files.

Choose an iPhone Simulator, Cmd+R to build/run, Cmd+U to run tests.
The previous 7 RoomPlan tests are retained; 5 favorites persistence/error tests are added (12 total).
This environment has no Xcode: the new code and tests still require a Mac build/run.

## Check without a Claude key

1. Run normally: tap Home avatar, open each profile entry, check empty states and Done/back navigation.
2. To exercise product hearts with no AI request, open HomeView.swift in Xcode's Canvas and use the
   existing `Answer` (#Preview) configuration. Enable live preview, tap a sample card heart, then avatar → Saved furniture.
   These are explicitly sample products in the existing preview, not real purchases. Preview storage is separate
   from the installed app. Changes in Preview do not prove persistence in the app process.
3. Cmd+U tests verify file persistence through fresh store instances, unsaving by ID, duplicate cleanup,
   corrupt-file preservation, and no false saved UI state after a disk-write failure.
4. With a teammate's working chat, repeat heart → profile → app relaunch in the running app.
5. My rooms starts empty on devices without saved scans. Real RoomPlan scanning still requires LiDAR.

## Stripe handoff

The Orders destination is an empty state in ProfileView.swift. The teammate implementing Stripe should
replace it with an orders view populated from their confirmed-order source. A checkout-start tap or retailer
link visit must not create an order. Test-mode transactions should be explicitly labeled Test order.

## Scope

No chat-history persistence, payment/address forms, furniture placement, or scan algorithm changes.
ScanStore.latest now delegates to ScanStore.all, keeping the home restore path and profile list consistent.
Favorites persist full product snapshots, so saved cards work without calling Claude again. Prices are catalog
snapshots, not refreshed merchant prices.
