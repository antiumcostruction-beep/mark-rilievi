import Foundation
import simd

struct PuntoColore {
    var p: SIMD3<Float>
    var r: UInt8, g: UInt8, b: UInt8
}

/// Una cella della pianta della copertura (25 cm di lato): quanti cubetti confermati ci sono sopra.
struct CellaCopertura: Hashable {
    var i: Int32
    var k: Int32
    var n: Int
}

/// Nuvola di punti a "cubetti" (1-3 cm). Ogni cubetto fa la MEDIA di tutte le volte che il laser lo vede:
/// ripassare lo rende più preciso e riempie i buchi. Un cubetto vale solo se visto almeno 2 volte.
final class Nuvola {
    private struct Cella {
        var sx: Float, sy: Float, sz: Float
        var r: UInt32, g: UInt32, b: UInt32
        var n: UInt16
        var maglia: Bool
    }
    static let lato2D: Float = 0.25          // celle della pianta della copertura
    static let latoVerde: Float = 0.06       // punti verdi mostrati sopra la fotocamera
    static let visteMinime: UInt16 = 2

    private var celle: [Int64: Cella] = [:]
    private var copertura: [Int64: Int] = [:]           // cella 2D -> cubetti confermati
    private var verdi: [Int64: SIMD3<Float>] = [:]      // un punto ogni 6 cm, già confermato
    private let lato: Float
    private let maxPunti = 3_000_000
    private let coda = DispatchQueue(label: "nuvola", qos: .utility)
    private var _conteggio = 0
    private let blocco = NSLock()

    init(lato: Float) { self.lato = lato }

    /// Cubetti confermati (visti almeno 2 volte, oppure presi dalla maglia).
    var conteggio: Int { blocco.lock(); defer { blocco.unlock() }; return _conteggio }

    /// Punti del laser: si sommano (media).
    func aggiungi(_ punti: [PuntoColore]) { aggiungi(punti, maglia: false) }

    /// Punti della maglia 3D (ripiego): entrano solo dove il laser non ha niente, già confermati.
    func aggiungiMaglia(_ punti: [PuntoColore]) { aggiungi(punti, maglia: true) }

    private func aggiungi(_ punti: [PuntoColore], maglia: Bool) {
        guard !punti.isEmpty else { return }
        coda.async { [self] in
            var confermati = 0
            for pt in punti {
                let k = chiave(pt.p, lato)
                if var c = celle[k] {
                    if maglia { continue }
                    if c.maglia { c = Cella(sx: 0, sy: 0, sz: 0, r: 0, g: 0, b: 0, n: 0, maglia: false) }
                    c.sx += pt.p.x; c.sy += pt.p.y; c.sz += pt.p.z
                    c.r += UInt32(pt.r); c.g += UInt32(pt.g); c.b += UInt32(pt.b)
                    if c.n < UInt16.max { c.n += 1 }
                    celle[k] = c
                    if c.n == Nuvola.visteMinime { confermati += 1; segna(pt.p) }
                } else {
                    guard celle.count < maxPunti else { continue }
                    celle[k] = Cella(sx: pt.p.x, sy: pt.p.y, sz: pt.p.z, r: UInt32(pt.r), g: UInt32(pt.g), b: UInt32(pt.b),
                                     n: maglia ? Nuvola.visteMinime : 1, maglia: maglia)
                    if maglia { confermati += 1; segna(pt.p) }
                }
            }
            if confermati > 0 { blocco.lock(); _conteggio += confermati; blocco.unlock() }
        }
    }

    private func segna(_ p: SIMD3<Float>) {
        let k2 = chiave2D(p)
        copertura[k2, default: 0] += 1
        let kv = chiave(p, Nuvola.latoVerde)
        if verdi[kv] == nil { verdi[kv] = p }
    }

    private func chiave(_ p: SIMD3<Float>, _ l: Float) -> Int64 {
        let o: Int64 = 1 << 20
        let m: Int64 = (1 << 21) - 1
        let x = (Int64((p.x / l).rounded(.down)) + o) & m
        let y = (Int64((p.y / l).rounded(.down)) + o) & m
        let z = (Int64((p.z / l).rounded(.down)) + o) & m
        return (x << 42) | (y << 21) | z
    }
    private func chiave2D(_ p: SIMD3<Float>) -> Int64 {
        let i = Int64((p.x / Nuvola.lato2D).rounded(.down)), k = Int64((p.z / Nuvola.lato2D).rounded(.down))
        return (i << 32) | (k & 0xFFFF_FFFF)
    }

    /// Fotografia per la guida: punti verdi (per lo schermo) e pianta della copertura.
    func istantanea() -> (verdi: [SIMD3<Float>], celle: [CellaCopertura]) {
        coda.sync {
            let c = copertura.map { (k, n) in CellaCopertura(i: Int32(truncatingIfNeeded: k >> 32), k: Int32(truncatingIfNeeded: k & 0xFFFF_FFFF), n: n) }
            return (Array(verdi.values), c)
        }
    }

    /// Scrive un file .ply binario con i soli cubetti confermati e non isolati (pulizia dei punti volanti).
    func salvaPLY(in url: URL) throws -> Int {
        try coda.sync {
            func vicino(_ k: Int64) -> Bool {
                guard let c = celle[k] else { return false }
                return c.n >= Nuvola.visteMinime
            }
            let passi: [Int64] = [1 << 42, -(1 << 42), 1 << 21, -(1 << 21), 1, -1]
            var punti: [PuntoColore] = []
            punti.reserveCapacity(celle.count / 2)
            for (k, c) in celle where c.n >= Nuvola.visteMinime {
                // tolgo i cubetti senza nessun vicino confermato: sono rumore o persone che passano
                if !c.maglia && !passi.contains(where: { vicino(k &+ $0) }) { continue }
                let n = Float(c.maglia ? 1 : c.n), nn = UInt32(c.maglia ? 1 : c.n)
                punti.append(PuntoColore(p: SIMD3(c.sx / n, c.sy / n, c.sz / n),
                                         r: UInt8(min(255, c.r / nn)), g: UInt8(min(255, c.g / nn)), b: UInt8(min(255, c.b / nn))))
            }
            var dati = Data()
            let intestazione = """
            ply
            format binary_little_endian 1.0
            comment MARK Rilievi - coordinate in metri, Y verso l'alto. Cubetti visti almeno 2 volte, media delle viste.
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
