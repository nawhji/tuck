import Foundation
import SceneKit
import ModelIO
import UIKit
import simd

/// Loads verified, offline material payloads for the three supplied demo chairs.
/// Their original USDZ files remain available for Quick Look. The prepared path
/// avoids SceneKit/Model I/O texture reinterpretation and all old disk caches.
actor FurnitureModelLibrary {
    static let shared = FurnitureModelLibrary()

    func payload(for id: String) throws -> Data {
        guard FurnitureCatalog.supports(id),
              let url = Bundle.main.url(forResource: id, withExtension: "tuckmodel",
                                        subdirectory: "ChairMaterials") else {
            throw FurnitureError.missingModel(id)
        }
        let data = try Data(contentsOf: url)
        let model = try JSONDecoder().decode(ModelPayload.self, from: data)
        guard model.id == id, model.appearanceVersion == 1, !model.parts.isEmpty,
              model.parts.allSatisfy({ $0.indices != nil && $0.tangents != nil &&
                  $0.texture != nil && $0.normalTexture != nil &&
                  $0.roughnessTexture != nil && $0.metallicTexture != nil }) else {
            throw FurnitureError.unsupportedGeometry
        }
        return data
    }

    struct ModelPayload: Codable {
        let id: String
        let label: String
        let parts: [Part]
        let bounds: [[Float]]
        var appearanceVersion: Int? = nil
    }

    struct Part: Codable {
        var positions: String
        var normals: String
        var uvs: String
        let color: [Float]
        let roughness: Float
        let texture: String?
        let normalTexture: String?
        let normalStrength: Float?
        let roughnessTexture: String?
        var indices: String? = nil
        var tangents: String? = nil
        var metallic: Float? = nil
        var metallicTexture: String? = nil
    }

    /// Internal so the iOS test target can verify hierarchy, units and decoding
    /// with synthetic geometry without having to download any model.
    static func export(scene: SCNScene, id: String, label: String, target: [Double]) throws -> ModelPayload {
        struct Mesh {
            var positions: [SIMD3<Float>]
            var normals: [SIMD3<Float>]
            var uvs: [SIMD2<Float>]
            let color: [Float]
            let roughness: Float
            let texture: String?
            let normalTexture: String?
            let normalStrength: Float
            let roughnessTexture: String?
        }
        var meshes: [Mesh] = []
        var textureCache: [ObjectIdentifier: String] = [:]
        func map(_ property: SCNMaterialProperty) -> String? {
            let key = ObjectIdentifier(property)
            if let cached = textureCache[key] { return cached }
            let image = textureData(property.contents)
            if let image { textureCache[key] = image }
            return image
        }
        var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
        var failure: Error?
        scene.rootNode.enumerateHierarchy { node, _ in
            guard failure == nil, !node.isHidden, let geometry = node.geometry else { return }
            do {
                guard let vertices = geometry.sources(for: .vertex).first else { return }
                let points = try vectors(vertices, count: 3)
                let normalSource = geometry.sources(for: .normal).first
                let normals = try normalSource.map { try vectors($0, count: 3) }
                let uvSource = geometry.sources(for: .texcoord).first
                let uv = try uvSource.map { try vectors($0, count: 2) }
                let matrix = node.simdWorldTransform
                let linear = simd_float3x3(columns: (matrix.columns.0.xyz, matrix.columns.1.xyz, matrix.columns.2.xyz))
                guard abs(simd_determinant(linear)) > 1e-12 else { return }
                let normalMatrix = simd_transpose(simd_inverse(linear))
                for (index, element) in geometry.elements.enumerated() {
                    let indices = try triangles(element)
                    let material = geometry.materials.isEmpty ? SCNMaterial() : geometry.materials[index % geometry.materials.count]
                    let transformUV = SCNMatrix4ToMat4(material.diffuse.contentsTransform)
                    let diffuse = colorComponents(material.diffuse.contents)
                    let tint = colorComponents(material.multiply.contents)
                    let color = zip(diffuse, tint).map { pair in pair.0 * pair.1 }
                    let roughnessMap = map(material.roughness)
                    var mesh = Mesh(positions: [], normals: [], uvs: [], color: color,
                        roughness: roughnessMap == nil ? scalar(material.roughness.contents, fallback: 0.72) : 1,
                        texture: map(material.diffuse), normalTexture: map(material.normal),
                        normalStrength: Float(material.normal.intensity), roughnessTexture: roughnessMap)
                    for face in stride(from: 0, to: indices.count, by: 3) {
                        let triple = Array(indices[face..<face + 3])
                        guard triple.allSatisfy({ $0 >= 0 && $0 < points.count }) else {
                            throw FurnitureError.unsupportedGeometry
                        }
                        let world = triple.map { i -> SIMD3<Float> in
                            let p = points[i]
                            return (matrix * SIMD4(p[0], p[1], p[2], 1)).xyz
                        }
                        let crossProduct = simd_cross(world[1] - world[0], world[2] - world[0])
                        guard simd_length(crossProduct) > 1e-10 else { continue }
                        for (corner, i) in triple.enumerated() {
                            let p = world[corner]
                            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw FurnitureError.unsupportedGeometry }
                            low = simd_min(low, p); high = simd_max(high, p)
                            mesh.positions.append(p)
                            if let normals, i < normals.count {
                                let n = normals[i]
                                let transformed = normalMatrix * SIMD3(n[0], n[1], n[2])
                                mesh.normals.append(simd_length(transformed) > 1e-8 ? simd_normalize(transformed) : simd_normalize(crossProduct))
                            } else { mesh.normals.append(simd_normalize(crossProduct)) }
                            let t = uv.flatMap { i < $0.count ? $0[i] : nil } ?? [0, 0]
                            let q = transformUV * SIMD4(t[0], t[1], 0, 1)
                            mesh.uvs.append(SIMD2(q.x, q.y))
                        }
                    }
                    if !mesh.positions.isEmpty { meshes.append(mesh) }
                }
            } catch { failure = error }
        }
        if let failure { throw failure }
        let size = high - low
        guard !meshes.isEmpty, target.count == 3, size.x > 1e-6, size.y > 1e-6, size.z > 1e-6 else {
            throw FurnitureError.emptyModel
        }
        // Uniform scaling preserves the supplied chair's shape even when its
        // USDZ uses centimeters. Bottom-centering gives it a floor-level pivot.
        let scale = min(Float(target[0]) / size.x, Float(target[1]) / size.y, Float(target[2]) / size.z)
        let pivot = SIMD3((low.x + high.x) / 2, low.y, (low.z + high.z) / 2)
        let parts = meshes.map { mesh -> Part in
            let positions = mesh.positions.flatMap { p -> [Float] in
                let q = (p - pivot) * scale
                return [q.x, q.y, q.z]
            }
            return Part(positions: packed(positions), normals: packed(mesh.normals.flatMap { [$0.x, $0.y, $0.z] }),
                uvs: packed(mesh.uvs.flatMap { [$0.x, $0.y] }), color: mesh.color,
                roughness: min(1, max(0.05, mesh.roughness)), texture: mesh.texture,
                normalTexture: mesh.normalTexture, normalStrength: mesh.normalStrength,
                roughnessTexture: mesh.roughnessTexture)
        }
        let halfX = size.x * scale / 2, halfZ = size.z * scale / 2
        return ModelPayload(id: id, label: label, parts: parts,
            bounds: [[-halfX, 0, -halfZ], [halfX, size.y * scale, halfZ]])
    }

    private static func packed(_ values: [Float]) -> String {
        values.withUnsafeBufferPointer { Data(buffer: $0).base64EncodedString() }
    }

    private static func vectors(_ source: SCNGeometrySource, count: Int) throws -> [[Float]] {
        guard source.usesFloatComponents, [2, 4, 8].contains(source.bytesPerComponent),
              source.componentsPerVector >= count else { throw FurnitureError.unsupportedGeometry }
        let stride = source.dataStride > 0 ? source.dataStride : source.componentsPerVector * source.bytesPerComponent
        return try source.data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            try (0..<source.vectorCount).map { vector in
                try (0..<count).map { component in
                    let offset = source.dataOffset + vector * stride + component * source.bytesPerComponent
                    guard offset >= 0, offset + source.bytesPerComponent <= bytes.count else {
                        throw FurnitureError.unsupportedGeometry
                    }
                    let value: Float
                    switch source.bytesPerComponent {
                    case 2: value = Float(Float16(bitPattern: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                    case 4: value = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    default: value = Float(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                    }
                    guard value.isFinite else { throw FurnitureError.unsupportedGeometry }
                    return value
                }
            }
        }
    }

    private static func triangles(_ element: SCNGeometryElement) throws -> [Int] {
        guard [1, 2, 4].contains(element.bytesPerIndex) else { throw FurnitureError.unsupportedGeometry }
        let indices: [Int] = element.data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            stride(from: 0, through: max(-1, bytes.count - element.bytesPerIndex), by: element.bytesPerIndex).map { offset in
                switch element.bytesPerIndex {
                case 1: Int(bytes[offset])
                case 2: Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                default: Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                }
            }
        }
        switch element.primitiveType {
        case .triangles:
            guard indices.count >= element.primitiveCount * 3 else { throw FurnitureError.unsupportedGeometry }
            return Array(indices.prefix(element.primitiveCount * 3))
        case .triangleStrip:
            guard indices.count >= element.primitiveCount + 2 else { throw FurnitureError.unsupportedGeometry }
            return (0..<element.primitiveCount).flatMap { i in
                i.isMultiple(of: 2) ? [indices[i], indices[i + 1], indices[i + 2]] : [indices[i + 1], indices[i], indices[i + 2]]
            }
        case .polygon:
            let counts = Array(indices.prefix(element.primitiveCount))
            var cursor = element.primitiveCount, result: [Int] = []
            for count in counts {
                guard count >= 3, cursor + count <= indices.count else { throw FurnitureError.unsupportedGeometry }
                for i in 1..<count - 1 { result += [indices[cursor], indices[cursor + i], indices[cursor + i + 1]] }
                cursor += count
            }
            return result
        default: throw FurnitureError.unsupportedGeometry
        }
    }

    private static func colorComponents(_ contents: Any?) -> [Float] {
        let color: UIColor
        if let value = contents as? UIColor { color = value }
        else if let value = contents, CFGetTypeID(value as CFTypeRef) == CGColorGetTypeID() {
            color = UIColor(cgColor: value as! CGColor)
        } else { return [1, 1, 1] }
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Float(r), Float(g), Float(b)]
    }

    private static func scalar(_ contents: Any?, fallback: Float) -> Float {
        if let number = contents as? NSNumber { return number.floatValue }
        if contents is UIColor { return colorComponents(contents).reduce(0, +) / 3 }
        return fallback
    }

    private static func textureData(_ contents: Any?) -> String? {
        let image: UIImage?
        if let value = contents as? UIImage { image = value }
        else if let value = contents as? Data { image = UIImage(data: value) }
        else if let value = contents as? URL, value.isFileURL { image = UIImage(contentsOfFile: value.path) }
        else if let value = contents as? String {
            image = UIImage(contentsOfFile: URL(string: value).flatMap { $0.isFileURL ? $0.path : nil } ?? value)
        }
        else if let value = contents as? MDLTexture { image = Self.image(from: value) }
        else if let value = contents, !(value is UIColor), !(value is NSNumber),
                CFGetTypeID(value as CFTypeRef) == CGImageGetTypeID() {
            image = UIImage(cgImage: value as! CGImage)
        }
        else { image = nil }
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, 2048 / max(pixels.width, pixels.height))
        let size = CGSize(width: max(1, floor(pixels.width * ratio)), height: max(1, floor(pixels.height * ratio)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // Lossless color, normal and roughness maps retain leather/fabric detail.
        return resized.pngData().map { "data:image/png;base64," + $0.base64EncodedString() }
    }

    private static func image(from texture: MDLTexture) -> UIImage? {
        guard texture.channelEncoding == .uInt8,
              let data = texture.texelDataWithTopLeftOrigin(), texture.channelCount >= 3 else { return nil }
        let width = Int(texture.dimensions.x), height = Int(texture.dimensions.y), channels = texture.channelCount
        let rowStride = max(texture.rowStride, width * channels)
        guard width > 0, height > 0, data.count >= (height - 1) * rowStride + width * channels else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for pixel in 0..<width * height {
                let offset = (pixel / width) * rowStride + (pixel % width) * channels
                for channel in 0..<3 { rgba[pixel * 4 + channel] = bytes[offset + channel] }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
