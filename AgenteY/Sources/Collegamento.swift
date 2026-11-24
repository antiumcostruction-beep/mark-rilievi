import Foundation
import UIKit
import Darwin

/// Parla con MARK sul PC dell'ufficio (Wi-Fi), sulla porta dei rilievi.
/// 1) trova MARK  2) abbinamento col codice di 6 cifre  3) prende i cantieri  4) manda i rilievi.
@MainActor
final class Collegamento: ObservableObject {
    nonisolated static let porta = 3017

    @Published var stato = "Non ancora collegato a MARK"
    @Published var lavora = false
    @Published var abbinato = UserDefaults.standard.string(forKey: Chiave.gettone) != nil
    @Published var trovatoIn: String? = UserDefaults.standard.string(forKey: Chiave.ultimoIndirizzo)

    private var timer: Timer?
    weak var archivio: Archivio?
    var inRilievo = false   // durante il rilievo non si manda niente

    private var gettone: String? {
        get { UserDefaults.standard.string(forKey: Chiave.gettone) }
        set { UserDefaults.standard.set(newValue, forKey: Chiave.gettone); abbinato = newValue != nil }
    }

    func avvia(archivio: Archivio) {
        self.archivio = archivio
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sincronizza(daSolo: true) }
        }
        Task { await sincronizza(daSolo: true) }
    }

    // MARK: Trovare MARK

    private func base(_ ind: String) -> String {
        var s = ind.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        // se manca la porta, metto quella dei rilievi
        if let u = URL(string: s), u.port == nil, u.scheme == "http" { s += ":\(Collegamento.porta)" }
        return s
    }

    nonisolated static func ciao(_ b: String, attesa: TimeInterval) async -> Bool {
        guard let u = URL(string: b + "/api/telefono/ciao") else { return false }
        var r = URLRequest(url: u, timeoutInterval: attesa)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return j["mark"] as? Bool == true
    }

    /// Cerca MARK: indirizzo scritto a mano, poi l'ultimo che ha funzionato, poi tutta la Wi-Fi (x.x.x.1-254).
    func trova() async -> String? {
        let manuale = UserDefaults.standard.string(forKey: Chiave.indirizzoMark) ?? ""
        if !manuale.isEmpty {
            let b = base(manuale)
            return await Collegamento.ciao(b, attesa: 4) ? b : nil
        }
        if let u = trovatoIn, await Collegamento.ciao(u, attesa: 2) { return u }
        guard let mio = Collegamento.indirizzoWiFi() else { return nil }
        let parti = mio.split(separator: ".")
        guard parti.count == 4 else { return nil }
        let prefisso = parti[0...2].joined(separator: ".")
        stato = "Cerco MARK sulla Wi-Fi…"
        let indirizzi = (1...254).map { "\(prefisso).\($0)" }.filter { $0 != mio }
        let trovato: String? = await withTaskGroup(of: String?.self) { g in
            var resto = indirizzi[...]
            for _ in 0..<40 {
                guard let ip = resto.popFirst() else { break }
                g.addTask { await Collegamento.ciao("http://\(ip):\(Collegamento.porta)", attesa: 1.5) ? "http://\(ip):\(Collegamento.porta)" : nil }
            }
            while let r = await g.next() {
                if let r { g.cancelAll(); return r }
                if let ip = resto.popFirst() {
                    g.addTask { await Collegamento.ciao("http://\(ip):\(Collegamento.porta)", attesa: 1.5) ? "http://\(ip):\(Collegamento.porta)" : nil }
                }
            }
            return nil
        }
        if let t = trovato {
            trovatoIn = t
            UserDefaults.standard.set(t, forKey: Chiave.ultimoIndirizzo)
        }
        return trovato
    }

    /// Indirizzo del telefono sulla Wi-Fi (interfaccia en0).
    static func indirizzoWiFi() -> String? {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primo = lista else { return nil }
        defer { freeifaddrs(lista) }
        var p: UnsafeMutablePointer<ifaddrs>? = primo
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: a.pointee.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    // MARK: Abbinamento

    func abbina(codice: String) async -> String? {
        lavora = true
        defer { lavora = false }
        stato = "Cerco MARK…"
        guard let b = await trova() else {
            stato = "Non trovo MARK"
            return "Non trovo MARK sulla Wi-Fi. Controlla che il telefono sia sulla Wi-Fi dell'ufficio e che MARK sia acceso sul PC."
        }
        var r = URLRequest(url: URL(string: b + "/api/telefono/abbina")!, timeoutInterval: 10)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["codice": codice, "telefono": UIDevice.current.name])
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return "MARK non risponde. Riprova." }
        let j = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
        if (resp as? HTTPURLResponse)?.statusCode == 200, let g = j["gettone"] as? String {
            gettone = g
            stato = "Abbinato a MARK"
            Task { await sincronizza(daSolo: false) }
            return nil
        }
        return j["error"] as? String ?? "Abbinamento non riuscito."
    }

    func dimentica() {
        gettone = nil
        stato = "Non abbinato"
    }

    // MARK: Scambio

    private func richiesta(_ b: String, _ percorso: String, metodo: String = "GET", attesa: TimeInterval = 15) -> URLRequest {
        var r = URLRequest(url: URL(string: b + "/api/telefono" + percorso)!, timeoutInterval: attesa)
        r.httpMethod = metodo
        r.setValue(gettone, forHTTPHeaderField: "X-Mark-Gettone")
        return r
    }

    private func controlla(_ resp: URLResponse?) throws {
        let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if c == 401 { gettone = nil; throw Errore.nonAbbinato }
        if c != 200 { throw Errore.mark(c) }
    }

    enum Errore: Error { case nonAbbinato, mark(Int) }

    /// Prende i cantieri e manda i rilievi che aspettano. daSolo = chiamata dal timer (non disturba se non trova).
    func sincronizza(daSolo: Bool) async {
        guard !lavora, !inRilievo, let archivio else { return }
        guard gettone != nil else { stato = "Da abbinare a MARK (Impostazioni)"; return }
        if daSolo, UserDefaults.standard.object(forKey: Chiave.invioAuto) as? Bool == false { return }
        lavora = true
        defer { lavora = false }
        guard let b = await trova() else {
            stato = archivio.rilievi.contains { $0.stato == Stato.aspetta } ? "MARK non è qui: aspetto la Wi-Fi dell'ufficio" : "MARK non è sulla rete"
            return
        }
        do {
            // cantieri
            let (d, resp) = try await URLSession.shared.data(for: richiesta(b, "/cantieri"))
            try controlla(resp)
            if let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let l = j["cantieri"] as? [[String: Any]] {
                archivio.aggiornaDaMark(l)
            }
            // rilievi
            let daMandare = archivio.rilievi.filter { $0.stato == Stato.aspetta }
            var mandati = 0
            for r in daMandare {
                stato = "Mando a MARK: \(r.cantiere) · \(r.unita)…"
                try await manda(r, a: b)
                archivio.segnaInMark(r)
                mandati += 1
            }
            stato = mandati == 0 ? "Collegato a MARK · tutto mandato"
                : (mandati == 1 ? "Mandato 1 rilievo a MARK" : "Mandati \(mandati) rilievi a MARK")
            if mandati > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        } catch Errore.nonAbbinato {
            stato = "MARK non riconosce più il telefono: abbinalo di nuovo (Impostazioni)"
        } catch {
            stato = "Invio interrotto, riprovo tra poco"
        }
    }

    private func manda(_ r: RilievoInfo, a b: String) async throws {
        guard let archivio else { return }
        let cartella = archivio.cartella(di: r)
        // già arrivato? (es. connessione caduta dopo la fine)
        let (ds, rs) = try await URLSession.shared.data(for: richiesta(b, "/rilievo/\(r.id)/stato"))
        try controlla(rs)
        if let j = try? JSONSerialization.jsonObject(with: ds) as? [String: Any], j["ricevuto"] as? Bool == true { return }

        let file = Collegamento.elencoFile(in: cartella)
        for rel in file {
            var q = URLComponents()
            q.queryItems = [URLQueryItem(name: "nome", value: rel)]
            var req = richiesta(b, "/rilievo/\(r.id)/file" + (q.percentEncodedQuery.map { "?" + $0 } ?? ""), metodo: "POST", attesa: 120)
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.upload(for: req, fromFile: cartella.appendingPathComponent(rel))
            try controlla(resp)
        }
        var fine = richiesta(b, "/rilievo/\(r.id)/fine", metodo: "POST", attesa: 60)
        fine.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fine.httpBody = try JSONSerialization.data(withJSONObject: ["file": file])
        let (_, rf) = try await URLSession.shared.data(for: fine)
        try controlla(rf)
    }

    /// Tutti i file della cartella del rilievo, con il percorso relativo (es. "foto/001.jpg").
    static func elencoFile(in cartella: URL) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: cartella, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let radice = cartella.standardizedFileURL.path
        var out: [String] = []
        for case let u as URL in en {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            var rel = u.standardizedFileURL.path
            if rel.hasPrefix(radice) { rel.removeFirst(radice.count) }
            while rel.hasPrefix("/") { rel.removeFirst() }
            if !rel.isEmpty { out.append(rel) }
        }
        // rilievo.json per ultimo
        return out.sorted { ($0 == "rilievo.json" ? 1 : 0, $0) < ($1 == "rilievo.json" ? 1 : 0, $1) }
    }
}
