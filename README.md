# MARK Rilievi

App per iPhone (con LiDAR) che fa i rilievi in cantiere camminando: muri, porte e finestre (RoomPlan),
nuvola di punti (laser), foto con profondità, percorso. Tutto resta sul telefono; più avanti i rilievi
passano allo "Studio Rilievi" di MARK sulla Wi-Fi dell'ufficio.

- Swift + SwiftUI, iOS 17+, RoomPlan + ARKit. Progetto generato con XcodeGen (`project.yml`).
- Costruzione: GitHub Actions (`.github/workflows/costruisci-app.yml`) sul Mac gratuito di GitHub,
  senza firma. Il file `MARK-Rilievi.ipa` esce nella release "ultima" e si installa con SideStore.
- Nessun dato di clienti o cantieri nel codice.

## Formato di un rilievo (cartella in Documenti/Rilievi)
- `rilievo.json`: cantiere, unità, fase, data, versione app, stanze con superfici e altezze, numeri di foto e punti.
- `stanze.json`: le stanze di RoomPlan (`CapturedRoom`), tutte nello stesso sistema di riferimento.
- `nuvola.ply`: nuvola di punti colorata (metri, Y in alto), apribile con CloudCompare/MeshLab.
- `percorso.json`: posizioni del telefono nel tempo.
- `foto/NNN.jpg` + `NNN.profondita` (Float32, metri) + `NNN.json` (posizione e ottica della camera).
