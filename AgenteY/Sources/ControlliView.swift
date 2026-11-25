import SwiftUI
import RoomPlan

/// Controlli automatici prima di partire.
struct ControlliView: View {
    let scelta: SceltaRilievo
    let vai: () -> Void
    let annulla: () -> Void

    @State private var batteria: Float = -1
    @State private var inCarica = false
    @State private var spazio: Double = 0

    private var laserOk: Bool { RoomCaptureSession.isSupported }
    private var batteriaOk: Bool { batteria < 0 || batteria >= 0.8 || inCarica }
    private var spazioOk: Bool { spazio >= 2 }
    private var tuttoOk: Bool { laserOk && batteriaOk && spazioOk }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                FumettoTraccia(testo: tuttoOk ? "Tutto pronto. Accendi le luci e apri le porte." : "Controlla qui sotto prima di partire.")
                Pannello {
                    Text("\(scelta.cantiere) · \(scelta.unita)").font(.headline)
                    Text("\(scelta.fase) · \(scelta.tipo.titolo)").foregroundStyle(Tema.testoTenue)
                }
                Pannello {
                    RigaControllo(ok: laserOk, testo: laserOk ? "Laser LiDAR presente" : "Questo telefono non ha il laser LiDAR")
                    RigaControllo(ok: batteriaOk, testo: batteria < 0 ? "Batteria: non leggibile" :
                                    "Batteria \(Int(batteria * 100))%" + (batteriaOk ? "" : " (meglio almeno 80%)"))
                    RigaControllo(ok: spazioOk, testo: String(format: "Spazio libero %.1f GB", spazio) + (spazioOk ? "" : " (servono 2 GB)"))
                    RigaControllo(ok: nil, testo: "Luci accese (al buio accendo io la torcia)")
                    RigaControllo(ok: nil, testo: "Porte aperte tra le stanze")
                    RigaControllo(ok: nil, testo: "Ricordati il punto di partenza: alla fine torna lì")
                    RigaControllo(ok: nil, testo: "Per gli spessori di muri e solai: non fermare il rilievo tra una stanza e l'altra e sulle scale")
                }
                if laserOk {
                    BottoneGrande(titolo: tuttoOk ? "Inizia a camminare" : "Parto lo stesso", icona: "figure.walk",
                                  colore: tuttoOk ? Tema.ok : Tema.casco, azione: vai)
                }
                Button("Annulla", action: annulla).padding(.top, 4)
            }
            .padding(16)
        }
        .background(Tema.sfondo.ignoresSafeArea())
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteria = UIDevice.current.batteryLevel
            inCarica = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            spazio = Archivio.spazioLiberoGB()
        }
    }
}

struct RigaControllo: View {
    let ok: Bool?   // nil = promemoria
    let testo: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ok == nil ? "lightbulb" : (ok! ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.title3)
                .foregroundStyle(ok == nil ? Tema.accento : (ok! ? Tema.ok : Tema.casco))
                .frame(width: 28)
            Text(testo).foregroundStyle(Tema.testo)
        }
    }
}

/// Controlli → rilievo → salvataggio.
struct RilievoFlussoView: View {
    let scelta: SceltaRilievo
    let fine: (RilievoInfo?) -> Void
    @State private var partito = false

    var body: some View {
        if partito {
            RilievoView(scelta: scelta, fine: fine)
        } else {
            ControlliView(scelta: scelta, vai: { partito = true }, annulla: { fine(nil) })
        }
    }
}
