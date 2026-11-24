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

    /// Cantieri arrivati da MARK: aggiorna quelli che ci sono, aggiunge i nuovi, tiene quelli creati sul telefono.
    func aggiornaDaMark(_ lista: [[String: Any]]) {
        for c in lista {
            guard let id = c["id"] as? String, let nome = c["nome"] as? String else { continue }
            let unita = (c["unita"] as? [String]) ?? []
            let inCorso = c["inCorso"] as? Bool
            if let i = cantieri.firstIndex(where: { $0.markId == id })
                ?? cantieri.firstIndex(where: { $0.markId == nil && $0.nome.caseInsensitiveCompare(nome) == .orderedSame }) {
                cantieri[i].markId = id
                cantieri[i].nome = nome
                cantieri[i].inCorso = inCorso
                for u in unita where !cantieri[i].unita.contains(u) { cantieri[i].unita.append(u) }
            } else {
                cantieri.append(Cantiere(nome: nome, unita: unita, markId: id, inCorso: inCorso))
            }
        }
        // prima i cantieri in corso, poi gli altri
        cantieri.sort { (($0.inCorso ?? true) ? 0 : 1, $0.nome.lowercased()) < (($1.inCorso ?? true) ? 0 : 1, $1.nome.lowercased()) }
        salvaCantieri()
    }

    // MARK: Rilievi

    /// Segna il rilievo "in MARK" (scritto anche nel suo rilievo.json).
    func segnaInMark(_ r: RilievoInfo) {
        var n = r
        n.stato = Stato.inMark
        if let d = try? Archivio.codificatore.encode(n) {
            try? d.write(to: cartella(di: r).appendingPathComponent("rilievo.json"), options: .atomic)
        }
        ricaricaRilievi()
    }

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
