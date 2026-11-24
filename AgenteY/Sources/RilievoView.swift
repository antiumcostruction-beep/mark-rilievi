import SwiftUI
import ARKit

/// Schermata leggera durante il rilievo: camera, piccola pianta, guida, tasti grandi.
struct RilievoView: View {
    let scelta: SceltaRilievo
    let fine: (RilievoInfo?) -> Void
    @StateObject private var motore: MotoreRilievo
    @State private var chiediAnnulla = false

    init(scelta: SceltaRilievo, fine: @escaping (RilievoInfo?) -> Void) {
        self.scelta = scelta
        self.fine = fine
        _motore = StateObject(wrappedValue: MotoreRilievo(scelta: scelta))
    }

    var body: some View {
        ZStack {
            CameraView(sessione: motore.sessione.arSession).ignoresSafeArea()

            VStack(spacing: 10) {
                // guida in alto
                HStack(spacing: 10) {
                    Image(systemName: motore.vaBene ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(motore.messaggio).font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(motore.vaBene ? Tema.ok : Tema.casco, in: RoundedRectangle(cornerRadius: 14))

                HStack(alignment: .top) {
                    // contatori
                    VStack(alignment: .leading, spacing: 6) {
                        Etichetta(icona: "square.split.bottomrightquarter", testo: "Stanza \(motore.numeroStanza)")
                        Etichetta(icona: "camera", testo: "\(motore.numeroFoto) foto")
                        Etichetta(icona: "circle.grid.3x3", testo: puntiTesto)
                    }
                    Spacer()
                    MiniPianta(tratti: motore.tratti, percorso: motore.percorso,
                               posizione: motore.posizione, direzione: motore.direzione)
                        .frame(width: 150, height: 150)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                }

                // barra pareti riprese
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pareti riprese \(Int(motore.copertura * 100))%")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(Tema.laser).frame(width: g.size.width * motore.copertura)
                        }
                    }
                    .frame(height: 10)
                }
                .padding(10)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                if let e = motore.errore {
                    Text(e).foregroundStyle(.white).padding(10)
                        .background(Tema.rosso, in: RoundedRectangle(cornerRadius: 12))
                }

                // tasti in basso
                HStack(spacing: 10) {
                    TastoTondo(icona: "camera.fill", testo: "Foto") { motore.scattaFoto() }
                    TastoTondo(icona: motore.torciaAccesa ? "flashlight.on.fill" : "flashlight.off.fill", testo: "Torcia") {
                        motore.cambiaTorcia()
                    }
                    TastoTondo(icona: "arrow.right.square", testo: "Stanza dopo") { motore.stanzaSuccessiva() }
                        .disabled(motore.fase != .rilievo)
                }
                BottoneGrande(titolo: "Fine rilievo", icona: "stop.circle.fill", colore: Tema.rosso) {
                    motore.fine { info in fine(info) }
                }
                .disabled(motore.fase != .rilievo && motore.fase != .cambioStanza)
                Text("Consiglio: finisci tornando al punto di partenza.")
                    .font(.footnote).foregroundStyle(.white).shadow(radius: 2)
            }
            .padding(14)

            if motore.fase == .chiusura || motore.fase == .salvataggio || motore.fase == .cambioStanza {
                Attesa(testo: motore.fase == .cambioStanza ? "Chiudo la stanza…" : "Salvo il rilievo sul telefono…")
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { chiediAnnulla = true } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .padding(10).background(.black.opacity(0.4), in: Circle())
            }
            .padding(.trailing, 14).padding(.top, 2)
            .opacity(0) // nascosto: si annulla con il tasto qui sotto per evitare tocchi per sbaglio
        }
        .onAppear { motore.avvia() }
        .statusBarHidden()
    }

    private var puntiTesto: String {
        let n = motore.puntiNuvola
        return n >= 1000 ? "\(n / 1000)k punti" : "\(n) punti"
    }
}

struct Etichetta: View {
    let icona: String
    let testo: String
    var body: some View {
        Label(testo, systemImage: icona)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.4), in: Capsule())
    }
}

struct TastoTondo: View {
    let icona: String
    let testo: String
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            VStack(spacing: 4) {
                Image(systemName: icona).font(.title2)
                Text(testo).font(.caption.weight(.semibold))
            }
            .foregroundStyle(Tema.testo)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct Attesa: View {
    let testo: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                TracciaView(dimensione: 90)
                ProgressView()
                Text(testo).font(.headline)
            }
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

/// Mostra la camera della sessione AR, senza 3D pesante sopra.
struct CameraView: UIViewRepresentable {
    let sessione: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = sessione
        v.automaticallyUpdatesLighting = false
        v.rendersCameraGrain = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
