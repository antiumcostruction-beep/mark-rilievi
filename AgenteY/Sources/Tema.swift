import SwiftUI

/// Colori di MARK (tema chiaro "ufficio luminoso").
enum Tema {
    static let sfondo = Color(hex: 0xEEF2F5)
    static let pannello = Color.white
    static let accento = Color(hex: 0x1F6FBF)
    static let testo = Color(hex: 0x1D2933)
    static let testoTenue = Color(hex: 0x5B6B78)
    static let casco = Color(hex: 0xE08A00)
    static let laser = Color(hex: 0x2BD46B)
    static let occhi = Color(hex: 0x6FE3FF)
    static let visiera = Color(hex: 0x1B2530)
    static let ok = Color(hex: 0x1E9E55)
    static let rosso = Color(hex: 0xD23B3B)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Bottone grande, facile da toccare in cantiere.
struct BottoneGrande: View {
    let titolo: String
    var icona: String? = nil
    var colore: Color = Tema.accento
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 12) {
                if let icona { Image(systemName: icona).font(.title2.weight(.semibold)) }
                Text(titolo).font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(.white)
            .background(colore, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Pannello bianco arrotondato.
struct Pannello<Contenuto: View>: View {
    @ViewBuilder let contenuto: () -> Contenuto
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { contenuto() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}
