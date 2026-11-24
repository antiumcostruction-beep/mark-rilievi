import SwiftUI

@main
struct AgenteYApp: App {
    @StateObject private var archivio = Archivio()

    var body: some Scene {
        WindowGroup {
            RadiceView()
                .environmentObject(archivio)
                .preferredColorScheme(.light)
                .tint(Tema.accento)
        }
    }
}

/// Decide quale schermata mostrare: Home, rilievo in corso, fine rilievo.
struct RadiceView: View {
    @EnvironmentObject var archivio: Archivio
    @State private var scelta: SceltaRilievo?
    @State private var finito: RilievoInfo?

    var body: some View {
        HomeView(inizia: { s in scelta = s }, apri: { r in finito = r })
            .fullScreenCover(item: $scelta) { s in
                RilievoFlussoView(scelta: s) { risultato in
                    scelta = nil
                    archivio.ricaricaRilievi()
                    if let r = risultato {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finito = r }
                    }
                }
            }
            .sheet(item: $finito) { r in
                FineView(rilievo: r)
            }
    }
}
