import SwiftUI

/// Piccola pianta 2D vista dall'alto: muri, porte, finestre, linea arancione del cammino.
struct MiniPianta: View {
    let tratti: [Tratto]
    let percorso: [CGPoint]
    var posizione: CGPoint? = nil
    var direzione: Double = 0
    var spessoreMuro: CGFloat = 3
    var copertura: [CellaCopertura] = []
    var soglia: Int = 30

    var body: some View {
        Canvas { ctx, size in
            var punti = percorso
            for t in tratti { punti.append(t.a); punti.append(t.b) }
            if let p = posizione { punti.append(p) }
            let L = CGFloat(Nuvola.lato2D)
            for c in copertura { punti.append(CGPoint(x: CGFloat(c.i) * L, y: CGFloat(c.k) * L)) }
            guard !punti.isEmpty else { return }
            let minX = punti.map(\.x).min()!, maxX = punti.map(\.x).max()!
            let minY = punti.map(\.y).min()!, maxY = punti.map(\.y).max()!
            let larg = max(maxX - minX, 2), alt = max(maxY - minY, 2)
            let margine: CGFloat = 10
            let scala = min((size.width - 2 * margine) / larg, (size.height - 2 * margine) / alt)
            let ox = (size.width - larg * scala) / 2 - minX * scala + (larg - (maxX - minX)) * scala / 2
            let oy = (size.height - alt * scala) / 2 - minY * scala + (alt - (maxY - minY)) * scala / 2
            func v(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scala + ox, y: p.y * scala + oy) }

            // copertura della nuvola: verde = fitta, arancione = pochi punti
            for c in copertura {
                let a = v(CGPoint(x: CGFloat(c.i) * L, y: CGFloat(c.k) * L))
                let r = CGRect(x: a.x, y: a.y, width: L * scala + 0.5, height: L * scala + 0.5)
                let col: Color = c.n >= soglia ? Tema.laser.opacity(0.55) : Tema.casco.opacity(0.45)
                ctx.fill(Path(r), with: .color(col))
            }
            for t in tratti {
                var p = Path(); p.move(to: v(t.a)); p.addLine(to: v(t.b))
                switch t.tipo {
                case .muro: ctx.stroke(p, with: .color(Tema.testo), style: StrokeStyle(lineWidth: spessoreMuro, lineCap: .round))
                case .porta: ctx.stroke(p, with: .color(Tema.casco), style: StrokeStyle(lineWidth: spessoreMuro + 1))
                case .finestra: ctx.stroke(p, with: .color(Tema.accento), style: StrokeStyle(lineWidth: spessoreMuro + 1))
                case .apertura: ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: spessoreMuro + 1))
                }
            }
            if percorso.count > 1 {
                var p = Path(); p.move(to: v(percorso[0]))
                for q in percorso.dropFirst() { p.addLine(to: v(q)) }
                ctx.stroke(p, with: .color(Tema.casco), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                let s = v(percorso[0])
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)), with: .color(Tema.ok))
            }
            if let pos = posizione {
                let c = v(pos)
                var freccia = Path()
                freccia.move(to: CGPoint(x: 0, y: -9)); freccia.addLine(to: CGPoint(x: 6, y: 6)); freccia.addLine(to: CGPoint(x: -6, y: 6)); freccia.closeSubpath()
                let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: direzione)
                ctx.fill(freccia.applying(t), with: .color(Tema.accento))
            }
        }
    }
}
