import SwiftUI

enum Qualita: String, CaseIterable, Identifiable {
    case veloce = "Veloce", normale = "Normale", dettaglio = "Dettaglio"
    var id: String { rawValue }
    /// Lato del "cubetto" della nuvola: un punto per cubetto.
    var cubetto: Float {
        switch self { case .veloce: return 0.03; case .normale: return 0.02; case .dettaglio: return 0.01 }
    }
    /// Un pixel ogni quanti, sulla mappa di profondità (256×192).
    var passo: Int {
        switch self { case .veloce: return 6; case .normale: return 4; case .dettaglio: return 3 }
    }
}

/// Le impostazioni dell'app, già giuste di partenza.
enum Chiave {
    static let qualita = "qualita"
    static let distanza = "distanzaLaser"
    static let fotoAuto = "fotoAutomatiche"
    static let fotoMetri = "fotoOgniMetri"
    static let torcia = "torciaAlBuio"
    static let voce = "guidaVoce"
    static let vibrazione = "vibrazione"
    static let invioAuto = "invioAutomatico"
    static let indirizzoMark = "indirizzoMark"
    static let gettone = "gettoneMark"
    static let ultimoIndirizzo = "ultimoIndirizzoMark"
}

struct ImpostazioniView: View {
    @Environment(\.dismiss) private var chiudi
    @AppStorage(Chiave.qualita) private var qualita = Qualita.normale.rawValue
    @AppStorage(Chiave.distanza) private var distanza = 5.0
    @AppStorage(Chiave.fotoAuto) private var fotoAuto = true
    @AppStorage(Chiave.fotoMetri) private var fotoMetri = 1.0
    @AppStorage(Chiave.torcia) private var torcia = true
    @AppStorage(Chiave.voce) private var voce = true
    @AppStorage(Chiave.vibrazione) private var vibrazione = true
    @AppStorage(Chiave.invioAuto) private var invioAuto = true
    @AppStorage(Chiave.indirizzoMark) private var indirizzo = ""
    @EnvironmentObject var collegamento: Collegamento
    @State private var codice = ""
    @State private var esito: String?
    @State private var chiediTogli = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rilievo") {
                    Picker("Qualità", selection: $qualita) {
                        ForEach(Qualita.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Distanza laser", selection: $distanza) {
                        Text("3 m").tag(3.0)
                        Text("5 m").tag(5.0)
                    }
                    Toggle("Foto automatiche", isOn: $fotoAuto)
                    if fotoAuto {
                        Picker("Una foto ogni", selection: $fotoMetri) {
                            Text("50 cm").tag(0.5)
                            Text("1 metro").tag(1.0)
                            Text("2 metri").tag(2.0)
                        }
                    }
                    Toggle("Torcia al buio", isOn: $torcia)
                }
                Section("Guida") {
                    Toggle("Guida a voce", isOn: $voce)
                    Toggle("Vibrazione", isOn: $vibrazione)
                }
                Section {
                    if collegamento.abbinato {
                        Label("Abbinato a MARK", systemImage: "checkmark.circle.fill").foregroundStyle(Tema.ok)
                        Button("Manda a MARK adesso") { Task { await collegamento.sincronizza(daSolo: false) } }
                            .disabled(collegamento.lavora)
                        Button("Togli l'abbinamento", role: .destructive) { chiediTogli = true }
                    } else {
                        TextField("Codice di 6 cifre da MARK", text: $codice)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                        Button {
                            Task { esito = await collegamento.abbina(codice: codice) ?? "Fatto: telefono abbinato a MARK." }
                        } label: {
                            if collegamento.lavora { ProgressView() } else { Text("Abbina a MARK") }
                        }
                        .disabled(codice.filter(\.isNumber).count != 6 || collegamento.lavora)
                    }
                    Text(collegamento.stato).font(.footnote).foregroundStyle(Tema.testoTenue)
                } header: {
                    Text("Collegamento con MARK")
                } footer: {
                    Text(collegamento.abbinato ? "Quando sei sulla Wi-Fi dell'ufficio i rilievi partono da soli." :
                         "Sul PC apri MARK → Rilievi → \"Abbina un telefono\" e scrivi qui il codice. Il telefono deve essere sulla Wi-Fi dell'ufficio.")
                }
                Section {
                    Toggle("Invio automatico a MARK", isOn: $invioAuto)
                    TextField("Indirizzo MARK (vuoto = lo trova da solo)", text: $indirizzo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("MARK")
                } footer: {
                    Text("Di solito l'indirizzo non serve: il telefono trova MARK da solo. I rilievi restano anche nell'app File → Sul mio iPhone → MARK Rilievi.")
                }
                Section {
                    LabeledContent("Versione", value: InfoApp.versione)
                }
            }
            .navigationTitle("Impostazioni")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { chiudi() } } }
            .alert(esito ?? "", isPresented: Binding(get: { esito != nil }, set: { if !$0 { esito = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert("Togliere l'abbinamento con MARK?", isPresented: $chiediTogli) {
                Button("Togli", role: .destructive) { collegamento.dimentica() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Per mandare altri rilievi dovrai chiedere un codice nuovo in MARK.")
            }
        }
    }
}
