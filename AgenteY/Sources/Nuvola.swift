import Foundation
import simd

struct PuntoColore {
    var p: SIMD3<Float>
    var r: UInt8, g: UInt8, b: UInt8
}

/// Nuvola di punti: un punto per "cubetto" (1-3 cm), così la memoria resta sotto controllo.
final class Nuvola {
    private var celle: [Int64: PuntoColore] = [:]
    private let lato: Float
    private let maxPunti = 3_000_000
    private let coda = DispatchQueue(label: "nuvola", qos: .utility)
    private var _conteggio = 0
    private let blocco = NSLock()

    init(lato: Float) { self.lato = lato }

    var conteggio: Int { blocco.lock(); defer { blocco.unlock() }; return _conteggio }

    func aggiungi(_ punti: [PuntoColore]) {
        guard !punti.isEmpty else { return }
        coda.async { [self] in
            for pt in punti {
                guard celle.count < maxPunti else { break }
                let k = chiave(pt.p)
                if celle[k] == nil { celle[k] = pt }
            }
            blocco.lock(); _conteggio = celle.count; blocco.unlock()
        }
    }

    private func chiave(_ p: SIMD3<Float>) -> Int64 {
        let o: Int64 = 1 << 20
        let m: Int64 = (1 << 21) - 1
        let x = (Int64((p.x / lato).rounded(.down)) + o) & m
        let y = (Int64((p.y / lato).rounded(.down)) + o) & m
        let z = (Int64((p.z / lato).rounded(.down)) + o) & m
        return (x << 42) | (y << 21) | z
    }

    /// Scrive un file .ply binario (si apre con CloudCompare, MeshLab, Blender…).
    func salvaPLY(in url: URL) throws -> Int {
        try coda.sync {
            let punti = Array(celle.values)
            var dati = Data()
            let intestazione = """
            ply
            format binary_little_endian 1.0
            comment MARK Rilievi - coordinate in metri, Y verso l'alto
            element vertex \(punti.count)
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            end_header\n
            """
            dati.append(intestazione.data(using: .ascii)!)
            dati.reserveCapacity(dati.count + punti.count * 15)
            for pt in punti {
                var x = pt.p.x.bitPattern.littleEndian
                var y = pt.p.y.bitPattern.littleEndian
                var z = pt.p.z.bitPattern.littleEndian
                withUnsafeBytes(of: &x) { dati.append(contentsOf: $0) }
                withUnsafeBytes(of: &y) { dati.append(contentsOf: $0) }
                withUnsafeBytes(of: &z) { dati.append(contentsOf: $0) }
                dati.append(contentsOf: [pt.r, pt.g, pt.b])
            }
            try dati.write(to: url, options: .atomic)
            return punti.count
        }
    }
}
