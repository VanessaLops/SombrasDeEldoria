import CoreGraphics
import SimCore

/// Figura vetorial de cada campeão (estilo "chibi", legível num celular), descrita como uma lista de
/// formas numa caixa de 100 × 120 com y para baixo e os pés em (50, 120). A mesma lista desenha o
/// campeão no mapa (SpriteKit) e o retrato na interface (SwiftUI), então os dois nunca divergem.
public enum HeroArt {
    public struct Part: @unchecked Sendable {
        public let path: CGPath
        public let fill: CGColor?
        public let stroke: CGColor?
        public let lineWidth: CGFloat
    }

    public static let width: CGFloat = 100
    public static let height: CGFloat = 120

    enum Hair { case short, long, ponytail, spiky, bun, hood, flame, helmet }
    enum Weapon { case staff, sword, bow, blades, flask, daggers, axe, orb, druidStaff }
    enum Accessory { case crystal, scar, warpaint, goggles, flaskBelt, eyepatch, antlers, mask, crown, beard }

    struct Look {
        let skin: UInt32
        let hair: UInt32
        let hairStyle: Hair
        let cloth: UInt32
        let accent: UInt32
        let eyes: UInt32
        let weapon: Weapon
        let accessory: Accessory
        let cape: Bool
        /// Ombros largos (guerreiros e tanques).
        let bulky: Bool
    }

    /// Aparência de cada campeão, tirada da bíblia do livro (`docs/PERSONAGENS.md`).
    static func look(_ hero: HeroID) -> Look {
        switch hero {
        case .alaric: Look(skin: 0xE8C4A0, hair: 0xCFD9F5, hairStyle: .short, cloth: 0x2A4A9C, accent: 0xFFD76A, eyes: 0x4A7BFF, weapon: .staff, accessory: .crystal, cape: true, bulky: false)
        case .lyara: Look(skin: 0xC98D62, hair: 0x5A2A1C, hairStyle: .ponytail, cloth: 0xB34A2A, accent: 0xFFCF8A, eyes: 0x7A4A2A, weapon: .sword, accessory: .scar, cape: false, bulky: true)
        case .kaelith: Look(skin: 0xD9A982, hair: 0x2F4A2A, hairStyle: .hood, cloth: 0x35552F, accent: 0x9BD36B, eyes: 0x3FAE5A, weapon: .bow, accessory: .warpaint, cape: true, bulky: false)
        case .eryon: Look(skin: 0xB98A63, hair: 0x2A2F3D, hairStyle: .spiky, cloth: 0x6A4A30, accent: 0x4DD2D2, eyes: 0x2AA8C8, weapon: .blades, accessory: .goggles, cape: false, bulky: false)
        case .saria: Look(skin: 0xE6BF9D, hair: 0x7A3F9A, hairStyle: .bun, cloth: 0x55306E, accent: 0xC58CFF, eyes: 0xA05AD0, weapon: .flask, accessory: .flaskBelt, cape: false, bulky: false)
        case .kaelor: Look(skin: 0xC99B78, hair: 0x4A3A28, hairStyle: .hood, cloth: 0x4A5A34, accent: 0x8CB369, eyes: 0x6A8A3A, weapon: .bow, accessory: .eyepatch, cape: true, bulky: false)
        case .nyssa: Look(skin: 0xBF8F6A, hair: 0x2A5A3A, hairStyle: .long, cloth: 0x2D6A4A, accent: 0x5BD68A, eyes: 0x3AD08A, weapon: .druidStaff, accessory: .antlers, cape: false, bulky: false)
        case .nyx: Look(skin: 0x9A9AC0, hair: 0x14101E, hairStyle: .hood, cloth: 0x1A1530, accent: 0x9B6BFF, eyes: 0xC7B0FF, weapon: .daggers, accessory: .mask, cape: true, bulky: false)
        case .kallindra: Look(skin: 0xE0B08A, hair: 0xFF9A2A, hairStyle: .flame, cloth: 0x8A2A1A, accent: 0xFFB84D, eyes: 0xFFD24A, weapon: .orb, accessory: .crown, cape: true, bulky: false)
        case .korrath: Look(skin: 0xA87A60, hair: 0x3A3F4A, hairStyle: .helmet, cloth: 0x4A4F5A, accent: 0xD94F6A, eyes: 0xD0D4E0, weapon: .axe, accessory: .beard, cape: true, bulky: true)
        }
    }

    // MARK: Montagem

    /// Formas do campeão, de trás para a frente. A Face da Sombra escurece roupas e acende os olhos;
    /// `nil` é o visual neutro que o inimigo vê (a face é segredo).
    public static func parts(_ hero: HeroID, face: Face?) -> [Part] {
        let base = look(hero)
        let shadow = face == .shadow
        let skin = shadow ? mix(base.skin, 0x6A5A8A, 0.25) : base.skin
        let hair = shadow ? mix(base.hair, 0x000000, 0.35) : base.hair
        let cloth = shadow ? mix(base.cloth, 0x1A0F2A, 0.45) : base.cloth
        let accent = shadow ? mix(base.accent, 0xB36BFF, 0.5) : base.accent
        let eyes: UInt32 = shadow ? 0xFF3A5E : base.eyes
        let outline = color(0x0B0D14)
        let width: CGFloat = base.bulky ? 1.15 : 1

        var parts: [Part] = []
        func add(_ path: CGPath, _ fill: UInt32?, stroke: CGColor? = outline, line: CGFloat = 2.2, alpha: CGFloat = 1) {
            parts.append(Part(path: path, fill: fill.map { color($0, alpha) }, stroke: stroke, lineWidth: line))
        }

        // Sombra no chão e aura da face (só para quem pode ver a face).
        add(ellipse(50, 118, 26 * width, 6), 0x000000, stroke: nil, alpha: 0.35)
        if let face {
            add(ellipse(50, 118, 34, 9), nil, stroke: color(face == .light ? 0xFFF0B8 : 0xB36BFF, 0.8), line: 2.5)
        }

        // Capa e cabelo de trás.
        if base.cape { add(poly([(30, 60), (70, 60), (80, 112), (20, 112)]), mix(cloth, 0x000000, 0.35)) }
        for path in hairBack(base.hairStyle) { add(path, hair) }

        // Arma atrás do corpo (cajados e arcos ficam ao lado).
        if [.staff, .druidStaff, .bow].contains(base.weapon) {
            for (path, fill, stroke) in weapon(base.weapon, accent: accent) { add(path, fill, stroke: stroke.map { color($0) } ?? outline) }
        }

        // Pernas, tronco, cinto e braços.
        add(roundRect(37, 92, 11, 26, 4), mix(cloth, 0x000000, 0.4))
        add(roundRect(52, 92, 11, 26, 4), mix(cloth, 0x000000, 0.4))
        add(roundRect(35, 113, 14, 7, 3), 0x2A2018)
        add(roundRect(51, 113, 14, 7, 3), 0x2A2018)
        let shoulder = 22 * width
        add(poly([(50 - shoulder, 62), (50 + shoulder, 62), (50 + 15 * width, 98), (50 - 15 * width, 98)]), cloth)
        add(roundRect(50 - 15 * width, 86, 30 * width, 5, 2), accent, stroke: nil)
        add(poly([(46, 62), (54, 62), (50, 74)]), mix(cloth, 0xFFFFFF, 0.2), stroke: nil)
        if base.bulky {
            add(ellipse(50 - shoulder, 64, 9, 6), mix(cloth, 0xFFFFFF, 0.25))
            add(ellipse(50 + shoulder, 64, 9, 6), mix(cloth, 0xFFFFFF, 0.25))
        }
        add(roundRect(50 - shoulder - 6, 64, 9, 26, 4), cloth)
        add(roundRect(50 + shoulder - 3, 64, 9, 26, 4), cloth)
        add(ellipse(50 - shoulder - 1.5, 92, 5, 5), skin)
        add(ellipse(50 + shoulder + 1.5, 92, 5, 5), skin)

        // Cabeça grande (chibi): rosto, olhos e boca.
        add(ellipse(50, 40, 21, 22), skin)
        for x in [42.0, 58.0] {
            add(ellipse(x, 42, 3.6, 4.2), 0xFFFFFF, stroke: nil)
            add(ellipse(x, 42.5, 2.4, 3), eyes, stroke: nil)
            if shadow { add(ellipse(x, 42.5, 5, 5), eyes, stroke: nil, alpha: 0.35) }
        }
        add(line([(46, 52), (54, 52)]), nil, stroke: color(mix(skin, 0x000000, 0.45)), line: 1.6)
        for path in hairFront(base.hairStyle) { add(path, hair) }
        if base.hairStyle == .hood { add(hoodEdge(), mix(hair, 0x000000, 0.25)) }

        for (path, fill, stroke, lineWidth) in accessory(base.accessory, accent: accent, skin: skin, hair: hair) {
            add(path, fill, stroke: stroke.map { color($0) } ?? outline, line: lineWidth)
        }

        // Armas de mão na frente.
        if ![.staff, .druidStaff, .bow].contains(base.weapon) {
            for (path, fill, stroke) in weapon(base.weapon, accent: accent) { add(path, fill, stroke: stroke.map { color($0) } ?? outline) }
        }
        return parts
    }

    // MARK: Cabelos

    static func hairBack(_ style: Hair) -> [CGPath] {
        switch style {
        case .long: [poly([(28, 34), (72, 34), (76, 84), (24, 84)])]
        case .ponytail: [poly([(64, 28), (82, 34), (86, 66), (74, 74), (70, 46)])]
        case .hood: [poly([(24, 66), (22, 34), (36, 14), (64, 14), (78, 34), (76, 66)])]
        case .flame:
            [poly([(26, 46), (22, 20), (32, 26), (36, 6), (46, 20), (52, 2), (58, 20), (66, 6), (70, 26), (80, 20), (74, 46)])]
        case .helmet: [poly([(30, 26), (14, 18), (12, 2), (24, 14), (36, 20)]), poly([(70, 26), (86, 18), (88, 2), (76, 14), (64, 20)])]
        case .short, .spiky, .bun: []
        }
    }

    static func hairFront(_ style: Hair) -> [CGPath] {
        switch style {
        case .short: [poly([(29, 40), (30, 24), (42, 17), (60, 17), (71, 26), (71, 40), (64, 30), (52, 27), (40, 30)])]
        case .long: [poly([(29, 44), (31, 24), (44, 17), (58, 17), (70, 24), (71, 44), (62, 30), (50, 28), (38, 30)])]
        case .ponytail: [poly([(29, 40), (31, 22), (44, 16), (60, 17), (71, 26), (71, 38), (60, 29), (40, 29)])]
        case .spiky: [poly([(29, 40), (25, 22), (35, 26), (36, 10), (45, 22), (52, 6), (57, 22), (66, 10), (68, 26), (76, 22), (71, 40), (60, 30), (40, 30)])]
        case .bun: [ellipse(50, 14, 9, 8), poly([(29, 40), (31, 24), (44, 18), (58, 18), (70, 24), (71, 40), (62, 30), (40, 30)])]
        case .flame: [poly([(29, 40), (31, 24), (44, 18), (58, 18), (70, 24), (71, 40), (62, 31), (40, 31)])]
        case .helmet: [poly([(28, 44), (28, 24), (40, 16), (60, 16), (72, 24), (72, 44), (64, 44), (64, 32), (36, 32), (36, 44)])]
        case .hood: []
        }
    }

    static func hoodEdge() -> CGPath {
        poly([(27, 58), (27, 30), (38, 20), (62, 20), (73, 30), (73, 58), (68, 58), (67, 34), (58, 27), (42, 27), (33, 34), (32, 58)])
    }

    // MARK: Acessórios e armas

    typealias Shape = (CGPath, UInt32?, UInt32?, CGFloat)

    static func accessory(_ kind: Accessory, accent: UInt32, skin: UInt32, hair: UInt32) -> [Shape] {
        switch kind {
        case .crystal: [(poly([(50, 21), (54, 27), (50, 33), (46, 27)]), accent, 0xFFFFFF, 1.5)]
        case .scar: [(line([(56, 36), (61, 50)]), nil, mix(skin, 0x000000, 0.45), 2)]
        case .warpaint: [(line([(37, 47), (44, 48)]), nil, accent, 2.4), (line([(63, 47), (56, 48)]), nil, accent, 2.4)]
        case .goggles: [(roundRect(33, 32, 34, 8, 4), 0x2A2A2A, nil, 1.5), (ellipse(42, 36, 5, 4), accent, nil, 1.2), (ellipse(58, 36, 5, 4), accent, nil, 1.2)]
        case .flaskBelt: [(roundRect(56, 84, 7, 10, 2), accent, nil, 1.2), (roundRect(44, 84, 7, 10, 2), 0x8AE0FF, nil, 1.2)]
        case .eyepatch: [(ellipse(58, 42, 5.5, 5), 0x1A1A1A, nil, 1), (line([(36, 34), (66, 46)]), nil, 0x1A1A1A, 1.5)]
        case .antlers:
            [(poly([(36, 20), (30, 4), (34, 10), (34, 0), (38, 12), (40, 18)]), 0xD8C8A0, nil, 1.5),
             (poly([(64, 20), (70, 4), (66, 10), (66, 0), (62, 12), (60, 18)]), 0xD8C8A0, nil, 1.5)]
        case .mask: [(poly([(30, 46), (70, 46), (66, 58), (50, 62), (34, 58)]), 0x1A1530, accent, 1.5)]
        case .crown: [(poly([(36, 20), (40, 8), (45, 16), (50, 4), (55, 16), (60, 8), (64, 20)]), 0xFFD76A, nil, 1.5)]
        case .beard: [(poly([(32, 46), (68, 46), (64, 62), (50, 70), (36, 62)]), mix(hair, 0x5A4A3A, 0.4), nil, 1.5)]
        }
    }

    static func weapon(_ kind: Weapon, accent: UInt32) -> [(CGPath, UInt32?, UInt32?)] {
        switch kind {
        case .staff:
            [(roundRect(76, 30, 4, 86, 2), 0x6B4A2A, nil), (ellipse(78, 26, 8, 8), accent, 0xFFFFFF)]
        case .druidStaff:
            [(roundRect(76, 32, 4, 84, 2), 0x5A4024, nil), (poly([(70, 34), (78, 18), (86, 34), (78, 28)]), accent, nil)]
        case .bow:
            [(arc(center: (80, 74), radius: 30, from: -1.25, to: 1.25), nil, 0x8A6A3A), (line([(91, 46), (91, 102)]), nil, 0xE8E8F0)]
        case .sword:
            [(poly([(76, 46), (82, 46), (82, 90), (79, 96), (76, 90)]), 0xD8DCE8, nil), (roundRect(72, 88, 14, 4, 2), accent, nil),
             (ellipse(22, 82, 11, 14), mix(accent, 0x8A4A2A, 0.5), nil)]
        case .blades:
            [(poly([(18, 70), (22, 70), (20, 100)]), accent, nil), (poly([(78, 70), (82, 70), (80, 100)]), accent, nil)]
        case .flask:
            [(roundRect(74, 84, 12, 14, 5), accent, nil), (roundRect(77, 78, 6, 7, 2), 0xE8E8F0, nil)]
        case .daggers:
            [(poly([(16, 90), (20, 90), (18, 74)]), 0xC7B0FF, nil), (poly([(80, 90), (84, 90), (82, 74)]), 0xC7B0FF, nil)]
        case .axe:
            [(roundRect(78, 40, 4, 64, 2), 0x5A4024, nil), (poly([(80, 42), (96, 36), (98, 56), (80, 52)]), 0xB8BCC8, nil)]
        case .orb:
            [(ellipse(80, 82, 9, 9), accent, 0xFFFFFF), (ellipse(80, 82, 14, 14), accent, nil)]
        }
    }

    // MARK: Formas básicas (y para baixo)

    static func poly(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return path
    }

    static func line(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        return path
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil)
    }

    static func arc(center: (CGFloat, CGFloat), radius: CGFloat, from: CGFloat, to: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: center.0, y: center.1), radius: radius, startAngle: from, endAngle: to, clockwise: false)
        return path
    }

    // MARK: Cores

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }

    /// Mistura `a` com `b` (t = 0 → a, t = 1 → b).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF)
            let y = Double((b >> shift) & 0xFF)
            return UInt32(min(255, max(0, (x + (y - x) * t).rounded())))
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }
}
