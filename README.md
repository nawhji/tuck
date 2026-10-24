# tuck

내 방을 LiDAR로 스캔해 3D 미니어처로 만들고, **AI 에이전트와의 대화 하나로**
가구 검색·추천 → 방 안 배치 시뮬레이션 → 주문·결제(Stripe 테스트 모드)까지 끝내는 iOS 앱. (CalHacks 13.0)

> 별도의 상품 상세·장바구니·결제 화면은 없습니다. 모든 구매 의사결정과 진행은 채팅 안에서 일어나고,
> 프로필에는 결과(주문 내역)만 기록됩니다.

디자인: [Figma — CalHacks13.0 / tuck](https://www.figma.com/design/flIQdS0FkYcdUDU0V0pojh/CalHacks13.0---tuck)

## 사용자 흐름

```
Splash ─▶ Home(빈 상태) ──[+ / 카메라]──▶ Room Scan ──[스캔 완료]──▶ Home(스캔된 공간)
                                                                         │
            ┌────────────── 채팅 입력 ("Any new ideas?") ◀──────────────┘
            ▼
      Home(질문 입력, 키보드) ─▶ Home(답변: 추천 가구 카드 목록)
                                         │ 카드 탭
                                         ▼
                              Home(Simulation: 3D 방에 가구 배치·이동)
                                         │ 같은 카드 다시 탭 → 시뮬레이션 종료 → 답변 화면
            ┌────────────────────────────┘
            ▼  "이걸로 주문할래" (채팅)
      채팅 안에서 주문 확인 카드(상품·배송지·카드·합계) ─[확인 탭]─▶ Stripe 결제 ─▶ 채팅에 주문 완료 메시지
                                                                          │
   Home 우상단 아바타 ──▶ Profile ──▶ Delivery Addresses / Payment Method / Order History ◀┘
```

주문 화면은 따로 없습니다. 검색 → 추천 → 배치 → 주문 → 결과 안내가 모두 같은 채팅 스레드에서 이어집니다.

| 화면 (Figma 프레임) | 내용 | 비고 |
| --- | --- | --- |
| `splash` | 갈색 배경 + 로고 | 시스템 Launch Screen으로 구현 (`UILaunchScreen`) |
| `home-default` | 점선 원 "Scan your space to start", 카메라 버튼, 하단 채팅 시트 | 저장된 스캔이 없을 때 |
| `room scan` | 카메라 + RoomPlan 윤곽선, "Move slowly to scan your space", 좌하단 미니 룸, 하단 진행 시트 "Scanning the room ...." | RoomPlan `RoomCaptureView` |
| `home-default with scanned space` | 3D 미니어처 방 + 카메라(재스캔) 버튼 + 채팅 시트(내 말풍선) | 스캔 결과 표시 |
| `home-asking a question` | 채팅 입력창(이미지·음성 버튼, 전송) + 키보드 | 이미지·음성 입력은 UI만 확인됨 |
| `home-answer` | AI 답변 텍스트 + 추천 가구 카드(이름·가격·판매처·태그·공유) | 카드 선택 시 테두리 강조 |
| `home-simulation` | 3D 방에서 가구를 드래그해 배치·이동 (심즈식) | 선택한 카드를 다시 탭하면 종료 |
| (신규) 채팅 내 주문 확인 카드 | 답변 카드와 같은 형태의 인라인 카드: 상품·수량·배송지·카드 끝 4자리·합계 + [주문 확인]/[취소] | Figma에 없음, 디자인 필요 |
| `profile` | 아바타·이름, Delivery Addresses, Payment Method, Order History | 로그인 없는 프로필. 주문은 여기서 하지 않고 **기록·관리만** (주소·카드 등록, 내역 조회) |

## 아키텍처

세 덩어리로 나뉩니다: **iOS 앱**(UI·스캔·3D 시뮬레이션), **Agent 백엔드**(LLM 에이전트 루프·도구·Stripe),
**Stripe**(테스트 모드). 앱은 SwiftUI + MVVM, 화면은 `Features/`, 순수 데이터는 `Models/`,
외부 연동·I/O는 `Services/`에 둡니다.

```
┌──────────────────────────── iOS 앱 ────────────────────────────┐        ┌──────────── Agent 백엔드 ────────────┐
│ Features                                                        │        │ POST /agent/messages  (SSE 스트림)   │
│  Home        3D 미니어처 + 하단 채팅 시트                         │        │  ├ LLM 에이전트 루프 (tool use)       │
│  Scan        RoomCaptureView (구현됨)                            │  HTTPS │  ├ Tools                             │
│  Chat        말풍선·추천 카드·주문 확인 카드                      │◀──────▶│  │   search_products                 │
│  Simulation  3D 씬에서 가구 배치·이동                             │        │  │   get_room_context / check_fit    │
│  Profile     주소·카드·주문 내역                                  │        │  │   place_in_room (앱에 UI 이벤트)  │
│ Models   RoomDocument(구현됨) Product ChatMessage Placement Order │        │  │   propose_order  (초안 생성)      │
│ Services AgentClient · ScanStore · ProfileStore · OrderStore     │        │  │   get_order_status                │
│          RoomExporter(구현됨)                                     │        │  └ 주문 확정은 앱의 [확인] 탭으로만    │
└──────────────────────────┬──────────────────────────────────────┘        │ POST /orders/{id}/confirm            │
                           │ Stripe 카드 등록 (SetupIntent, 앱 SDK)          │ Webhook /stripe (payment_intent.*)   │
                           ▼                                                └───────────────┬──────────────────────┘
                      Stripe (Test mode) ◀──────────── PaymentIntent 생성·확정, Customer/PaymentMethod ─┘
```

### 에이전트의 책임 범위 (end to end)

| 단계 | 에이전트가 하는 일 | 사용 도구 |
| --- | --- | --- |
| 검색·추천 | 질문과 `room.json`(빈 공간·기존 가구 치수)을 보고 후보를 찾아 이유와 함께 추천 | `get_room_context`, `search_products` |
| 적합성 판단 | 치수가 들어갈지 확인, 필요 시 대안 제시 | `check_fit` |
| 배치 시뮬레이션 | 사용자가 고른 상품을 3D 방에 올리도록 앱에 지시 | `place_in_room` |
| 주문 결정 | 사용자의 구매 의사를 확인하고 상품·수량·배송지·카드로 주문 **초안** 작성 | `propose_order` |
| 결제·결과 안내 | 확정 후 결제 결과·배송 상태를 채팅으로 안내 | `get_order_status` |

**주문 확정은 모델이 아니라 앱 UI가 결정합니다.** `propose_order`는 금액·상품·배송지·카드가 담긴
`draft` 주문만 만들고, 앱이 채팅에 확인 카드를 띄웁니다. 사용자가 [주문 확인]을 탭하면 앱이
`POST /orders/{id}/confirm`을 호출하고, 그때 비로소 서버가 Stripe 결제를 실행합니다.
금액·상품은 서버가 카탈로그 기준으로 다시 계산하므로 LLM 출력이나 클라이언트 값은 신뢰하지 않습니다.
이 확인 단계는 별도 결제 "페이지"가 아니라 채팅 안의 인라인 카드입니다.

### 데이터 흐름

1. **스캔** — `RoomCaptureView` → `CapturedRoom` → `RoomDocument` → `RoomExporter`가
   `Documents/RoomScans/<id>/`에 `room.json`, `captured-room.json`, `room.usdz` 저장.
2. **홈 표시** — 가장 최근 스캔의 `room.usdz`를 3D 미니어처로 렌더링. (현재 샘플은 앱 재실행 시
   자동 복원하지 않으므로 `ScanStore` 필요)
3. **대화** — 앱이 질문 + `room.json`을 `AgentClient`로 전송, 서버가 에이전트 루프를 돌리며
   텍스트와 구조화된 블록(`product_cards`, `place_in_room`, `order_draft`)을 스트리밍으로 돌려줌.
4. **시뮬레이션** — 카드 탭 시 `Product`의 3D 에셋(없으면 `dimensions` 크기의 박스)을
   `room.json` 월드 좌표(미터, y-up, 열 우선 4×4)에 배치·드래그. 같은 카드를 다시 탭하면 종료.
5. **주문** — `order_draft` 블록 → 확인 카드 → [주문 확인] → 서버가 Stripe `PaymentIntent`를
   저장된 PaymentMethod로 확정(`Idempotency-Key = orderID`) → 웹훅으로 최종 상태 확정 →
   에이전트가 채팅에 결과 메시지 → `OrderStore`/Order History에 기록.

### Stripe 연동 (테스트 모드)

- **키**: `sk_test_…`와 LLM API 키는 **백엔드 환경변수에만** 둡니다. 앱에는 publishable key(`pk_test_…`)만 넣습니다.
- **Customer**: 로그인이 없으므로 앱 최초 실행 시 서버가 기기 단위 Customer를 만들고 익명 토큰을 발급합니다.
- **카드 등록** (프로필 → Payment Method): 서버가 `SetupIntent`를 만들고 앱이 Stripe iOS SDK로 카드를 저장.
  카드 번호는 앱·서버를 거치지 않고 Stripe로 직접 갑니다. 테스트 카드: `4242 4242 4242 4242`.
- **결제**: 확인 탭 후 서버가 저장된 PaymentMethod로 `PaymentIntent`(`confirm=true`)를 생성.
  3DS 등 추가 인증이 필요하면 `requires_action`을 앱에 돌려주고 Stripe SDK가 인증 시트를 띄웁니다.
  인증이 끝나면 같은 주문 흐름이 이어지며 결과 메시지는 여전히 채팅에 표시됩니다.
- **상태 확정**: 클라이언트 응답이 아니라 웹훅(`payment_intent.succeeded` / `payment_failed`)을 기준으로 주문 상태를 바꿉니다.
- **실제 배송은 일어나지 않습니다.** 테스트 모드이므로 실제 청구도 없습니다.

### 설계 결정 / 전제

- **계정**: 로그인 없이 시작. 프로필(이름·주소)은 기기에 저장, 카드는 Stripe가 보관, 주문 내역은 서버가 보관하고
  앱은 익명 토큰으로 조회합니다. 로그인 추가 시 익명 Customer를 계정에 연결합니다.
- **안전장치**: 결제는 사용자 탭 없이는 실행되지 않음 / 서버가 가격 재계산 / 주문 1건당 멱등 키 / 1회 상한 금액 설정.
- **배치 가능 여부**: RoomPlan은 가려진 가구를 놓칠 수 있으므로 빈 면적 계산만으로 단정하지 않고,
  시뮬레이션에서 사용자가 눈으로 확인·조정합니다.
- **좌표**: 서로 다른 스캔의 월드 좌표는 정렬되지 않습니다. `Placement`는 스캔 ID와 함께 저장합니다.

### 아직 정해지지 않은 것

- **상품 카탈로그 출처**: 프로토타입은 IKEA 상품을 보여주지만, 테스트 모드에서 실제 IKEA 재고·가격 API를 쓸 수 없습니다.
  해커톤에서는 자체 시드 카탈로그(이름·가격·치수·이미지·3D 에셋)를 쓰는 안을 전제로 하며 확정이 필요합니다.
- **백엔드 스택과 호스팅**, 에이전트에 쓸 LLM 모델.
- **배송 상태**: 테스트 모드의 배송 진행(`shipped` 등)을 시뮬레이션할지 여부.
- **주문 확인 카드 디자인**: Figma에 없음.

### 구현 현황

| 영역 | 상태 |
| --- | --- |
| Splash / 앱 아이콘 / 로고 에셋 | 완료 (`Tuck/Resources/Assets.xcassets`) |
| Scan (RoomPlan, JSON·USDZ 내보내기) | 완료, 실기기 검증 필요 |
| Home 레이아웃, Chat UI, 추천 카드, 주문 확인 카드 | 미구현 |
| Simulation (가구 배치·이동) | 미구현 |
| Profile (주소·카드 등록·주문 내역) | 미구현 |
| Agent 백엔드 (에이전트 루프, 도구, Stripe, 웹훅) | 미구현 |

## 프로젝트 구조

```
tuck/
├── Tuck.xcodeproj
├── Tuck/                       # 정식 iOS 앱 (번들 ID: com.hackathon.tuck)
│   ├── App/                    # @main 진입점 (TuckApp)
│   ├── Features/Scan/          # 스캔 화면(ScanView, RoomPlan 연결, 상태 관리)
│   ├── Models/                 # RoomDocument 등 JSON 계약 모델
│   ├── Services/               # 파일 저장·내보내기 (RoomExporter)
│   └── Resources/              # Info.plist, Assets.xcassets (AppIcon, TuckLogo, LaunchLogo, TuckBrown)
├── backend/                    # (예정) Agent 서버: 에이전트 루프·도구·Stripe·웹훅
├── docs/                       # room.json 계약(room-json-contract.md)과 예제
└── RoomScanStarter/            # 정식 개발 전 테스트용 프로젝트. 원본 보존, 수정하지 않음
```

- `Tuck/`의 스캔 코드는 `RoomScanStarter/`에서 가져와 구조만 정리한 것입니다. 동작은 동일하고,
  이름만 `TuckApp`, `ScanView`로 바꿨습니다. 이후 개발은 `Tuck/`에서만 합니다.
- `RoomScanStarter/`는 참고용 원본입니다. 삭제·이름 변경·수정하지 않습니다.
- 새 기능은 `Tuck/Features/<이름>/`에 추가하고, 화면에 종속되지 않는 타입은 `Models/`,
  I/O·외부 연동은 `Services/`에 둡니다. Xcode에서 폴더를 추가하면 그룹도 같은 경로로 만드세요.
- `room.json` 규칙은 [docs/room-json-contract.md](docs/room-json-contract.md) 참고.

## 브랜드

- 메인 컬러: 갈색 `#4A352B` (`TuckBrown`), 보조 흰색 `#F3F1EE` 계열
- 앱 아이콘: `AppIcon` (1024px, 알파 없음 — iOS가 모서리를 마스킹)
- 워드마크: `TuckLogo` — 홈 상단 좌측 로고 (Figma 기준 약 88×35pt)

## 개발 환경

- Xcode 16+, iOS/iPadOS 17+, LiDAR 기기 필요 (Simulator 스캔 불가)
- 린트: `brew install swiftlint` 후 저장소 루트에서 `swiftlint`
