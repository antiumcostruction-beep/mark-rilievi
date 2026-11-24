import SwiftUI

@main
struct AgenteYApp: App {
    @StateObject private var archivio = Archivio()
    @StateObject private var collegamento = Collegamento()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            RadiceView()
                .environmentObject(archivio)
                .environmentObject(collegamento)
                .onAppear { collegamento.avvia(archivio: archivio) }
                .onChange(of: fase) { _, f in
                    if f == .active { Task { await collegamento.sincronizza(daSolo: true) } }
                }
                .preferredColorScheme(.light)
                .tint(Tema.accento)
        }
    }
}

/// Decide quale schermata mostrare: Home, rilievo in corso, fine rilievo.
struct RadiceView: View {
    @EnvironmentObject var archivio: Archivio
    @EnvironmentObject var collegamento: Collegamento
    @State private var scelta: SceltaRilievo?
    @State private var finito: RilievoInfo?

    var body: some View {
        HomeView(inizia: { s in scelta = s }, apri: { r in finito = r })
            .fullScreenCover(item: $scelta) { s in
                RilievoFlussoView(scelta: s) { risultato in
                    scelta = nil
                    archivio.ricaricaRilievi()
                    collegamento.inRilievo = false
                    Task { await collegamento.sincronizza(daSolo: true) }
                    if let r = risultato {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finito = r }
                    }
                }
            }
            .onChange(of: scelta) { _, s in if s != nil { collegamento.inRilievo = true } }
            .sheet(item: $finito) { r in
                FineView(rilievo: r)
            }
    }
}
