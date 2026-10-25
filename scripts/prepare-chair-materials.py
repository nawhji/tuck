"""Prepare ONLY the three supplied USDZ chairs for the offline room renderer.

Run manually: python -m pip install usd-core numpy Pillow
              python scripts/prepare-chair-materials.py
Xcode does not need Python. Commit the generated resources with this script.
No mesh simplification, UV regeneration, recoloring, or normal-map baking.
"""
import base64
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdShade

ROOT = Path(__file__).resolve().parents[1]
IDS = ("sofa_007_brown", "sofa_027_brown", "sofa_028_brown")
OUTPUT = ROOT / "Tuck/Resources/ChairMaterials"


def encoded(array, dtype):
    return base64.b64encode(np.asarray(array, dtype=dtype).tobytes()).decode("ascii")


def prepare():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with next((ROOT / "data").glob("*.csv")).open() as f:
        rows = {r["id"]: r for r in csv.DictReader(f)}
    reports = []
    for model_id in IDS:
        source = ROOT / "data" / f"{model_id}.usdz"
        stage = Usd.Stage.Open(str(source))
        assert UsdGeom.GetStageUpAxis(stage) == "Y"
        prims = [p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
        assert len(prims) == 1, "Revisit multi-mesh assets before regenerating"
        prim = prims[0]
        mesh = UsdGeom.Mesh(prim)
        # These supplied assets are Y-up with identity transforms. Fail rather
        # than silently changing tangents/handedness if the source is replaced.
        assert np.allclose(np.array(UsdGeom.XformCache().GetLocalToWorldTransform(prim)), np.eye(4))
        positions = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
        normals = np.array(mesh.GetNormalsAttr().Get(), dtype="<f4")
        assert mesh.GetNormalsInterpolation() == "vertex"
        uv = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
        tangent = UsdGeom.PrimvarsAPI(prim).GetPrimvar("tangents")
        assert uv.GetInterpolation() == tangent.GetInterpolation() == "vertex"
        uvs = np.array(uv.ComputeFlattened(), dtype="<f4")
        tangents = np.array(tangent.ComputeFlattened(), dtype="<f4")
        indices = np.array(mesh.GetFaceVertexIndicesAttr().Get(), dtype="<u4")
        assert np.all(np.array(mesh.GetFaceVertexCountsAttr().Get()) == 3)
        assert normals.shape == positions.shape and uvs.shape == (len(positions), 2)
        assert tangents.shape == (len(positions), 4) and indices.max() < len(positions)
        assert all(np.isfinite(a).all() for a in (positions, normals, uvs, tangents))
        assert np.allclose(np.abs(tangents[:, 3]), 1)
        row = rows[model_id]
        dimensions = np.array([float(row[k]) * .0254 for k in ("width_in", "height_in", "depth_in")])
        low, high = positions.min(axis=0), positions.max(axis=0)
        # Same uniform fit as the existing app: preserve original proportions.
        positions -= [(low[0] + high[0]) / 2, low[1], (low[2] + high[2]) / 2]
        positions *= np.min(dimensions / (high - low))
        material, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
        shader, _, _ = material.ComputeSurfaceSource()
        maps, map_report = {}, {}
        with zipfile.ZipFile(source) as archive:
            for input_name, field in (("diffuseColor", "texture"), ("normal", "normalTexture"),
                                      ("roughness", "roughnessTexture"), ("metallic", "metallicTexture")):
                connection = shader.GetInput(input_name).GetConnectedSource()
                assert connection, f"Missing {input_name}"
                texture = UsdShade.Shader(connection[0].GetPrim())
                assert tuple(texture.GetInput("scale").Get()) == ((2, 2, 2, 1) if input_name == "normal" else (1, 1, 1, 1))
                if input_name == "normal":
                    assert tuple(texture.GetInput("bias").Get())[:3] == (-1, -1, -1)
                    assert texture.GetInput("sourceColorSpace").Get() == "raw"
                path = texture.GetInput("file").Get().path.removeprefix("./")
                # Follow material connections, NOT filenames (007 has different
                # color/normal image numbering from 027 and 028).
                raw = archive.read(path)
                image = Image.open(io.BytesIO(raw))
                original_size = image.size
                image = image.convert("RGB" if input_name in ("diffuseColor", "normal") else "L")
                image.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
                data = io.BytesIO()
                # Lossless output; data maps keep their numeric values. No
                # UIKit color conversion or JPEG re-encoding of normal maps.
                image.save(data, format="PNG", optimize=True)
                maps[field] = "data:image/png;base64," + base64.b64encode(data.getvalue()).decode("ascii")
                map_report[input_name] = dict(path=path, sourceSHA256=hashlib.sha256(raw).hexdigest(),
                    sourceSize=original_size, outputSize=image.size)
        part = dict(positions=encoded(positions, "<f4"), normals=encoded(normals, "<f4"),
            uvs=encoded(uvs, "<f4"), tangents=encoded(tangents, "<f4"), indices=encoded(indices, "<u4"),
            color=[1, 1, 1], roughness=1, metallic=1, normalStrength=1, **maps)
        payload = dict(appearanceVersion=1, id=model_id, label=row["name"], parts=[part],
            bounds=[positions.min(axis=0).tolist(), positions.max(axis=0).tolist()])
        output = OUTPUT / f"{model_id}.tuckmodel"
        output.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
        reports.append(dict(id=model_id, sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
            outputSHA256=hashlib.sha256(output.read_bytes()).hexdigest(), vertices=len(positions),
            triangles=len(indices) // 3, maps=map_report))
        print(model_id, len(positions), "vertices;", len(indices) // 3, "triangles;", output.stat().st_size, "bytes")
    (OUTPUT / "manifest.json").write_text(json.dumps(dict(version=1, models=reports), indent=2) + "\n")


if __name__ == "__main__":
    prepare()
