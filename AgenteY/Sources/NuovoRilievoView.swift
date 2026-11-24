import SwiftUI

/// Tre tocchi: cantiere → unità → fase.
struct NuovoRilievoView: View {
    @EnvironmentObject var archivio: Archivio
    @Environment(\.dismiss) private var chiudi
    let parti: (SceltaRilievo) -> Void

    @State private var passo = 0
    @State private var cantiere: Cantiere?
    @State private var unita: String?
    @State private var nuovoNome = ""
    @State private var chiediNome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Indicatore(passo: passo)
                    switch passo {
                    case 0: sceltaCantiere
                    case 1: sceltaUnita
                    default: sceltaFase
                    }
                }
                .padding(16)
            }
            .background(Tema.sfondo.ignoresSafeArea())
            .navigationTitle(["Quale cantiere?", "Quale unità?", "Quale fase?"][min(passo, 2)])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if passo == 0 { Button("Annulla") { chiudi() } }
                    else { Button("Indietro") { passo -= 1 } }
                }
            }
            .alert(passo == 0 ? "Nuovo cantiere" : "Nuova unità", isPresented: $chiediNome) {
                TextField(passo == 0 ? "Es. Via Roma 12" : "Es. App. 3", text: $nuovoNome)
                Button("Aggiungi") { aggiungi() }
                Button("Annulla", role: .cancel) { nuovoNome = "" }
            }
        }
    }

    private var sceltaCantiere: some View {
        VStack(spacing: 12) {
            ForEach(archivio.cantieri) { c in
                BottoneScelta(titolo: c.nome, icona: "building.2") {
                    cantiere = c; passo = 1
                }
            }
            BottoneScelta(titolo: "Aggiungi cantiere", icona: "plus", tenue: true) { nuovoNome = ""; chiediNome = true }
        }
    }

    private var sceltaUnita: some View {
        let c = archivio.cantieri.first { $0.id == cantiere?.id } ?? cantiere
        return VStack(spacing: 12) {
            ForEach(c?.unita ?? [], id: \.self) { u in
                BottoneScelta(titolo: u, icona: "door.left.hand.closed") { unita = u; passo = 2 }
            }
            BottoneScelta(titolo: "Tutto il cantiere", icona: "square.grid.2x2") { unita = "Generale"; passo = 2 }
            BottoneScelta(titolo: "Aggiungi unità", icona: "plus", tenue: true) { nuovoNome = ""; chiediNome = true }
        }
    }

    private var sceltaFase: some View {
        VStack(spacing: 12) {
            ForEach(Fase.allCases) { f in
                BottoneScelta(titolo: f.rawValue, icona: f.icona) {
                    guard let c = cantiere, let u = unita else { return }
                    parti(SceltaRilievo(cantiere: c.nome, cantiereId: c.markId, unita: u, fase: f.rawValue))
                }
            }
        }
    }

    private func aggiungi() {
        defer { nuovoNome = "" }
        if passo == 0 {
            if let c = archivio.aggiungiCantiere(nuovoNome) { cantiere = c; passo = 1 }
        } else if let c = cantiere {
            let n = nuovoNome.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            archivio.aggiungiUnita(n, a: c)
            unita = n; passo = 2
        }
    }
}

struct BottoneScelta: View {
    let titolo: String
    let icona: String
    var tenue = false
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            HStack(spacing: 14) {
                Image(systemName: icona).font(.title2).frame(width: 34)
                Text(titolo).font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Tema.testoTenue)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(tenue ? Tema.accento : Tema.testo)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct Indicatore: View {
    let passo: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule().fill(i <= passo ? Tema.accento : Color.gray.opacity(0.25)).frame(height: 6)
            }
        }
        .padding(.bottom, 4)
    }
}
