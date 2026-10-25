# 홈 카메라 → RoomPlan 연결

## 이번 변경

기준 저장소 커밋: `f26498f` (상품 카탈로그·채팅 개선이 포함된 main).

- 홈의 카메라와 점선 원의 + 버튼이 기존 `ScanView`를 전체 화면으로 연다.
- LiDAR 지원 여부 확인 → 카메라 권한 요청 → 실제 `RoomCaptureView` 스캔 시작.
- `스캔 완료` → Apple의 3D 결과 미리보기 → 벽·가구의 추정 치수 표시.
- 기존 `RoomExporter`로 아이폰 내부에 자동 저장. `홈에 적용`은 저장 결과가 있을 때 활성화된다.
- 홈에서 USDZ를 회전·확대하고 `View measurements`로 치수·공유 화면을 연다.
- 앱 재실행 시 가장 최근에 읽을 수 있는 스캔을 복원한다. 이전 스캔 파일도 그대로 남는다.
- 권한 거부, 비지원 기기, 빈 스캔, 처리 지연, 취소, 파일 저장/내보내기 실패를 처리한다.
- `RoomScanStarter/` 원본, 상품 데이터, Claude 채팅 서비스와 채팅 UI는 변경하지 않았다.
- 예시 동영상에 맞춘 공간 제작, 가구 배치, 결제는 이번 변경에 포함하지 않았다.

스캔은 Apple RoomPlan/ARKit와 로컬 파일 저장만 사용한다. 유료 API·외부 서버·API 키가 필요하지 않다.
기존 Claude 채팅은 별도 기능이며 그대로 유지된다. 스캔 파일을 채팅 서버로 자동 업로드하지 않는다.

## 기존 저장소에 패치 적용

팀원이 작업 중인 파일을 폴더째 덮어쓰지 않는다. 저장소에서 먼저 `git status`로 작업 내용을 확인하고
변경 내용을 커밋하거나 따로 보관한 다음 적용한다. 아래 경로는 다운로드한 패치의 실제 위치로 바꾼다.

```bash
git switch -c feat/home-roomplan
git apply --check ~/Downloads/tuck-roomplan.patch
git apply ~/Downloads/tuck-roomplan.patch
bash scripts/setup-local.sh
open Tuck.xcodeproj
```

`--check`에서 오류가 나면 두 번째 `git apply`는 실행하지 않는다. 팀원의 최신 수정과 충돌한다는 뜻일 수 있다.
이때 오류와 `git status`를 공유해 병합한다. `git reset --hard`로 팀원 변경을 지우지 않는다.
패치에는 새 Swift 파일의 Xcode target 등록과 XCTest target도 포함되어 있다.

전체 프로젝트 ZIP을 받았다면 기존 폴더와 별개로 압축을 풀고 그 폴더에서 마지막 두 명령만 실행해도 된다.
ZIP에는 `.git`, 개인 API 키, 사용자별 Xcode 설정이 없다.

## Xcode 초보용: iPhone 14 Pro에서 실행

1. Mac에서 Xcode를 설치하고 한 번 실행해 필요한 iOS 플랫폼 구성 요소 설치를 마친다.
   프로젝트의 최소 타깃은 iOS 17. 실제 아이폰의 iOS 버전을 지원하는 Xcode를 사용한다.
2. VS Code 터미널에서 저장소를 연 상태로 `bash scripts/setup-local.sh` 실행.
   기존 `Secrets.swift`는 보존하고, 없을 때만 **빈 키** 파일을 만든다. 스캔에는 키를 넣지 않아도 된다.
   기존 프로젝트가 이 파일을 컴파일 대상으로 참조하기 때문에 파일 자체는 필요하다.
3. 루트의 **`Tuck.xcodeproj`** 를 연다. `RoomScanStarter.xcodeproj`가 아니다.
4. 아이폰을 케이블로 Mac에 연결하고, 아이폰에서 컴퓨터를 신뢰한다. 잠금을 해제한다.
5. Xcode → Settings → Apple Accounts(버전에 따라 Accounts)에서 본인 Apple 계정으로 로그인한다.
6. 왼쪽 파란 Tuck 프로젝트 → TARGETS의 **Tuck** → Signing & Capabilities:
   `Automatically manage signing` 켜기 → `Team`을 본인 Personal Team/개발 팀으로 선택.
   기존 저장소에는 팀원의 Team ID가 있으므로 내 계정으로 바꿔야 한다.
   Bundle Identifier 충돌 시 `com.본인이름.tuck`처럼 고유하게 바꾼다.
7. 아이폰 설정 → 개인정보 보호 및 보안 → **개발자 모드**를 켜고 안내에 따라 재시동·확인한다.
   항목이 없다면 먼저 Xcode에서 기기가 인식되었는지 확인한다.
8. Xcode 상단 Scheme은 **Tuck**, 실행 대상은 **연결한 실제 iPhone 14 Pro**로 선택한다.
9. ▶ 또는 `⌘R`로 빌드·설치·실행한다. 권한/서명 안내가 뜨면 Xcode와 기기의 안내에 따른다.
10. 홈 카메라 탭 → 카메라 허용 → 벽·바닥·가구가 보이도록 천천히 방을 둘러본다.
    `스캔 완료` 후 처리·저장이 끝나면 3D를 회전하고 치수를 확인한 뒤 `홈에 적용`을 누른다.

SF Pro는 SwiftUI 시스템 폰트를 통해 사용하며 별도 폰트 파일을 설치할 필요가 없다.
RoomPlan은 LiDAR가 필요하므로 Simulator에서는 실제 스캔 대신 비지원 안내가 표시된다.
iPhone 14 Pro에서 실제 스캔을 확인해야 한다. 결과는 사진 같은 복원이 아닌 RoomPlan의 구조·가구 모델이다.

## 저장 위치와 의미

앱 Documents 아래 `RoomScans/<스캔 ID>/`:

| 파일 | 내용 |
| --- | --- |
| `room.json` | 팀 공유용 치수·위치·회전 행렬·가구 이름 |
| `captured-room.json` | Apple 원본 CapturedRoom 데이터 |
| `room.usdz` | 3D 미리보기 및 공유용 모델 |

치수는 추정치다. 데이터는 미터, 화면은 cm이다. 벽·바닥 치수는 각각의 로컬 축 기준이며
UI의 높이가 언제나 월드 수직 높이를 뜻하지 않는다. 방 전체 면적이나 빈 공간을 계산하는 기능은 추가하지 않았다.
세부 계약은 [room-json-contract.md](room-json-contract.md) 참고.

- 스캔 결과는 자동 저장되며 `홈에 적용`은 저장된 방을 홈에 연결한다.
- 재스캔 중 취소하면 기존 홈의 저장된 방은 유지된다.
- USDZ만 실패하면 치수 JSON은 남는다. 오류를 표시하고 `저장 재시도`를 제공한다.
- 파일 앱의 나의 iPhone → Tuck 또는 앱의 공유 버튼에서 파일을 내보낼 수 있다.
- 앱 삭제 시 앱 내부 파일도 삭제되므로 필요한 스캔은 공유해서 별도로 보관한다.

## 검증 상태

이 변경을 작성한 환경은 **Linux이며 Xcode, Apple SDK, 연결된 아이폰이 없다.**
`xcodebuild`를 실제 호출했지만 `command not found`로 실행되지 않았다.
**따라서 iOS 빌드 성공, XCTest 통과, 실제 LiDAR 스캔 성공을 확인한 상태가 아니다.**

수행한 검사:

- Swift 구문 파서 검사 (컴파일러의 타입 검사와는 다름).
- Xcode 프로젝트 OpenStep 형식, 타깃의 소스 파일 참조, Info.plist·공유 Scheme 구조 검사.
- `git diff --check` 및 수정 범위 점검.
- RoomPlan delegate/결과 처리 및 지원 기기 API를 Apple 문서와 대조.

Mac에서 두 SDK로 서명 없는 컴파일 확인:

```bash
bash scripts/check-ios-build.sh
```

실제로 XCTest를 실행하려면 Xcode 상단에서 iPhone **Simulator** 선택 후 **Product → Test (`⌘U`)**.
저장소 복원·손상 파일 처리·취소 후 콜백 무시 등 **7개 XCTest**를 추가했다. 아직 실행하지 않았다.
CLI로는 `xcrun simctl list devices available`에서 Simulator UDID를 확인한 뒤:

```bash
bash scripts/check-ios-build.sh YOUR_SIMULATOR_UDID
```

빌드 로그는 `.build/logs/`에 남는다. 빌드 오류가 있으면 첫 번째 빨간 오류 메시지 또는 이 로그를 공유하면 된다.

실기기 확인 목록:

- 첫 실행 권한 허용 후 카메라/RoomPlan 안내가 보이는지.
- 권한 거부 후 앱 설정에서 켜고 재시도할 수 있는지.
- 벽·가구 스캔 → 완료 → 3D·cm 치수 → 저장 → 홈 미리보기가 되는지.
- 앱을 완전히 종료했다 다시 실행해 같은 방·치수를 불러오는지.
- 결과의 가구 이름 변경 후 홈 치수 화면에도 반영되는지.
- 재스캔 취소 시 이전 방이 남고, 스캔 중 앱을 배경으로 옮겨도 멈춤/오류 안내로 복구되는지.
- JSON·USDZ 공유, 3D 회전·확대가 되는지.
- 기존 상품 카드, 채팅, 키보드, 시트 드래그 동작에 변화가 없는지.

## 참고한 Apple 공식 문서

- [RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)
- [RoomCaptureViewDelegate](https://developer.apple.com/documentation/roomplan/roomcaptureviewdelegate)
- [지원 여부](https://developer.apple.com/documentation/roomplan/roomcapturesession/issupported)
- [실제 기기에서 앱 실행](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [개발자 모드](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
