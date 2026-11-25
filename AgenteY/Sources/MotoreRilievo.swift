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

    enum Fase { case pronto, rilievo, cambioStanza, chiusura, sceltaRipasso, ripasso, salvataggio, finito }

    // Quello che vede l'utente
    @Published var fase: Fase = .pronto
    @Published var messaggio = "Mettiti nel punto di partenza e premi START"
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
    @Published var celleCopertura: [CellaCopertura] = []   // pianta della copertura (25 cm)
    @Published var puntiVerdi: [SIMD3<Float>] = []         // zone già rilevate, mostrate sulla fotocamera
    @Published var versioneVerdi = 0
    @Published var completezza: Double = 0                 // 0...1 "Nuvola fitta"

    /// Sessione ARKit nostra (con profondità del laser e maglia 3D), passata a RoomPlan.
    let arSessione = ARSession()
    let sessione: RoomCaptureSession
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
    private var frameLetti = 0
    private var maglieViste = 0
    private var arAvviata = false
    private var profonditaForzata = false       // provato a riaccendere il laser insieme a RoomPlan
    private var momentoForzatura = Date.distantPast
    private var nonForzare = false
    private var ripassoFatto = false
    private var ultimaPosVel: (SIMD3<Float>, Double, Date)?
    private let strada: Bool
    var sogliaCella: Int { max(6, Int(Nuvola.lato2D * Nuvola.lato2D / (qualita.cubetto * qualita.cubetto) * 0.25)) }
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

        strada = scelta.tipo == .strada
        nomeCartella = Archivio.nomeCartella(data: inizio, scelta: scelta)
        cartella = Archivio.cartellaRilievi.appendingPathComponent(nomeCartella, isDirectory: true)
        nuvola = Nuvola(lato: qualita.cubetto)
        fotografo = Fotografo(cartella: cartella.appendingPathComponent("foto", isDirectory: true))
        sessione = RoomCaptureSession(arSession: arSessione)
        super.init()
        sessione.delegate = self
    }

    // MARK: Comandi

    /// Apre la fotocamera e il laser, ma non registra ancora: aspetta START.
    func prepara() {
        guard !arAvviata else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        accendiLaser()
    }

    private func accendiLaser() {
        let c = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { c.frameSemantics.insert(.sceneDepth) }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }
        arSessione.run(c)
        arAvviata = true
    }

    /// Tasto START: da qui si registra.
    func avvia() {
        guard fase == .pronto else { return }
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        UIApplication.shared.isIdleTimerDisabled = true
        if vibrazione { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        avviaStanza()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.leggiFrame() }
    }

    private func avviaStanza() {
        if !arAvviata { accendiLaser() }
        if strada {
            // Strada / scavo: niente RoomPlan, così la profondità del laser resta accesa
            inizioStanza = Date()
            fase = .rilievo
            guida("Cammina piano, telefono verso terra", ok: true)
            return
        }
        var conf = RoomCaptureSession.Configuration()
        conf.isCoachingEnabled = true
        sessione.run(configuration: conf)
        inizioStanza = Date()
        muriVisti = 0
        settori.removeAll()
        copertura = 0
        fase = .rilievo
        // RoomPlan spegne la profondità del laser: provo a riaccenderla una volta, poco dopo la partenza
        if !nonForzare && !profonditaForzata {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.riaccendiProfondita() }
        }
    }

    private func riaccendiProfondita() {
        guard fase == .rilievo, !strada, !nonForzare, !profonditaForzata, framePerProfondita == 0,
              let c = arSessione.configuration as? ARWorldTrackingConfiguration,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { return }
        c.frameSemantics.insert(.sceneDepth)
        profonditaForzata = true
        momentoForzatura = Date()
        arSessione.run(c)
    }

    /// Ripasso per la nuvola dopo le stanze (se il laser non ha dato la profondità insieme a RoomPlan).
    func ripassa() {
        guard fase == .sceltaRipasso else { return }
        ripassoFatto = true
        let c = ARWorldTrackingConfiguration()
        c.frameSemantics.insert(.sceneDepth)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }
        arSessione.run(c)   // senza azzerare: la nuvola resta allineata alla pianta
        fase = .ripasso
        if timer == nil || !(timer!.isValid) {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.leggiFrame() }
        }
        guida("Ripassa piano le stanze: ora registro la nuvola", ok: true)
    }

    func salvaSenzaRipasso() {
        guard fase == .sceltaRipasso else { return }
        salvaTutto()
    }

    /// Chiude la stanza attuale e passa alla prossima, senza fermare il laser.
    func stanzaSuccessiva() {
        guard fase == .rilievo, !strada else { return }
        fase = .cambioStanza
        stopVoluto = true
        aggiungiMaglia()
        sessione.stop(pauseARSession: false)
    }

    func scattaFoto() {
        guard let f = arSessione.currentFrame else { return }
        fotografo.scatta(f, manuale: true)
        numeroFoto = fotografo.numero
        if vibrazione { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    func fine(_ completamento: @escaping (RilievoInfo?) -> Void) {
        guard fase == .rilievo || fase == .cambioStanza || fase == .ripasso else { return }
        self.completamento = completamento
        finale = true
        if fase == .ripasso { fase = .chiusura; salvaTutto(); return }
        if fase == .cambioStanza { return }   // la stanza si sta già chiudendo: salvo dopo
        if strada { fase = .chiusura; aggiungiMaglia(); salvaTutto(); return }
        fase = .chiusura
        stopVoluto = true
        aggiungiMaglia()
        // se il laser non ha dato la nuvola, tengo acceso il sensore per l'eventuale ripasso
        sessione.stop(pauseARSession: framePerProfondita >= 5)
    }

    /// Esce senza salvare (cancella la cartella).
    func annulla() {
        annullato = true
        timer?.invalidate()
        finale = true
        stopVoluto = true
        if strada || fase == .ripasso || fase == .sceltaRipasso { arSessione.pause() } else { sessione.stop() }
        accendiTorcia(false)
        UIApplication.shared.isIdleTimerDisabled = false
        try? FileManager.default.removeItem(at: cartella)
    }

    // MARK: Lettura continua del laser e della posizione (10 volte al secondo)

    private func leggiFrame() {
        guard fase == .rilievo || fase == .ripasso, let f = arSessione.currentFrame else { return }
        let soloLaser = strada || fase == .ripasso
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
            frameLetti += 1
            let punti = LetturaFrame.punti(da: f, passo: qualita.passo, distanzaMax: distanzaMax)
            if !punti.isEmpty { framePerProfondita += 1 }
            nuvola.aggiungi(punti)
            puntiNuvola = nuvola.conteggio
        }

        // ripiego ogni 3 s: se la profondità non arriva, prendo i punti della maglia 3D
        if tick % 30 == 0 {
            let n = f.anchors.reduce(0) { $0 + ($1 is ARMeshAnchor ? 1 : 0) }
            maglieViste = max(maglieViste, n)
            if framePerProfondita < 5, n > 0 {
                // solo i punti della maglia che la fotocamera vede adesso, col loro colore vero
                nuvola.aggiungiMaglia(LetturaFrame.puntiMagliaColorati(da: f, distanzaMax: distanzaMax))
                puntiNuvola = nuvola.conteggio
            }
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

        // guida della nuvola, una volta al secondo
        if tick % 10 == 0 { guidaNuvola(frame: f, pos: pos, avanti: avanti, tracciamentoOk: tracciamentoOk, soloLaser: soloLaser) }
        if soloLaser { return }

        // consiglio se dopo un po' non vedo ancora muri
        if muriVisti == 0, Date().timeIntervalSince(inizioStanza) > 8, vaBene {
            guida("Inquadra l'angolo col pavimento", ok: false)
        }
    }

    // MARK: Guida della nuvola (dove ripassare)

    private func guidaNuvola(frame f: ARFrame, pos: SIMD3<Float>, avanti: SIMD3<Float>, tracciamentoOk: Bool, soloLaser: Bool) {
        // velocità di cammino e di rotazione
        let ora = Date()
        let yaw = Double(atan2(avanti.x, -avanti.z))
        var troppoVeloce = false, giraVeloce = false
        if let u = ultimaPosVel {
            let (p0, y0, t0) = u
            let dt = ora.timeIntervalSince(t0)
            if dt > 0 {
                troppoVeloce = Double(simd_distance(p0, pos)) / dt > 0.8
                var dy = abs(yaw - y0); if dy > .pi { dy = 2 * .pi - dy }
                giraVeloce = dy / dt > 1.2
            }
        }
        ultimaPosVel = (pos, yaw, ora)
        // distanza al centro dell'inquadratura
        var lontano = false
        if let sd = f.sceneDepth ?? f.smoothedSceneDepth {
            let d = sd.depthMap
            CVPixelBufferLockBaseAddress(d, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(d) {
                let w = CVPixelBufferGetWidth(d), h = CVPixelBufferGetHeight(d), riga = CVPixelBufferGetBytesPerRow(d)
                let v = base.advanced(by: (h / 2) * riga).assumingMemoryBound(to: Float32.self)[w / 2]
                lontano = v > distanzaMax
            }
            CVPixelBufferUnlockBaseAddress(d, .readOnly)
        }
        // fotografia della nuvola, poi la pianta della copertura e i buchi vicini
        let snap = nuvola.istantanea()
        puntiVerdi = snap.verdi
        versioneVerdi += 1
        celleCopertura = snap.celle
        let soglia = sogliaCella
        let mappa = Dictionary(uniqueKeysWithValues: snap.celle.map { (Int64($0.i) << 32 | Int64(UInt32(bitPattern: $0.k)), $0.n) })
        let fitte = snap.celle.filter { $0.n >= soglia }.count
        completezza = snap.celle.isEmpty ? 0 : Double(fitte) / Double(snap.celle.count)
        // buco = cella vicina (entro 3 m) poco fitta, o vuota ma circondata da celle rilevate
        let ci = Int32((pos.x / Nuvola.lato2D).rounded(.down)), ck = Int32((pos.z / Nuvola.lato2D).rounded(.down))
        var buco: (Float, Float)? = nil, distMin: Float = .infinity
        for di in Int32(-12)...12 { for dk in Int32(-12)...12 {
            let i = ci + di, k = ck + dk
            let n = mappa[Int64(i) << 32 | Int64(UInt32(bitPattern: k))] ?? 0
            if n >= soglia { continue }
            if n == 0 {
                var vicini = 0
                for (a, b) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where (mappa[Int64(i + Int32(a)) << 32 | Int64(UInt32(bitPattern: k + Int32(b)))] ?? 0) >= soglia { vicini += 1 }
                if vicini < 3 { continue }
            }
            let x = (Float(i) + 0.5) * Nuvola.lato2D - pos.x, z = (Float(k) + 0.5) * Nuvola.lato2D - pos.z
            let d = (x * x + z * z).squareRoot()
            if d > 0.6 && d < 3 && d < distMin { distMin = d; buco = (x, z) }
        } }
        if !tracciamentoOk { guida("Muoviti più piano", ok: false); return }
        if troppoVeloce { guida("Rallenta", ok: false); return }
        if giraVeloce { guida("Gira più piano", ok: false); return }
        if lontano { guida("Troppo lontano, avvicinati", ok: false); return }
        if let bb = buco, Date().timeIntervalSince(inizioStanza) > 6 {
            let (bx, bz) = bb
            // direzione del buco rispetto a dove guardo
            let f2 = SIMD2<Float>(avanti.x, avanti.z), b2 = SIMD2<Float>(bx, bz)
            let lf = simd_length(f2), lb = simd_length(b2)
            if lf > 0.2 {
                let cosA = simd_dot(f2, b2) / (lf * lb)
                let croce = f2.x * b2.y - f2.y * b2.x       // > 0 = a destra (asse z verso di me)
                let dove = cosA > 0.7 ? "davanti" : (cosA < -0.5 ? "dietro di te" : (croce > 0 ? "a destra" : "a sinistra"))
                guida("Manca un pezzo \(dove): ripassa lì", ok: true)
                return
            }
        }
        if soloLaser { guida(completezza > 0.8 ? "Ottimo, nuvola fitta" : "Cammina piano, telefono verso le superfici", ok: true) }
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
                // RoomPlan si è fermato subito dopo aver riacceso la profondità: niente forzatura, riparto la stanza
                if !voluto && profonditaForzata && Date().timeIntervalSince(momentoForzatura) < 10 && !finale {
                    nonForzare = true
                    profonditaForzata = false
                    accendiLaser()
                    avviaStanza()
                    return
                }
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
                    if voluto && framePerProfondita < 5 && !ripassoFatto && !strada {
                        fase = .sceltaRipasso   // chiedo se ripassare per la nuvola nitida
                        guida("Pianta fatta. Ripassi per la nuvola?", ok: true)
                        return
                    }
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
        guard framePerProfondita < 5, let f = arSessione.currentFrame else { return }
        nuvola.aggiungiMaglia(LetturaFrame.puntiMaglia(da: f))
    }

    // MARK: Salvataggio

    private func salvaTutto() {
        fase = .salvataggio
        timer?.invalidate()
        arSessione.pause()
        accendiTorcia(false)
        UIApplication.shared.isIdleTimerDisabled = false
        let stanzeCopia = stanze
        let percorsoCopia = percorso3D
        let durata = Int(Date().timeIntervalSince(inizio))
        let lung = Double(lunghezza)
        let fonte = framePerProfondita >= 5 ? "profondità" : "maglia"
        let diagnosi = ["frameLetti": "\(frameLetti)", "frameConProfondita": "\(framePerProfondita)", "maglie3D": "\(maglieViste)", "profonditaRiaccesa": profonditaForzata ? "si" : (nonForzare ? "rifiutata da RoomPlan" : "no"), "ripasso": ripassoFatto ? "si" : "no", "completezza": "\(Int(completezza * 100))"]
        let piantaTratti = trattiChiusi.map { t -> [String: Any] in
            let tipo: String
            switch t.tipo { case .muro: tipo = "muro"; case .porta: tipo = "porta"; case .finestra: tipo = "finestra"; case .apertura: tipo = "apertura" }
            return ["a": [Double(t.a.x), Double(t.a.y)], "b": [Double(t.b.x), Double(t.b.y)], "tipo": tipo]
        }

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
            // pianta semplice per lo Studio Rilievi in MARK (x, z in metri, vista dall'alto)
            let piantaPercorso = percorsoCopia.map { [Double($0[1]), Double($0[3])] }
            if let d = try? JSONSerialization.data(withJSONObject: ["formato": 1, "tratti": piantaTratti, "percorso": piantaPercorso]) {
                try? d.write(to: cartella.appendingPathComponent("pianta.json"))
            }

            let info = RilievoInfo(
                id: UUID().uuidString, data: inizio,
                cantiere: scelta.cantiere, cantiereId: scelta.cantiereId, unita: scelta.unita, fase: scelta.fase, tipo: scelta.tipo.rawValue,
                versione: InfoApp.versione, stato: Stato.aspetta,
                stanze: stanzeCopia.enumerated().map { MotoreRilievo.info(stanza: $1, numero: $0 + 1) },
                numeroFoto: fotografo.numero,
                puntiNuvola: punti,
                fonteNuvola: punti == 0 ? "nessuna" : fonte,
                lunghezzaPercorso: lung,
                durataSecondi: durata,
                impostazioni: ["qualita": qualita.rawValue, "distanzaLaser": "\(distanzaMax)", "fotoOgniMetri": "\(fotoMetri)"].merging(diagnosi) { a, _ in a },
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
