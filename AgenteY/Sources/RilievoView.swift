import SwiftUI
import ARKit
import SceneKit

/// Schermata leggera durante il rilievo: camera, piccola pianta, guida, tasti grandi.
struct RilievoView: View {
    let scelta: SceltaRilievo
    let fine: (RilievoInfo?) -> Void
    @StateObject private var motore: MotoreRilievo
    @State private var chiediAnnulla = false
    @State private var chiediFine = false

    init(scelta: SceltaRilievo, fine: @escaping (RilievoInfo?) -> Void) {
        self.scelta = scelta
        self.fine = fine
        _motore = StateObject(wrappedValue: MotoreRilievo(scelta: scelta))
    }

    var body: some View {
        ZStack {
            CameraView(sessione: motore.arSessione, verdi: motore.puntiVerdi, versione: motore.versioneVerdi).ignoresSafeArea()

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
                        Etichetta(icona: scelta.tipo.icona, testo: scelta.tipo == .strada ? "Strada / scavo" : "Stanza \(motore.numeroStanza)")
                        Etichetta(icona: "camera", testo: "\(motore.numeroFoto) foto")
                        Etichetta(icona: "circle.grid.3x3", testo: puntiTesto)
                        Etichetta(icona: "checkmark.seal", testo: "Nuvola fitta \(Int(motore.completezza * 100))%")
                    }
                    Spacer()
                    MiniPianta(tratti: motore.tratti, percorso: motore.percorso,
                               posizione: motore.posizione, direzione: motore.direzione,
                               copertura: motore.celleCopertura, soglia: motore.sogliaCella)
                        .frame(width: 150, height: 150)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                }

                // barra pareti riprese (solo stanze)
                if scelta.tipo == .stanze {
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
                }

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
                    if scelta.tipo == .stanze {
                        TastoTondo(icona: "arrow.right.square", testo: "Stanza dopo") { motore.stanzaSuccessiva() }
                            .disabled(motore.fase != .rilievo)
                    }
                }
                if motore.fase == .pronto {
                    BottoneGrande(titolo: "START", icona: "play.circle.fill", colore: Tema.ok) { motore.avvia() }
                    Text("Mettiti nel punto di partenza, inquadra il pavimento e premi START.")
                        .font(.footnote).foregroundStyle(.white).shadow(radius: 2)
                } else {
                    BottoneGrande(titolo: "Fine rilievo", icona: "stop.circle.fill", colore: Tema.rosso) {
                        if motore.completezza < 0.6 && motore.puntiNuvola > 0 { chiediFine = true }
                        else { motore.fine { info in fine(info) } }
                    }
                    .disabled(motore.fase != .rilievo && motore.fase != .cambioStanza && motore.fase != .ripasso)
                }
                if motore.fase != .pronto {
                    Text("Consiglio: finisci tornando al punto di partenza.")
                        .font(.footnote).foregroundStyle(.white).shadow(radius: 2)
                }
            }
            .padding(14)

            if motore.fase == .sceltaRipasso {
                SceltaRipasso(ripassa: { motore.ripassa() }, salva: { motore.salvaSenzaRipasso() })
            }

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
        .onAppear { motore.prepara() }
        .confirmationDialog("Restano zone poco rilevate (in grigio o arancione sulla piantina).", isPresented: $chiediFine, titleVisibility: .visible) {
            Button("Ripasso ancora") {}
            Button("Finisci lo stesso", role: .destructive) { motore.fine { info in fine(info) } }
        }
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

/// Scelta dopo le stanze, se il laser non ha dato la nuvola insieme alla pianta.
struct SceltaRipasso: View {
    let ripassa: () -> Void
    let salva: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                TracciaView(dimensione: 80)
                Text("Pianta fatta!").font(.title2.weight(.bold))
                Text("Per la nuvola nitida, ripassa piano le stanze: muri, porte e finestre restano.")
                    .multilineTextAlignment(.center).foregroundStyle(Tema.testoTenue)
                BottoneGrande(titolo: "Ripassa per la nuvola", icona: "arrow.triangle.2.circlepath", colore: Tema.ok, azione: ripassa)
                Button("Salva così", action: salva).padding(.top, 2)
            }
            .padding(22)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .padding(20)
        }
    }
}

/// Mostra la camera della sessione AR e, sopra, in verde le zone già rilevate bene.
struct CameraView: UIViewRepresentable {
    let sessione: ARSession
    var verdi: [SIMD3<Float>] = []
    var versione: Int = 0

    final class Coordinatore { var versione = -1; let nodo = SCNNode() }
    func makeCoordinator() -> Coordinatore { Coordinatore() }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = sessione
        v.automaticallyUpdatesLighting = false
        v.rendersCameraGrain = false
        v.scene = SCNScene()
        v.scene.rootNode.addChildNode(context.coordinator.nodo)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        let c = context.coordinator
        guard c.versione != versione else { return }
        c.versione = versione
        guard !verdi.isEmpty else { c.nodo.geometry = nil; return }
        let vettori = verdi.map { SCNVector3($0.x, $0.y, $0.z) }
        let sorgente = SCNGeometrySource(vertices: vettori)
        let indici = (0..<Int32(vettori.count)).map { $0 }
        let elemento = SCNGeometryElement(indices: indici, primitiveType: .point)
        elemento.pointSize = 6
        elemento.minimumPointScreenSpaceRadius = 2
        elemento.maximumPointScreenSpaceRadius = 6
        let g = SCNGeometry(sources: [sorgente], elements: [elemento])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.17, green: 0.83, blue: 0.42, alpha: 1)
        m.transparency = 0.55
        m.writesToDepthBuffer = false
        g.materials = [m]
        c.nodo.geometry = g
    }
}
