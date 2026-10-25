# Tuck

Tuck is an iPhone furniture-shopping prototype. It combines a room-scanning flow, a rotatable 3D room, furniture recommendations in chat, and a lightweight checkout demo. The app is built with SwiftUI; its interactive room preview is rendered in a bundled WebGL page.

This repository is a hackathon prototype. Room measurements and furniture recognition are approximate, product availability is not live, and the checkout flow is for Stripe test mode only.

## What works

- **Room scan and saved rooms:** RoomPlan scans are processed on device and saved in the app's Documents directory. The app also includes a local illustrative room named **Sample Room**. The app opens to the empty scan screen; saved rooms are available from the room-name menu.
- **3D room preview:** Rotate and zoom the room, add supported furniture models from recommendation cards, and use the room editing controls to move and rotate placed items. Furniture layouts and room records are stored locally on the iPhone. Curtains are part of the room structure and are not editable furniture.
- **Furniture chat:** The app calls Anthropic's Messages API directly and streams replies. Its prompt uses the bundled product catalog and current room context. Recommendations can include up to three product cards. Chat history is kept per room on device, and the user can stop an in-progress response.
- **Catalog and product models:** The bundled catalog contains 30 chair products. Three brown sofa USDZ models can currently be inserted into the 3D room. Catalog recommendations do not imply that every item has a 3D model.
- **Profile and local data:** The profile includes saved furniture, delivery details, payment settings, and order history. Favorites and room/chat data are stored locally; checkout records are also available through the backend.
- **Checkout demo:** The optional Node.js service creates quotes and orders and integrates with Stripe test mode. A build without Stripe support displays that payments are unsupported on the device; room scanning, chat, and room editing remain separate features.

### Important limits

RoomPlan produces a structural model, not a photorealistic copy. Recognition can miss or misclassify objects, and measurements may be inaccurate. The chat can compare catalog dimensions with available room context, but there is no collision or clearance verification: it cannot guarantee that a product fits, that a walkway stays clear, or that doors and drawers can open. Product inventory, prices, and delivery are not live commerce data.

## Main user flow

1. Launch to the empty home screen and tap the scan circle or camera button.
2. Scan on a supported LiDAR iPhone, then finish and review the result. On unsupported devices, the camera screen is a demo fallback and finishing opens the illustrative room.
3. Choose a saved room from the room-name menu, or use the new scan result. The app asks how to handle unsaved changes when leaving a changed room.
4. Ask for furniture recommendations in the chat. Tap a product card's **Try** action to add a supported 3D model to the room.
5. Use the room controls to inspect and arrange furniture. Save changes to an existing room or create a newly named room.
6. Use the profile and checkout demo for saved items and test orders.

## Repository layout

```text
Tuck.xcodeproj/                 Main iOS app project
TuckNoPayments.xcodeproj/       iOS project without Stripe payment support
Tuck/                           SwiftUI app, services, local stores, and WebGL room
  Features/Home/                Home, chat, product cards, room preview
  Features/Scan/                RoomPlan scan and scan result screens
  Features/Profile/             Profile and saved-item screens
  Services/                     Claude, catalog, room, favorites, checkout services
  Resources/DemoRoom.html       Interactive 3D room renderer
RoomScanStarter/                Earlier standalone RoomPlan reference project
TuckTests/                      XCTest sources
backend/                        Node.js quote, order, and Stripe test service
data/TUCK_Product_Catalog.csv   Bundled furniture catalog
scripts/                        Local setup and developer utilities
docs/                           Room JSON and RoomPlan notes
```

## Build the iOS app

Requirements: macOS with Xcode, an Apple development account for device installation, and iOS 17 or later. LiDAR scanning requires a supported LiDAR iPhone or iPad; it cannot be tested in the iOS Simulator.

1. Clone the repository and open `Tuck.xcodeproj` in Xcode.
2. Run `bash scripts/setup-local.sh` from the repository root. It creates a minimal ignored `Tuck/Services/Secrets.swift` only if one does not already exist.
3. To use chat, add an Anthropic API key to the local `Secrets.swift` file. The app talks to Anthropic directly; do not commit this file or put secret keys in the repository.
4. Select the **Tuck** scheme, set your development team under **Signing & Capabilities**, choose a simulator or connected iPhone, then build with `⌘R`.
5. Grant camera access when prompted. Use a supported LiDAR device to scan a real room.

For a device build that omits Stripe, open `TuckNoPayments.xcodeproj` and select its **Tuck** scheme. The app shows a payment-unavailable message for checkout on that build; no simulated successful charge is made.

## Chat and product catalog

`Tuck/Services/ClaudeClient.swift` streams requests directly to `https://api.anthropic.com/v1/messages`. The API key is read from the local `Secrets.swift`. The current system prompt asks for concise English answers, uses the room's current editor context when available, and restricts furniture recommendations to the bundled catalog. Room geometry is approximate context only, not a fit-check service.

The catalog is `data/TUCK_Product_Catalog.csv`. Product prices and dimensions are bundled demo data. Image links may point to external product images; the app does not scrape live inventory.

## Optional checkout backend

The backend is only for quote/order and Stripe test-mode flows; it does not host the chat model. It requires Node.js 20 or later and Stripe test credentials.

1. Copy `.env.example` to `.env` and fill in `STRIPE_SECRET_KEY` (`sk_test_...`) and `STRIPE_WEBHOOK_SECRET` (`whsec_...`). Keep `.env` private. The backend refuses live Stripe secret keys.
2. Start the service from the repository root:

   ```bash
   npm --prefix backend start
   ```

3. The default port is `8787`. For a physical iPhone, set the app's local `Secrets.backendURL` to the Mac's reachable LAN address instead of `localhost`.
4. To accept Stripe events locally, configure Stripe CLI forwarding to `http://localhost:8787/webhooks/stripe` and use the generated webhook signing secret.

Routes currently implemented:

- `POST /v1/devices` — register a demo device and receive its token
- `POST /v1/quotes` — create a quote for a catalog product
- `GET /v1/orders/:id` — retrieve an order
- `POST /v1/orders/:id/confirm` — confirm an order after quote validation
- `POST /v1/orders/:id/cancel` — cancel an order
- `POST /webhooks/stripe` — receive verified Stripe events

The backend persists its order store under `backend/.data/` by default. Use Stripe test mode only; this prototype does not fulfill or ship real products.

## Tests and utilities

- Backend: `npm --prefix backend test`
- Swift unit tests: open the project in Xcode and choose **Product → Test** (`⌘U`) with an iOS Simulator destination.
- Local API test helpers and room/editor scripts are in `scripts/`.

The iOS app and RoomPlan scanning must be built and exercised on macOS/Xcode and a supported physical device. Passing backend or unit tests does not verify LiDAR behavior or visual quality on a phone.

## Data and privacy

Room scans, saved room layouts, chat history, and favorites are stored on the device. Chat messages and room context are sent to Anthropic when using the chat feature. Checkout requests go to the configured Tuck backend and Stripe test mode. Scan files are not automatically uploaded to the backend.

## Design reference

[Figma — CalHacks 13.0 / Tuck](https://www.figma.com/design/flIQdS0FkYcdUDU0V0pojh/CalHacks13.0---tuck)
