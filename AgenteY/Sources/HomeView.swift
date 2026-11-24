import SwiftUI

struct HomeView: View {
    @EnvironmentObject var archivio: Archivio
    let inizia: (SceltaRilievo) -> Void
    let apri: (RilievoInfo) -> Void
    @State private var mostraNuovo = false
    @State private var mostraImpostazioni = false
    @State private var daEliminare: RilievoInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FumettoTraccia(testo: saluto)

                    BottoneGrande(titolo: "Nuovo rilievo", icona: "camera.viewfinder") { mostraNuovo = true }

                    Pannello {
                        Text("Ultimi rilievi").font(.headline).foregroundStyle(Tema.testo)
                        if archivio.rilievi.isEmpty {
                            Text("Ancora nessun rilievo. Premi \"Nuovo rilievo\" e cammina.")
                                .foregroundStyle(Tema.testoTenue)
                        }
                        ForEach(archivio.rilievi) { r in
                            Button { apri(r) } label: { RigaRilievo(r: r) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { daEliminare = r } label: {
                                        Label("Elimina rilievo", systemImage: "trash")
                                    }
                                }
                            if r.id != archivio.rilievi.last?.id { Divider() }
                        }
                    }

                    Pannello {
                        Text("Cantieri sul telefono").font(.headline).foregroundStyle(Tema.testo)
                        if archivio.cantieri.isEmpty {
                            Text("Li aggiungi quando fai il primo rilievo. Più avanti arriveranno da MARK sulla Wi-Fi.")
                                .foregroundStyle(Tema.testoTenue)
                        }
                        ForEach(archivio.cantieri) { c in
                            HStack {
                                Image(systemName: "building.2").foregroundStyle(Tema.accento)
                                Text(c.nome).foregroundStyle(Tema.testo)
                                Spacer()
                                Text("\(c.unita.count) unità").foregroundStyle(Tema.testoTenue).font(.subheadline)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Tema.sfondo.ignoresSafeArea())
            .navigationTitle("MARK Rilievi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mostraImpostazioni = true } label: { Image(systemName: "gearshape").font(.title3) }
                        .accessibilityLabel("Impostazioni")
                }
            }
            .sheet(isPresented: $mostraNuovo) {
                NuovoRilievoView { s in
                    mostraNuovo = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { inizia(s) }
                }
            }
            .sheet(isPresented: $mostraImpostazioni) { ImpostazioniView() }
            .alert("Eliminare questo rilievo?", isPresented: Binding(get: { daEliminare != nil }, set: { if !$0 { daEliminare = nil } })) {
                Button("Elimina", role: .destructive) { if let r = daEliminare { archivio.elimina(rilievo: r) } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Se non è ancora in MARK, lo perdi.")
            }
        }
    }

    private var saluto: String {
        let attesa = archivio.rilievi.filter { $0.stato == Stato.aspetta }.count
        if attesa == 0 { return "Ciao! Sono Traccia. Andiamo a rilevare?" }
        return attesa == 1 ? "Ho 1 rilievo che aspetta la Wi-Fi di MARK." : "Ho \(attesa) rilievi che aspettano la Wi-Fi di MARK."
    }
}

struct RigaRilievo: View {
    let r: RilievoInfo
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.dashed.inset.filled")
                .font(.title2).foregroundStyle(Tema.accento)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.cantiere) · \(r.unita)").font(.body.weight(.semibold)).foregroundStyle(Tema.testo)
                Text("\(r.fase) · \(r.data.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(Tema.testoTenue)
            }
            Spacer()
            Text(r.stato)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(r.stato == Stato.inMark ? Tema.ok : Tema.casco)
                .background((r.stato == Stato.inMark ? Tema.ok : Tema.casco).opacity(0.12), in: Capsule())
        }
        .contentShape(Rectangle())
    }
}
