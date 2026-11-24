import Foundation
import ARKit
import RoomPlan
import AVFoundation
import UIKit
import simd

/// Un tratto da disegnare sulla piccola pianta (coordinate x, z in metri).
struct Tratto {
    enum Tipo { case muro, porta, finestra, apertura }
    var a: CGPoint
    var b: CGPoint
    var tipo: Tipo
}

/// Il cuore del rilievo: RoomPlan (muri, porte, finestre) + laser (nuvola) + foto + percorso.
final class MotoreRilievo: NSObject, ObservableObject, RoomCaptureSessionDelegate {

    enum Fase { case pronto, rilievo, cambioStanza, chiusura, salvataggio, finito }

    // Quello che vede l'utente
    @Published var fase: Fase = .pronto
    @Published var messaggio = "Inquadra un angolo col pavimento"
    @Published var vaBene = true
    @Published var tratti: [Tratto] = []          // stanze già chiuse + stanza attuale
    @Published var percorso: [CGPoint] = []
    @Published var posizione: CGPoint?
    @Published var direzione: Double = 0          // radianti, per la freccia sulla pianta
    @Published var copertura: Double = 0          // 0...1 "Pareti riprese"
    @Published var numeroStanza = 1
    @Published var numeroFoto = 0
    @Published var puntiNuvola = 0
    @Published var torciaAccesa = false
    @Published var errore: String?

    let sessione = RoomCaptureSession()
    let scelta: SceltaRilievo
    private let inizio = Date()
    private let cartella: URL
    private let nomeCartella: String
    private let nuvola: Nuvola
    private let fotografo: Fotografo
    private let voce = AVSpeechSynthesizer()
    private let vibra = UINotificationFeedbackGenerator()

    // impostazioni
    private let qualita: Qualita
    private let distanzaMax: Float
    private let fotoAuto: Bool
    private let fotoMetri: Float
    private let torciaAuto: Bool
    private let guidaVoce: Bool
    private let vibrazione: Bool

    private var timer: Timer?
    private var stanze: [CapturedRoom] = []
    private var trattiChiusi: [Tratto] = []
    private var percorso3D: [[Float]] = []        // t, x, y, z
    private var ultimaPos: SIMD3<Float>?
    private var ultimaFoto: SIMD3<Float>?
    private var lunghezza: Float = 0
    private var settori = Set<Int>()              // 36 settori da 10° per la copertura
    private var tick = 0
    private var buioDa: Date?
    private var ultimoParlato = Date.distantPast
    private var ultimoMessaggio = ""
    private var inizioStanza = Date()
    private var muriVisti = 0
    private var framePerProfondita = 0
    private var stopVoluto = false
    private var finale = false
    private var annullato = false
    private var completamento: ((RilievoInfo?) -> Void)?

    init(scelta: SceltaRilievo) {
        self.scelta = scelta
        let d = UserDefaults.standard
        qualita = Qualita(rawValue: d.string(forKey: Chiave.qualita) ?? "") ?? .normale
        distanzaMax = Float(d.object(forKey: Chiave.distanza) as? Double ?? 5)
        fotoAuto = d.object(forKey: Chiave.fotoAuto) as? Bool ?? true
        fotoMetri = Float(d.object(forKey: Chiave.fotoMetri) as? Double ?? 1)
        torciaAuto = d.object(forKey: Chiave.torcia) as? Bool ?? true
        guidaVoce = d.object(forKey: Chiave.voce) as? Bool ?? true
        vibrazione = d.object(forKey: Chiave.vibrazione) as? Bool ?? true

        nomeCartella = Archivio.nomeCartella(data: inizio, scelta: scelta)
        cartella = Archivio.cartellaRilievi.appendingPathComponent(nomeCartella, isDirectory: true)
        nuvola = Nuvola(lato: qualita.cubetto)
        fotografo = Fotografo(cartella: cartella.appendingPathComponent("foto", isDirectory: true))
        super.init()
        sessione.delegate = self
    }

    // MARK: Comandi

    func avvia() {
        guard fase == .pronto else { return }
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        UIApplication.shared.isIdleTimerDisabled = true
        avviaStanza()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.leggiFrame() }
    }

    private func avviaStanza() {
        var conf = RoomCaptureSession.Configuration()
        conf.isCoachingEnabled = true
        sessione.run(configuration: conf)
        inizioStanza = Date()
        muriVisti = 0
        settori.removeAll()
        copertura = 0
        fase = .rilievo
    }

    /// Chiude la stanza attuale e passa alla prossima, senza fermare il laser.
    func stanzaSuccessiva() {
        guard fase == .rilievo else { return }
        fase = .cambioStanza
        stopVoluto = true
        aggiungiMaglia()
        sessione.stop(pauseARSession: false)
    }

    func scattaFoto() {
        guard let f = sessione.arSession.currentFrame else { return }
        fotografo.scatta(f, manuale: true)
        numeroFoto = fotografo.numero
        if vibrazione { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    func fine(_ completamento: @escaping (RilievoInfo?) -> Void) {
        guard fase == .rilievo || fase == .cambioStanza else { return }
        self.completamento = completamento
        finale = true
        if fase == .cambioStanza { return }   // la stanza si sta già chiudendo: salvo dopo
        fase = .chiusura
        stopVoluto = true
        aggiungiMaglia()
        sessione.stop()
    }

    /// Esce senza salvare (cancella la cartella).
    func annulla() {
        annullato = true
        timer?.invalidate()
        finale = true
        stopVoluto = true
        sessione.stop()
        accendiTorcia(false)
        UIApplication.shared.isIdleTimerDisabled = false
        try? FileManager.default.removeItem(at: cartella)
    }

    // MARK: Lettura continua del laser e della posizione (10 volte al secondo)

    private func leggiFrame() {
        guard fase == .rilievo, let f = sessione.arSession.currentFrame else { return }
        tick += 1
        let T = f.camera.transform
        let pos = SIMD3<Float>(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        let avanti = -SIMD3<Float>(T.columns.2.x, T.columns.2.y, T.columns.2.z)
        let tracciamentoOk: Bool
        if case .normal = f.camera.trackingState { tracciamentoOk = true } else { tracciamentoOk = false }

        // percorso (linea arancione)
        if ultimaPos == nil || simd_distance(ultimaPos!, pos) > 0.05 {
            if let u = ultimaPos { lunghezza += simd_distance(u, pos) }
            ultimaPos = pos
            percorso.append(CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.z)))
            percorso3D.append([Float(Date().timeIntervalSince(inizio)), pos.x, pos.y, pos.z])
        }
        posizione = CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.z))
        direzione = Double(atan2(avanti.x, -avanti.z))

        // copertura: in quali direzioni ho già guardato
        if tracciamentoOk, simd_length(SIMD2(avanti.x, avanti.z)) > 0.3 {
            let ang = atan2(avanti.x, avanti.z) * 180 / .pi + 180
            settori.insert(Int(ang / 10) % 36)
            copertura = Double(settori.count) / 36
        }

        // nuvola di punti (3 volte al secondo)
        if tracciamentoOk, tick % 3 == 0 {
            let punti = LetturaFrame.punti(da: f, passo: qualita.passo, distanzaMax: distanzaMax)
            if !punti.isEmpty { framePerProfondita += 1 }
            nuvola.aggiungi(punti)
            puntiNuvola = nuvola.conteggio
        }

        // foto automatica ogni ~1 m
        if fotoAuto, tracciamentoOk, ultimaFoto == nil || simd_distance(ultimaFoto!, pos) >= fotoMetri {
            ultimaFoto = pos
            fotografo.scatta(f, manuale: false)
            numeroFoto = fotografo.numero
        }

        // torcia al buio
        if torciaAuto, !torciaAccesa, let luce = f.lightEstimate?.ambientIntensity {
            if luce < 250 {
                if buioDa == nil { buioDa = Date() }
                if Date().timeIntervalSince(buioDa!) > 1.5 { accendiTorcia(true) }
            } else { buioDa = nil }
        }

        // consiglio se dopo un po' non vedo ancora muri
        if muriVisti == 0, Date().timeIntervalSince(inizioStanza) > 8, vaBene {
            guida("Inquadra l'angolo col pavimento", ok: false)
        }
    }

    // MARK: RoomPlan

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async { [self] in
            muriVisti = room.walls.count
            tratti = trattiChiusi + MotoreRilievo.tratti(di: room)
        }
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        DispatchQueue.main.async { [self] in
            switch instruction {
            case .normal: guida("Vai bene così", ok: true)
            case .slowDown: guida("Rallenta", ok: false)
            case .turnOnLight: guida("Più luce", ok: false)
            case .moveCloseToWall: guida("Avvicinati al muro", ok: false)
            case .moveAwayFromWall: guida("Allontanati dal muro", ok: false)
            case .lowTexture: guida("Muovi piano, muro liscio", ok: false)
            @unknown default: break
            }
        }
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        let voluto = stopVoluto
        stopVoluto = false
        Task {
            var costruita: CapturedRoom?
            if error == nil || voluto {
                costruita = try? await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
            }
            let stanza = costruita
            await MainActor.run {
                if annullato { return }
                if let s = stanza {
                    stanze.append(s)
                    trattiChiusi += MotoreRilievo.tratti(di: s)
                    tratti = trattiChiusi
                }
                if !voluto {
                    // interrotto (chiamata, app chiusa…): salvo quello che c'è
                    errore = "Il rilievo si è interrotto. Ho salvato quello che avevo."
                    finale = true
                }
                if finale {
                    if !voluto { sessione.stop() }
                    salvaTutto()
                } else {
                    numeroStanza += 1
                    guida("Stanza \(numeroStanza). Cammina piano.", ok: true)
                    avviaStanza()
                }
            }
        }
    }

    // MARK: Guida a schermo, voce, vibrazione

    private func guida(_ testo: String, ok: Bool) {
        guard testo != ultimoMessaggio else { return }
        ultimoMessaggio = testo
        messaggio = testo
        let eraOk = vaBene
        vaBene = ok
        if !ok && eraOk && vibrazione { vibra.notificationOccurred(.warning) }
        if guidaVoce, !ok || testo.hasPrefix("Stanza"), Date().timeIntervalSince(ultimoParlato) > 3.5 {
            ultimoParlato = Date()
            let u = AVSpeechUtterance(string: testo)
            u.voice = AVSpeechSynthesisVoice(language: "it-IT")
            u.rate = 0.5
            voce.stopSpeaking(at: .immediate)
            voce.speak(u)
        }
    }

    private func accendiTorcia(_ on: Bool) {
        guard let dev = AVCaptureDevice.default(for: .video), dev.hasTorch else { return }
        do {
            try dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
            torciaAccesa = on
        } catch {}
    }

    func cambiaTorcia() { accendiTorcia(!torciaAccesa) }

    /// Se il laser non ha dato la profondità, uso la maglia 3D come nuvola.
    private func aggiungiMaglia() {
        guard framePerProfondita < 5, let f = sessione.arSession.currentFrame else { return }
        nuvola.aggiungi(LetturaFrame.puntiMaglia(da: f))
    }

    // MARK: Salvataggio

    private func salvaTutto() {
        fase = .salvataggio
        timer?.invalidate()
        sessione.arSession.pause()
        accendiTorcia(false)
        UIApplication.shared.isIdleTimerDisabled = false
        let stanzeCopia = stanze
        let percorsoCopia = percorso3D
        let durata = Int(Date().timeIntervalSince(inizio))
        let lung = Double(lunghezza)
        let fonte = framePerProfondita >= 5 ? "profondità" : "maglia"

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            fotografo.attendi()
            Thread.sleep(forTimeInterval: 0.3)  // lascia finire gli ultimi punti in coda
            let punti = (try? nuvola.salvaPLY(in: cartella.appendingPathComponent("nuvola.ply"))) ?? 0

            if let d = try? Archivio.codificatore.encode(stanzeCopia) {
                try? d.write(to: cartella.appendingPathComponent("stanze.json"))
            }
            if let d = try? JSONSerialization.data(withJSONObject: ["formato": "t (s), x, y, z (m)", "punti": percorsoCopia]) {
                try? d.write(to: cartella.appendingPathComponent("percorso.json"))
            }

            let info = RilievoInfo(
                id: UUID().uuidString, data: inizio,
                cantiere: scelta.cantiere, unita: scelta.unita, fase: scelta.fase,
                versione: InfoApp.versione, stato: Stato.aspetta,
                stanze: stanzeCopia.enumerated().map { MotoreRilievo.info(stanza: $1, numero: $0 + 1) },
                numeroFoto: fotografo.numero,
                puntiNuvola: punti,
                fonteNuvola: punti == 0 ? "nessuna" : fonte,
                lunghezzaPercorso: lung,
                durataSecondi: durata,
                impostazioni: ["qualita": qualita.rawValue, "distanzaLaser": "\(distanzaMax)", "fotoOgniMetri": "\(fotoMetri)"],
                cartella: nomeCartella)
            if let d = try? Archivio.codificatore.encode(info) {
                try? d.write(to: cartella.appendingPathComponent("rilievo.json"), options: .atomic)
            }
            DispatchQueue.main.async {
                self.fase = .finito
                self.completamento?(info)
            }
        }
    }

    // MARK: Conti sulle stanze

    static func tratti(di room: CapturedRoom) -> [Tratto] {
        func seg(_ t: simd_float4x4, _ larghezza: Float, _ tipo: Tratto.Tipo) -> Tratto {
            let c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let dir = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
            let a = c - dir * larghezza / 2, b = c + dir * larghezza / 2
            return Tratto(a: CGPoint(x: CGFloat(a.x), y: CGFloat(a.z)), b: CGPoint(x: CGFloat(b.x), y: CGFloat(b.z)), tipo: tipo)
        }
        var out = room.walls.map { seg($0.transform, $0.dimensions.x, .muro) }
        out += room.doors.map { seg($0.transform, $0.dimensions.x, .porta) }
        out += room.windows.map { seg($0.transform, $0.dimensions.x, .finestra) }
        out += room.openings.map { seg($0.transform, $0.dimensions.x, .apertura) }
        return out
    }

    static func info(stanza r: CapturedRoom, numero: Int) -> StanzaInfo {
        var area: Double = 0
        for f in r.floors {
            let pc = f.polygonCorners
            if pc.count >= 3 {
                var somma = SIMD3<Float>(0, 0, 0)
                for i in 0..<pc.count { somma += simd_cross(pc[i], pc[(i + 1) % pc.count]) }
                area += Double(simd_length(somma) / 2)
            } else {
                let d = [f.dimensions.x, f.dimensions.y, f.dimensions.z].sorted(by: >)
                area += Double(d[0] * d[1])
            }
        }
        let altezze = r.walls.map { Double($0.dimensions.y) }
        let h = altezze.isEmpty ? 0 : altezze.reduce(0, +) / Double(altezze.count)
        return StanzaInfo(nome: "Stanza \(numero)", superficie: (area * 100).rounded() / 100, altezza: (h * 100).rounded() / 100,
                          pareti: r.walls.count, porte: r.doors.count, finestre: r.windows.count, aperture: r.openings.count)
    }
}
