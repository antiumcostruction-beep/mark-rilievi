import SwiftUI
import RoomPlan

/// Riepilogo a fine rilievo: pianta, superfici, foto, nuvola. Tutto offline.
struct FineView: View {
    @EnvironmentObject var archivio: Archivio
    @Environment(\.dismiss) private var chiudi
    let rilievo: RilievoInfo
    @State private var tratti: [Tratto] = []
    @State private var percorso: [CGPoint] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FumettoTraccia(testo: rilievo.stanze.isEmpty
                                   ? "Ho salvato foto e nuvola. Le stanze non sono venute: riprova con più luce."
                                   : "Rilievo salvato. Lo porto in MARK appena c'è la Wi-Fi dell'ufficio.")
                    Pannello {
                        Text("\(rilievo.cantiere) · \(rilievo.unita)").font(.headline)
                        Text("\(rilievo.fase) · \(rilievo.data.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(Tema.testoTenue)
                        MiniPianta(tratti: tratti, percorso: percorso, spessoreMuro: 4)
                            .frame(height: 260)
                            .background(Tema.sfondo, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Pannello {
                        ForEach(rilievo.stanze, id: \.nome) { s in
                            HStack {
                                Text(s.nome).font(.body.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.2f m²", s.superficie))
                                Text(String(format: "h %.2f m", s.altezza)).foregroundStyle(Tema.testoTenue)
                            }
                        }
                        if !rilievo.stanze.isEmpty {
                            Divider()
                            HStack {
                                Text("Totale calpestabile").font(.headline)
                                Spacer()
                                Text(String(format: "%.2f m²", rilievo.superficieTotale)).font(.headline)
                            }
                        }
                        Text("Le superfici sono di RoomPlan: controllale col metro su un paio di stanze.")
                            .font(.footnote).foregroundStyle(Tema.testoTenue)
                    }
                    Pannello {
                        RigaDato(icona: "camera", testo: "\(rilievo.numeroFoto) foto con profondità")
                        RigaDato(icona: "circle.grid.3x3", testo: "\(rilievo.puntiNuvola) punti nella nuvola (\(rilievo.fonteNuvola))")
                        RigaDato(icona: "figure.walk", testo: String(format: "%.0f m camminati in %d min", rilievo.lunghezzaPercorso, max(1, rilievo.durataSecondi / 60)))
                        RigaDato(icona: "wifi", testo: "Stato: \(rilievo.stato)")
                    }
                    Text("Misure sulla pianta e sulle foto, segni di specchi e finestre e nuvola 3D arrivano con la Tappa 2.")
                        .font(.footnote).foregroundStyle(Tema.testoTenue).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background(Tema.sfondo.ignoresSafeArea())
            .navigationTitle("Rilievo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { chiudi() } } }
            .onAppear(perform: carica)
        }
    }

    private func carica() {
        let c = archivio.cartella(di: rilievo)
        if let d = try? Data(contentsOf: c.appendingPathComponent("stanze.json")),
           let stanze = try? Archivio.decodificatore.decode([CapturedRoom].self, from: d) {
            tratti = stanze.flatMap { MotoreRilievo.tratti(di: $0) }
        }
        if let d = try? Data(contentsOf: c.appendingPathComponent("percorso.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let p = j["punti"] as? [[Double]] {
            percorso = p.compactMap { $0.count >= 4 ? CGPoint(x: $0[1], y: $0[3]) : nil }
        }
    }
}

struct RigaDato: View {
    let icona: String
    let testo: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icona).foregroundStyle(Tema.accento).frame(width: 26)
            Text(testo).foregroundStyle(Tema.testo)
        }
    }
}
