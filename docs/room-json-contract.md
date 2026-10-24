# room.json 계약

스캔 결과(`room.json`)를 iOS 앱, 백엔드(에이전트), 웹이 공유하는 형식입니다. 예제: [room.example.json](room.example.json)


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

