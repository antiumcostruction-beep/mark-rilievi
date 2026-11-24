import ARKit
import CoreImage
import ImageIO
import Metal
import simd

/// Legge i dati utili da un fotogramma ARKit (profondità del laser + colori).
enum LetturaFrame {

    /// Punti 3D (in coordinate del mondo) dalla mappa di profondità, solo confidenza alta.
    static func punti(da frame: ARFrame, passo: Int, distanzaMax: Float) -> [PuntoColore] {
        guard let sd = frame.sceneDepth ?? frame.smoothedSceneDepth else { return [] }
        let depth = sd.depthMap
        let immagine = frame.capturedImage
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(immagine, .readOnly)
        if let c = sd.confidenceMap { CVPixelBufferLockBaseAddress(c, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(immagine, .readOnly)
            if let c = sd.confidenceMap { CVPixelBufferUnlockBaseAddress(c, .readOnly) }
        }
        guard let baseD = CVPixelBufferGetBaseAddress(depth),
              CVPixelBufferGetPlaneCount(immagine) >= 2,
              let baseY = CVPixelBufferGetBaseAddressOfPlane(immagine, 0),
              let baseC = CVPixelBufferGetBaseAddressOfPlane(immagine, 1) else { return [] }

        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        let rigaD = CVPixelBufferGetBytesPerRow(depth)
        let iw = CVPixelBufferGetWidthOfPlane(immagine, 0), ih = CVPixelBufferGetHeightOfPlane(immagine, 0)
        let rigaY = CVPixelBufferGetBytesPerRowOfPlane(immagine, 0)
        let rigaC = CVPixelBufferGetBytesPerRowOfPlane(immagine, 1)

        var baseConf: UnsafeMutableRawPointer? = nil
        var rigaConf = 0
        if let c = sd.confidenceMap {
            baseConf = CVPixelBufferGetBaseAddress(c)
            rigaConf = CVPixelBufferGetBytesPerRow(c)
        }

        let K = frame.camera.intrinsics
        let sx = Float(w) / Float(iw), sy = Float(h) / Float(ih)
        let fx = K.columns.0.x * sx, fy = K.columns.1.y * sy
        let cx = K.columns.2.x * sx, cy = K.columns.2.y * sy
        let T = frame.camera.transform
        let alta = UInt8(ARConfidenceLevel.high.rawValue)

        var out: [PuntoColore] = []
        out.reserveCapacity((w / passo) * (h / passo))
        var v = 0
        while v < h {
            let rigaPtr = baseD.advanced(by: v * rigaD).assumingMemoryBound(to: Float32.self)
            var u = 0
            while u < w {
                defer { u += passo }
                if let bc = baseConf {
                    let conf = bc.advanced(by: v * rigaConf).assumingMemoryBound(to: UInt8.self)[u]
                    if conf < alta { continue }
                }
                let d = rigaPtr[u]
                if !(d > 0.15 && d <= distanzaMax) { continue }
                let x = (Float(u) + 0.5 - cx) / fx * d
                let y = (Float(v) + 0.5 - cy) / fy * d
                let mondo = T * SIMD4<Float>(x, -y, -d, 1)

                let iu = min(iw - 1, Int((Float(u) + 0.5) / sx))
                let iv = min(ih - 1, Int((Float(v) + 0.5) / sy))
                let Y = Float(baseY.advanced(by: iv * rigaY + iu).assumingMemoryBound(to: UInt8.self).pointee)
                let cPtr = baseC.advanced(by: (iv / 2) * rigaC + (iu / 2) * 2).assumingMemoryBound(to: UInt8.self)
                let cb = Float(cPtr[0]) - 128, cr = Float(cPtr[1]) - 128
                out.append(PuntoColore(p: SIMD3(mondo.x, mondo.y, mondo.z),
                                       r: limita(Y + 1.402 * cr),
                                       g: limita(Y - 0.344136 * cb - 0.714136 * cr),
                                       b: limita(Y + 1.772 * cb)))
            }
            v += passo
        }
        return out
    }

    /// Ripiego: i vertici della maglia 3D di ARKit, se la profondità non arriva.
    static func puntiMaglia(da frame: ARFrame) -> [PuntoColore] {
        var out: [PuntoColore] = []
        for case let a as ARMeshAnchor in frame.anchors {
            let vert = a.geometry.vertices
            let buf = vert.buffer.contents()
            for i in 0..<vert.count {
                let p = buf.advanced(by: vert.offset + vert.stride * i).assumingMemoryBound(to: Float.self)
                let mondo = a.transform * SIMD4<Float>(p[0], p[1], p[2], 1)
                out.append(PuntoColore(p: SIMD3(mondo.x, mondo.y, mondo.z), r: 170, g: 178, b: 186))
            }
        }
        return out
    }

    /// Punti della maglia 3D visibili nel fotogramma, colorati con la fotocamera (quando la profondità non arriva).
    static func puntiMagliaColorati(da frame: ARFrame, distanzaMax: Float) -> [PuntoColore] {
        let immagine = frame.capturedImage
        CVPixelBufferLockBaseAddress(immagine, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(immagine, .readOnly) }
        guard CVPixelBufferGetPlaneCount(immagine) >= 2,
              let baseY = CVPixelBufferGetBaseAddressOfPlane(immagine, 0),
              let baseC = CVPixelBufferGetBaseAddressOfPlane(immagine, 1) else { return [] }
        let iw = CVPixelBufferGetWidthOfPlane(immagine, 0), ih = CVPixelBufferGetHeightOfPlane(immagine, 0)
        let rigaY = CVPixelBufferGetBytesPerRowOfPlane(immagine, 0), rigaC = CVPixelBufferGetBytesPerRowOfPlane(immagine, 1)
        let mondoInCamera = frame.camera.transform.inverse
        let K = frame.camera.intrinsics
        let fx = K.columns.0.x, fy = K.columns.1.y, cx = K.columns.2.x, cy = K.columns.2.y
        var out: [PuntoColore] = []
        for case let a as ARMeshAnchor in frame.anchors {
            let vert = a.geometry.vertices
            let buf = vert.buffer.contents()
            for i in 0..<vert.count {
                let p = buf.advanced(by: vert.offset + vert.stride * i).assumingMemoryBound(to: Float.self)
                let mondo = a.transform * SIMD4<Float>(p[0], p[1], p[2], 1)
                let c = mondoInCamera * mondo          // camera ARKit: guarda verso -z, y in alto
                let d = -c.z
                if d < 0.15 || d > distanzaMax { continue }
                let u = fx * c.x / d + cx, v = cy - fy * c.y / d   // pixel nell'immagine del sensore
                if u < 0 || v < 0 || u >= Float(iw) || v >= Float(ih) { continue }
                let iu = Int(u), iv = Int(v)
                let Y = Float(baseY.advanced(by: iv * rigaY + iu).assumingMemoryBound(to: UInt8.self).pointee)
                let cPtr = baseC.advanced(by: (iv / 2) * rigaC + (iu / 2) * 2).assumingMemoryBound(to: UInt8.self)
                let cb = Float(cPtr[0]) - 128, cr = Float(cPtr[1]) - 128
                out.append(PuntoColore(p: SIMD3(mondo.x, mondo.y, mondo.z),
                                       r: limita(Y + 1.402 * cr), g: limita(Y - 0.344136 * cb - 0.714136 * cr), b: limita(Y + 1.772 * cb)))
            }
        }
        return out
    }

    /// Copia della mappa di profondità (metri, Float32) per misurare sulle foto.
    static func copiaProfondita(da frame: ARFrame) -> (dati: Data, w: Int, h: Int)? {
        guard let sd = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }
        let depth = sd.depthMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        let riga = CVPixelBufferGetBytesPerRow(depth)
        var dati = Data(capacity: w * h * 4)
        for v in 0..<h {
            dati.append(base.advanced(by: v * riga).assumingMemoryBound(to: UInt8.self), count: w * 4)
        }
        return (dati, w, h)
    }

    private static func limita(_ x: Float) -> UInt8 { UInt8(max(0, min(255, x))) }
}

/// Salva le foto (JPEG) con la loro profondità, in sottofondo.
final class Fotografo {
    private let coda = DispatchQueue(label: "foto", qos: .utility)
    private let contesto = CIContext()
    private let cartella: URL
    private(set) var numero = 0

    init(cartella: URL) {
        self.cartella = cartella
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
    }

    struct Meta: Codable {
        var numero: Int
        var data: Date
        var manuale: Bool
        var larghezzaFoto: Int
        var altezzaFoto: Int
        var intrinseci: [Float]      // fx, fy, cx, cy riferiti alla foto
        var posizione: [Float]       // matrice 4x4 della camera, per colonne
        var profonditaLarghezza: Int
        var profonditaAltezza: Int
        var nota: String = "Foto nell'orientamento del sensore (orizzontale). Profondità: Float32 in metri, righe dall'alto."
    }

    func scatta(_ frame: ARFrame, manuale: Bool) {
        numero += 1
        let n = numero
        let immagine = frame.capturedImage
        let K = frame.camera.intrinsics
        let T = frame.camera.transform
        let prof = LetturaFrame.copiaProfondita(da: frame)
        let w = CVPixelBufferGetWidth(immagine), h = CVPixelBufferGetHeight(immagine)
        let nome = String(format: "%03d", n)
        let ciImg = CIImage(cvPixelBuffer: immagine)
        coda.async { [self] in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let opz: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8
            ]
            if let jpg = contesto.jpegRepresentation(of: ciImg, colorSpace: cs, options: opz) {
                try? jpg.write(to: cartella.appendingPathComponent("\(nome).jpg"))
            }
            if let p = prof { try? p.dati.write(to: cartella.appendingPathComponent("\(nome).profondita")) }
            let meta = Meta(numero: n, data: Date(), manuale: manuale, larghezzaFoto: w, altezzaFoto: h,
                            intrinseci: [K.columns.0.x, K.columns.1.y, K.columns.2.x, K.columns.2.y],
                            posizione: [T.columns.0, T.columns.1, T.columns.2, T.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] },
                            profonditaLarghezza: prof?.w ?? 0, profonditaAltezza: prof?.h ?? 0)
            if let d = try? Archivio.codificatore.encode(meta) {
                try? d.write(to: cartella.appendingPathComponent("\(nome).json"))
            }
        }
    }

    /// Aspetta che tutte le foto siano scritte.
    func attendi() { coda.sync {} }
}
