# `room.json` Contract

The iOS app, agent backend, and web client share this format for scan results. See the [example](room.example.json).

`examples/room.example.json` shows the complete structure. **Its values are fictional and were not measured from the attached video.**

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
- `dimensions.width/height/depth` are the sizes of the element's **local x/y/z axes**. Surfaces such as walls and floors can have zero thickness. A floor's local y-axis may differ from world up; displayed width, height, and depth are local-axis dimensions.
- `position` is the element center in world coordinates and matches the last column of `transform`.
- `transform` is a column-major array of 16 values representing a **4×4 matrix** that maps local coordinates into the scan's world coordinates. Include the matrix to preserve rotation; position alone is not enough.
- World coordinates use a right-handed coordinate system with y pointing up. The origin is relative to the scan session, and **the floor is not necessarily at y=0**. Coordinates from separate scans are not automatically aligned.
- `confidence` is RoomPlan's classification confidence, not a measurement error estimate.
- `objects` contains furniture; `walls/doors/windows/openings/floors` contains structural elements.
- `room.json` is a compact format for element dimensions and transforms. Use `captured-room.json` or `room.usdz` when detailed surface geometry or Apple-specific properties are needed.

Example: reconstruct a furniture box from the data with Three.js on the web.

```js
// Use the web team's existing Three.js import for THREE.
const { width, height, depth } = object.dimensions;
const mesh = new THREE.Mesh(
  new THREE.BoxGeometry(width, height, depth),
  new THREE.MeshStandardMaterial({ color: 0xd8c4aa })
);
mesh.matrixAutoUpdate = false;
mesh.matrix.fromArray(object.transform); // Column-major array; do not add position again.
mesh.userData.roomObjectId = object.id;
scene.add(mesh);
```
