"""Verify committed chair payloads against the actual USDZ source, not mocks.

Requires usd-core, numpy and Pillow (same as prepare-chair-materials.py).
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
folder = ROOT / "Tuck/Resources/ChairMaterials"
manifest = json.loads((folder / "manifest.json").read_text())
assert [m["id"] for m in manifest["models"]] == ["sofa_007_brown", "sofa_027_brown", "sofa_028_brown"]
with next((ROOT / "data").glob("*.csv")).open() as f:
    catalog = {r["id"]: r for r in csv.DictReader(f)}

for report in manifest["models"]:
    model_id = report["id"]
    source = ROOT / "data" / f"{model_id}.usdz"
    output = folder / f"{model_id}.tuckmodel"
    assert hashlib.sha256(source.read_bytes()).hexdigest() == report["sourceSHA256"]
    assert hashlib.sha256(output.read_bytes()).hexdigest() == report["outputSHA256"]
    model = json.loads(output.read_text())
    assert model["id"] == model_id and model["appearanceVersion"] == 1
    part, = model["parts"]
    stage = Usd.Stage.Open(str(source))
    prim = next(p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
    mesh = UsdGeom.Mesh(prim)
    decode = lambda key, dtype="<f4": np.frombuffer(base64.b64decode(part[key]), dtype=dtype)
    original = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
    positions = decode("positions").reshape(-1, 3)
    assert len(positions) == len(original) == report["vertices"]
    np.testing.assert_array_equal(decode("indices", "<u4"), mesh.GetFaceVertexIndicesAttr().Get())
    assert len(decode("indices")) // 3 == report["triangles"]
    np.testing.assert_array_equal(decode("normals").reshape(-1, 3), mesh.GetNormalsAttr().Get())
    for field, name, width in (("uvs", "st", 2), ("tangents", "tangents", 4)):
        np.testing.assert_array_equal(decode(field).reshape(-1, width),
            UsdGeom.PrimvarsAPI(prim).GetPrimvar(name).ComputeFlattened())
    low, high = original.min(axis=0), original.max(axis=0)
    dimensions = np.array([float(catalog[model_id][k]) * .0254 for k in ("width_in", "height_in", "depth_in")])
    expected = (original - [(low[0]+high[0])/2, low[1], (low[2]+high[2])/2]) * min(dimensions/(high-low))
    np.testing.assert_allclose(positions, expected, atol=1e-7)
    np.testing.assert_allclose(model["bounds"], [positions.min(axis=0), positions.max(axis=0)], atol=1e-7)
    assert part["color"] == [1, 1, 1] and part["normalStrength"] == 1
    assert part["roughness"] == part["metallic"] == 1
    material, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
    shader, _, _ = material.ComputeSurfaceSource()
    with zipfile.ZipFile(source) as archive:
        for input_name, field in (("diffuseColor", "texture"), ("normal", "normalTexture"),
                                  ("roughness", "roughnessTexture"), ("metallic", "metallicTexture")):
            texture = UsdShade.Shader(shader.GetInput(input_name).GetConnectedSource()[0].GetPrim())
            path = texture.GetInput("file").Get().path.removeprefix("./")
            assert path == report["maps"][input_name]["path"]
            raw = archive.read(path)
            assert hashlib.sha256(raw).hexdigest() == report["maps"][input_name]["sourceSHA256"]
            expected = Image.open(io.BytesIO(raw)).convert("RGB" if input_name in ("diffuseColor", "normal") else "L")
            expected.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
            actual = Image.open(io.BytesIO(base64.b64decode(part[field].split(",", 1)[1])))
            assert actual.size == (2048, 2048)
            np.testing.assert_array_equal(np.array(actual), np.array(expected))
    print(f"PASS {model_id}: original topology, normals, UVs, tangent signs, uniform scale, and all four source maps")
