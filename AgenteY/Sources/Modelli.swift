import Foundation

struct Cantiere: Codable, Identifiable, Hashable {
    var id = UUID()
    var nome: String
    var unita: [String] = []
    var markId: String? = nil      // percorso del cantiere in MARK (es. "ANNO 2026/Via Roma 12")
    var inCorso: Bool? = nil
}

enum Fase: String, CaseIterable, Codable, Identifiable {
    case statoDiFatto = "Stato di fatto"
    case impianti = "Impianti"
    case massetto = "Massetto"
    case finito = "Finito"
    case altra = "Altra"
    var id: String { rawValue }
    var icona: String {
        switch self {
        case .statoDiFatto: return "house"
        case .impianti: return "bolt.horizontal"
        case .massetto: return "square.stack.3d.down.forward"
        case .finito: return "checkmark.seal"
        case .altra: return "ellipsis.circle"
        }
    }
}

/// Cosa ha scelto l'utente prima di camminare.
struct SceltaRilievo: Identifiable, Hashable {
    let id = UUID()
    var cantiere: String
    var cantiereId: String? = nil
    var unita: String
    var fase: String
}

/// Una stanza del rilievo, in numeri semplici.
struct StanzaInfo: Codable, Hashable {
    var nome: String
    var superficie: Double      // m², calpestabile
    var altezza: Double         // m, altezza media delle pareti
    var pareti: Int
    var porte: Int
    var finestre: Int
    var aperture: Int
}

/// Contenuto di rilievo.json.
struct RilievoInfo: Codable, Identifiable, Hashable {
    var id: String
    var formato: Int = 1
    var data: Date
    var cantiere: String
    var cantiereId: String? = nil     // cantiere in MARK, se arrivato da MARK
    var unita: String
    var fase: String
    var app: String = "MARK Rilievi"
    var versione: String
    var stato: String                 // "aspetta Wi-Fi" oppure "in MARK"
    var stanze: [StanzaInfo] = []
    var numeroFoto: Int = 0
    var puntiNuvola: Int = 0
    var fonteNuvola: String = ""      // "profondità", "maglia", "nessuna"
    var lunghezzaPercorso: Double = 0 // m
    var durataSecondi: Int = 0
    var impostazioni: [String: String] = [:]
    var segni: [Segno] = []           // finestre/specchi/porte segnati col dito (tappa 2)
    var misure: [Misura] = []         // misure fatte sul telefono (tappa 2)
    var cartella: String              // nome della cartella in Documenti/Rilievi

    var superficieTotale: Double { stanze.reduce(0) { $0 + $1.superficie } }
}

struct Segno: Codable, Hashable {
    var tipo: String
    var x1: Double, z1: Double, x2: Double, z2: Double
}

struct Misura: Codable, Hashable {
    var nome: String
    var metri: Double
}

enum Stato {
    static let aspetta = "aspetta Wi-Fi"
    static let inMark = "in MARK"
}

enum InfoApp {
    static var versione: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
