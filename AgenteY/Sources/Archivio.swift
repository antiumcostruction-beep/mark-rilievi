import Foundation
import SwiftUI

/// Tutto quello che l'app salva sul telefono (cartella Documenti, visibile anche nell'app File).
final class Archivio: ObservableObject {
    @Published var cantieri: [Cantiere] = []
    @Published var rilievi: [RilievoInfo] = []

    static var documenti: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var cartellaRilievi: URL { documenti.appendingPathComponent("Rilievi", isDirectory: true) }
    private var fileCantieri: URL { Archivio.documenti.appendingPathComponent("cantieri.json") }

    static let codificatore: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decodificatore: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        try? FileManager.default.createDirectory(at: Archivio.cartellaRilievi, withIntermediateDirectories: true)
        caricaCantieri()
        ricaricaRilievi()
    }

    // MARK: Cantieri

    func caricaCantieri() {
        guard let d = try? Data(contentsOf: fileCantieri),
              let c = try? Archivio.decodificatore.decode([Cantiere].self, from: d) else { return }
        cantieri = c
    }

    func salvaCantieri() {
        if let d = try? Archivio.codificatore.encode(cantieri) { try? d.write(to: fileCantieri, options: .atomic) }
    }

    @discardableResult
    func aggiungiCantiere(_ nome: String) -> Cantiere? {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        if let esiste = cantieri.first(where: { $0.nome.caseInsensitiveCompare(n) == .orderedSame }) { return esiste }
        let c = Cantiere(nome: n)
        cantieri.append(c)
        salvaCantieri()
        return c
    }

    func aggiungiUnita(_ nome: String, a cantiere: Cantiere) {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = cantieri.firstIndex(where: { $0.id == cantiere.id }) else { return }
        if !cantieri[i].unita.contains(n) { cantieri[i].unita.append(n) }
        salvaCantieri()
    }

    func elimina(cantiere: Cantiere) {
        cantieri.removeAll { $0.id == cantiere.id }
        salvaCantieri()
    }

    // MARK: Rilievi

    func ricaricaRilievi() {
        let fm = FileManager.default
        let cartelle = (try? fm.contentsOfDirectory(at: Archivio.cartellaRilievi, includingPropertiesForKeys: nil)) ?? []
        var lista: [RilievoInfo] = []
        for c in cartelle {
            let f = c.appendingPathComponent("rilievo.json")
            if let d = try? Data(contentsOf: f), let r = try? Archivio.decodificatore.decode(RilievoInfo.self, from: d) {
                lista.append(r)
            }
        }
        rilievi = lista.sorted { $0.data > $1.data }
    }

    func cartella(di r: RilievoInfo) -> URL {
        Archivio.cartellaRilievi.appendingPathComponent(r.cartella, isDirectory: true)
    }

    func elimina(rilievo r: RilievoInfo) {
        try? FileManager.default.removeItem(at: cartella(di: r))
        ricaricaRilievi()
    }

    /// Nome cartella: "<data> <cantiere> <unità> <fase>", senza caratteri vietati.
    static func nomeCartella(data: Date, scelta: SceltaRilievo) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let grezzo = "\(f.string(from: data)) \(scelta.cantiere) \(scelta.unita) \(scelta.fase)"
        let vietati = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return grezzo.components(separatedBy: vietati).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Controlli

    static func spazioLiberoGB() -> Double {
        let v = try? documenti.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let b = v?.volumeAvailableCapacityForImportantUsage ?? 0
        return Double(b) / 1_000_000_000
    }
}
