import SwiftUI

/// "Traccia": il robot geometra. Bianco arrotondato, visiera scura, occhi azzurri,
/// casco arancione con la lente LiDAR verde, raggio laser verde tratteggiato, iPhone in mano.
struct TracciaView: View {
    var dimensione: CGFloat = 120
    var saluta: Bool = false
    var laser: Bool = true
    @State private var braccioSu = false
    @State private var occhiAperti = true

    var body: some View {
        let s = dimensione / 120
        ZStack {
            // raggio laser dalla lente del casco
            if laser {
                Path { p in
                    p.move(to: CGPoint(x: 72 * s, y: 18 * s))
                    p.addLine(to: CGPoint(x: 118 * s, y: 4 * s))
                }
                .stroke(Tema.laser, style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round, dash: [5 * s, 4 * s]))
            }
            // corpo
            RoundedRectangle(cornerRadius: 18 * s)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 18 * s).stroke(Color.black.opacity(0.08), lineWidth: 1))
                .frame(width: 52 * s, height: 40 * s)
                .position(x: 60 * s, y: 92 * s)
            // braccio sinistro (saluta)
            Capsule()
                .fill(.white)
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .frame(width: 12 * s, height: 30 * s)
                .rotationEffect(.degrees(braccioSu ? 140 : 20), anchor: .top)
                .position(x: 32 * s, y: 88 * s)
            // braccio destro con iPhone
            Capsule()
                .fill(.white)
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .frame(width: 12 * s, height: 28 * s)
                .rotationEffect(.degrees(-35), anchor: .top)
                .position(x: 88 * s, y: 88 * s)
            RoundedRectangle(cornerRadius: 3 * s)
                .fill(Tema.visiera)
                .frame(width: 13 * s, height: 22 * s)
                .overlay(Circle().fill(Tema.laser).frame(width: 3 * s).offset(x: -2.5 * s, y: -7 * s))
                .rotationEffect(.degrees(-12))
                .position(x: 98 * s, y: 104 * s)
            // testa
            RoundedRectangle(cornerRadius: 22 * s)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 22 * s).stroke(Color.black.opacity(0.08), lineWidth: 1))
                .frame(width: 70 * s, height: 52 * s)
                .position(x: 60 * s, y: 48 * s)
            // visiera con occhi
            RoundedRectangle(cornerRadius: 14 * s)
                .fill(Tema.visiera)
                .frame(width: 54 * s, height: 26 * s)
                .overlay(
                    HStack(spacing: 14 * s) {
                        Capsule().fill(Tema.occhi).frame(width: 9 * s, height: occhiAperti ? 12 * s : 2 * s)
                        Capsule().fill(Tema.occhi).frame(width: 9 * s, height: occhiAperti ? 12 * s : 2 * s)
                    }
                    .shadow(color: Tema.occhi.opacity(0.8), radius: 4 * s)
                )
                .position(x: 60 * s, y: 52 * s)
            // casco arancione
            CascoForma()
                .fill(Tema.casco)
                .frame(width: 80 * s, height: 30 * s)
                .position(x: 60 * s, y: 22 * s)
            // lente LiDAR verde
            Circle()
                .fill(Tema.laser)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5 * s))
                .frame(width: 11 * s, height: 11 * s)
                .shadow(color: Tema.laser, radius: 4 * s)
                .position(x: 70 * s, y: 18 * s)
        }
        .frame(width: dimensione, height: dimensione)
        .onAppear {
            if saluta {
                withAnimation(.easeInOut(duration: 0.45).repeatCount(5, autoreverses: true)) { braccioSu = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { withAnimation { braccioSu = false } }
            }
            Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.12)) { occhiAperti = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.12)) { occhiAperti = true }
                }
            }
        }
        .accessibilityLabel("Traccia, il robot dei rilievi")
    }
}

/// Casco da cantiere: cupola con la tesa.
struct CascoForma: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tesa = r.height * 0.22
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.maxY - tesa))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.06, y: r.maxY - tesa),
                   control1: CGPoint(x: r.maxX - r.width * 0.12, y: r.minY - r.height * 0.25),
                   control2: CGPoint(x: r.minX + r.width * 0.12, y: r.minY - r.height * 0.25))
        p.closeSubpath()
        return p
    }
}

/// Fumetto di Traccia.
struct FumettoTraccia: View {
    let testo: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TracciaView(dimensione: 76, saluta: true, laser: false)
            Text(testo)
                .font(.headline)
                .foregroundStyle(Tema.testo)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            Spacer(minLength: 0)
        }
    }
}
