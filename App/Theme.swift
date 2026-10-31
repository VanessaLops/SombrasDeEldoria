import GameEngine
import SimCore
import SwiftUI

/// Cores e estilos da interface SwiftUI (a cena usa `Palette`, com os mesmos tons).
enum Theme {
    static let navy = Color(hex: 0x0A1428)
    static let panel = Color(hex: 0x0F1B33).opacity(0.85)
    static let panelEdge = Color(hex: 0x3B4A6B)
    static let gold = Color(hex: 0xC8AA6E)
    static let goldDark = Color(hex: 0x785A28)
    static let text = Color(hex: 0xF2F0FF)
    static let dim = Color(hex: 0x9A98B8)
    static let hp = Color(hex: 0x5BE07A)
    static let mana = Color(hex: 0x4AA3FF)
    static let flux = Color(hex: 0x4DE8C8)
    static let light = Color(hex: 0xFFD76A)
    static let shadow = Color(hex: 0xB36BFF)
    static let ally = Color(hex: 0x8FD1FF)
    static let enemy = Color(hex: 0xFF5A5A)

    static func team(_ team: Team?) -> Color {
        switch team {
        case .light: light
        case .shadow: shadow
        default: dim
        }
    }

    static func difficulty(_ difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy: hp
        case .medium: light
        case .hard: enemy
        }
    }

    static func hero(_ id: HeroID) -> Color { Color(hex: HeroDefinition.definition(for: id).color) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Retrato do campeão: a mesma figura do mapa (`HeroArt`), do peito para cima, num medalhão.
struct HeroBadge: View {
    let hero: HeroID
    var face: Face? = nil
    var size: CGFloat = 48

    var body: some View {
        let definition = HeroDefinition.definition(for: hero)
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.hero(hero).opacity(0.9), Color(hex: 0x0A1428)], center: .center, startRadius: 0, endRadius: size * 0.7))
            Canvas { context, canvas in
                // Mostra a faixa de 0 a 84 da figura (cabeça e tronco), centrada.
                let scale = canvas.height / 84
                context.translateBy(x: (canvas.width - HeroArt.width * scale) / 2, y: canvas.height * 0.06)
                context.scaleBy(x: scale, y: scale)
                for part in HeroArt.parts(hero, face: face) {
                    let path = Path(part.path)
                    if let fill = part.fill { context.fill(path, with: .color(Color(cgColor: fill))) }
                    if let stroke = part.stroke {
                        context.stroke(path, with: .color(Color(cgColor: stroke)), style: StrokeStyle(lineWidth: part.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(face == .shadow ? Theme.shadow : face == .light ? Theme.light : Theme.panelEdge, lineWidth: max(2, size * 0.05))
        }
        .accessibilityLabel(definition.name)
    }
}

/// Botão principal dourado.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .black))
            .tracking(1)
            .foregroundStyle(Color(hex: 0x1A1530))
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.goldDark, lineWidth: 3))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
