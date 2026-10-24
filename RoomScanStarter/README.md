# RoomScanStarter — 해커톤용 RoomPlan 스캐너

참고 영상처럼 실제 카메라 화면에 벽·가구 윤곽선과 미니어처 방을 표시하고,
스캔 완료 후 3D 결과와 치수를 같은 화면에서 확인하는 네이티브 iOS 앱입니다.

## 바로 실행하기

1. 압축을 풀고 `RoomScanStarter.xcodeproj`를 Xcode로 엽니다.
2. 프로젝트 → TARGETS → RoomScanStarter → **Signing & Capabilities**에서
   본인의 Apple 계정 **Team**을 선택합니다. 개인 기기 데모에는 Personal Team을
   사용할 수 있으며, Xcode에서 안내하는 서명 설정을 완료하세요.
3. **Bundle Identifier**를 본인만 사용하는 값으로 바꿉니다.
   예: `com.yourname.furniture.RoomScanStarter`.
4. **LiDAR가 있는 실제 아이폰/아이패드**를 Mac에 연결하고 실행 대상으로 고릅니다.
   기기에서 Mac 신뢰, Developer Mode 활성화 등이 요청되면 안내에 따릅니다.
5. Run(⌘R) → 카메라 허용 → **방 스캔 시작** → 천천히 벽·바닥·가구 촬영 →
   **스캔 완료**를 누릅니다. 카메라가 켜진 화면에서 방을 둘러보는 방식입니다.
6. 3D 결과를 터치해서 확인합니다. 아래에서 가구·구조물 치수를 확인하고,
   가구에 `화장대` 같은 이름을 붙인 뒤 **이름 저장**을 누를 수 있습니다.
7. **JSON 공유** / **3D 공유**로 AirDrop 또는 파일 저장을 선택합니다.

프로젝트 최소 버전은 **iOS/iPadOS 17**이고 SwiftUI + Swift로 작성했습니다.
별도 패키지 설치, API 키, 백엔드 서버가 필요하지 않습니다.
RoomPlan 자체는 iOS 16부터 제공되지만 이 샘플은 iOS 17을 기준으로 구성했습니다.
카메라 사용 설명과 파일 앱 접근 설정은 `Info.plist`에 포함되어 있습니다.

**VS Code에서 Swift 파일을 편집할 수 있습니다. 실제 iOS 빌드·서명·설치는
Mac의 Xcode로 진행하세요.** Simulator에서는 실제 방을 스캔할 수 없습니다.
앱은 `RoomCaptureSession.isSupported`로 현재 기기 지원 여부를 검사합니다.

## 현재 GitHub 저장소에 넣기

기존 저장소 안에 이 `RoomScanStarter` 폴더를 통째로 복사하세요.
팀의 웹/백엔드 코드가 있다면 `ios/RoomScanStarter`에 두어도 됩니다.
`.xcodeproj`와 안쪽 `RoomScanStarter` 소스 폴더는 같은 상위 폴더에 있어야 합니다.

```bash
# 본인 저장소의 루트 디렉터리에서, 폴더를 RoomScanStarter로 복사한 경우
git status
git add RoomScanStarter
git commit -m "feat: add RoomPlan scanning and room export"
git push -u origin HEAD
```

VS Code로 저장소 전체를 열고 Swift 파일을 수정한 뒤 Xcode에서 ⌘R로 실행하면 됩니다.
이미 SwiftUI 앱이 있다면 아래 6개 `.swift` 중 `RoomScanStarterApp.swift`를 제외한
5개를 앱 타깃에 추가하고 기존 앱에서 `ContentView()`를 표시해도 됩니다.
`Info.plist`의 `NSCameraUsageDescription`도 기존 앱 타깃에 추가하세요.
`@main` 앱 진입점은 하나만 사용합니다.

## 파일별 역할

| 파일 | 역할 |
| --- | --- |
| `RoomScanStarterApp.swift` | 앱 시작점 |
| `ContentView.swift` | 스캔, 3D 결과, 치수 목록, 이름 입력, 공유 버튼 |
| `RoomCaptureContainer.swift` | SwiftUI와 Apple RoomCaptureView 연결, 스캔 콜백 처리 |
| `RoomScanner.swift` | 권한, 스캔 시작/종료, 화면 상태와 결과 관리 |
| `RoomDocument.swift` | 팀에서 사용할 JSON 형식, 위치·회전·치수 추출 |
| `RoomExporter.swift` | JSON 및 USDZ 저장 |

## 실제 동작 흐름

`RoomCaptureView`를 화면에 올린 뒤 `captureSession.run(configuration:)`을 호출합니다.
흰 윤곽선, 스캔 가이드, 하단의 작은 방은 RoomPlan 기본 UI입니다.
종료 버튼은 `captureSession.stop(pauseARSession: true)`를 호출합니다.
완성된 `CapturedRoom`은 `captureView(didPresent:error:)`로 들어옵니다.

완료 직후 화면에서 `RoomCaptureView`를 제거하지 않습니다. 그래야 후처리와
3D 결과 표시가 완료됩니다. 완성 결과를 받은 다음 JSON과 USDZ를 저장합니다.
USDZ 생성은 메인 스레드 밖에서 실행합니다. 콜백마다 스캔 ID를 확인하므로
이전 스캔의 늦은 콜백이 새 스캔을 덮어쓰지 않습니다.

## 내보내는 파일

각 스캔은 앱의 `Documents/RoomScans/<스캔 ID>/`에 저장됩니다.
아이폰 **파일 앱 → 나의 iPhone → Room Scan → RoomScans**에서도 접근할 수 있습니다.

| 파일 | 사용처 |
| --- | --- |
| `room.json` | 웹 프론트엔드와 AI/백엔드에서 읽기 쉬운 치수·좌표·이름 데이터 |
| `captured-room.json` | Apple `CapturedRoom` 전체를 인코딩한 원본 구조 데이터 |
| `room.usdz` | Apple 뷰어 및 USDZ를 지원하는 도구에서 열 수 있는 3D 모델 |

일반 JSON 저장이 성공하고 USDZ 생성만 실패하면 JSON은 유지하고 재시도 버튼을 표시합니다.
가구 이름 변경은 `room.json`에 저장하며 Apple 원본 JSON의 카테고리는 유지합니다.
앱 재실행 후 저장 파일은 남지만, 이 최소 샘플은 마지막 스캔을 화면에 자동 복원하지 않습니다.

## 팀에 전달할 JSON 규칙

`examples/room.example.json`에 전체 구조 예제가 있습니다. **예제 값은 가상 데이터이며
첨부 영상에서 측정한 값이 아닙니다.**

```json
{
  "id": "가구 식별자",
  "kind": "object",
  "category": "table",
  "label": "화장대",
  "confidence": "high",
  "dimensions": { "width": 1.0, "height": 0.75, "depth": 0.4 },
  "position": { "x": 1.2, "y": -0.625, "z": -0.9 },
  "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1.2, -0.625, -0.9, 1]
}
```

- **길이 단위는 미터**입니다. UI에서만 `× 100` 해서 cm로 표시합니다.
- `dimensions.width/height/depth`는 요소 **자체 좌표계의 x/y/z 축 크기**입니다.
  벽·바닥 같은 Surface는 두께가 0일 수 있으며, 바닥의 로컬 y축은 월드 높이축과
  다를 수 있습니다. 화면의 가로·높이·깊이 표기는 로컬 축 치수입니다.
- `position`은 요소 중심의 월드 좌표이며 `transform`의 마지막 열과 같습니다.
- `transform`은 로컬 좌표를 스캔의 월드 좌표로 바꾸는 **4×4 행렬 16개 값**을
  열 우선으로 펼친 배열입니다. 위치만 전달하면 회전을 잃으므로 행렬도 전달합니다.
- 월드 좌표는 오른손 좌표계이며 y가 위쪽입니다. 원점은 스캔 세션 기준이고
  **바닥 높이가 반드시 y=0인 것은 아닙니다.** 서로 다른 스캔의 좌표는 자동 정렬되지 않습니다.
- `confidence`는 RoomPlan이 부여한 인식 분류 신뢰도이며 치수의 오차율이 아닙니다.
- `objects`는 가구, `walls/doors/windows/openings/floors`는 구조 요소입니다.
- `room.json`은 요소의 치수와 자세를 전달하는 간단한 형식입니다. 복잡한 표면 형상과
  Apple 고유 속성이 필요하면 `captured-room.json` 또는 `room.usdz`를 사용합니다.

웹에서 Three.js로 가구 상자를 재구성할 때의 예시입니다.

```js
// THREE는 웹 팀의 기존 Three.js import를 사용합니다.
const { width, height, depth } = object.dimensions;
const mesh = new THREE.Mesh(
  new THREE.BoxGeometry(width, height, depth),
  new THREE.MeshStandardMaterial({ color: 0xd8c4aa })
);
mesh.matrixAutoUpdate = false;
mesh.matrix.fromArray(object.transform); // 열 우선 배열. position을 다시 더하지 않기.
mesh.userData.roomObjectId = object.id;
scene.add(mesh);
```

## 현재 기능 범위와 다음 연결 지점

- **일반 MP4 업로드 → RoomPlan 스캔 결과** 변환은 제공하지 않습니다.
  RoomPlan은 기기의 카메라·LiDAR·AR 세션으로 직접 스캔합니다.
  기존 MP4로 3D를 복원하려면 별도 복원 파이프라인을 만들거나 데모용 사전 스캔 결과를 불러와야 합니다.
- RoomPlan의 결과는 벽·가구의 구조 모델입니다. 사진의 질감이 그대로 입혀진
  사실적인 방이나 판매할 가구의 상세 3D 모델을 자동 생성하는 기능은 아닙니다.
- RoomPlan 분류만으로 모든 가구를 정확히 `화장대`라고 식별할 수는 없습니다.
  데모에서는 목록에서 이름을 붙이고 `label == "화장대"`인 요소의 ID와
  `transform`을 AI에 전달하면 됩니다.
- **실제 배치 가능한 여유 공간과 충돌 판정**은 별도 로직입니다. 이 코드는 그 계산에
  필요한 관측된 가구의 크기·자세와 구조 데이터를 기록합니다. 가려진 가구나 사물의
  누락을 고려해야 하며, 방 바닥 면적에서 가구 면적만 빼서 배치 가능성을 단정하면 안 됩니다.
- 상품 추천·배치 편집·서버 업로드·결제 기능은 포함하지 않았습니다. 웹 팀에는 `room.json`을
  전달하고, 웹에서 상자를 재구성하거나 적절한 모델 변환 과정을 통해 3D 뷰어에 연결할 수 있습니다.
  판매 가구의 실제 3D 에셋과 치수는 별도 상품 데이터로 연결합니다.
- 서버 업로드를 붙일 때는 `scanner.files?.json`의 데이터를 서버의 합의된 API로 보내면 됩니다.
  앱에는 임의의 서버 주소나 결제 동작을 넣지 않았습니다.

## 확인 범위

이 프로젝트는 Xcode/iOS SDK가 없는 환경에서 작성했습니다.
프로젝트 구성·파일 참조·JSON 예제·Info.plist의 정적 검사는 수행했지만,
**Xcode 빌드와 실제 LiDAR 기기에서의 실행은 아직 확인하지 못했습니다.**
처음 실행할 때 스캔 → 종료 → 3D 보기 → JSON/3D 공유 → 이름 변경 → 재스캔을
실제 기기에서 확인하세요.

## Apple 공식 자료

- [RoomPlan 소개](https://developer.apple.com/augmented-reality/roomplan/)
- [RoomCaptureView](https://developer.apple.com/documentation/roomplan/roomcaptureview)
- [공식 RoomPlan 샘플](https://developer.apple.com/documentation/roomplan/create-a-3d-model-of-an-interior-room-by-guiding-the-user-through-an-ar-experience)
- [RoomCaptureViewDelegate](https://developer.apple.com/documentation/roomplan/roomcaptureviewdelegate)
- [CapturedRoom](https://developer.apple.com/documentation/roomplan/capturedroom)
