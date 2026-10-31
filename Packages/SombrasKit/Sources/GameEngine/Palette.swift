import SimCore
import SpriteKit

/// Paleta do jogo. Cores só aqui, nunca espalhadas pelo código de desenho.
public enum Palette {
    public static let background = SKColor(hex: 0x0B0D14)
    public static let grass = SKColor(hex: 0x1D3324)
    public static let grassDark = SKColor(hex: 0x182B1E)
    public static let river = SKColor(hex: 0x265A7A)
    public static let lane = SKColor(hex: 0x5F4F36)
    public static let laneEdge = SKColor(hex: 0x2B2619)
    public static let base = SKColor(hex: 0x343746)
    public static let wall = SKColor(hex: 0x5A5E70)
    public static let wallEdge = SKColor(hex: 0x3A3A48)
    public static let crystal = SKColor(hex: 0x58CFFF)
    public static let crystalEdge = SKColor(hex: 0xBDEEFF)
    public static let tree = SKColor(hex: 0x245A32)
    public static let light = SKColor(hex: 0xFFD76A)
    public static let shadow = SKColor(hex: 0xB36BFF)
    public static let ally = SKColor(hex: 0x8FD1FF)
    public static let enemy = SKColor(hex: 0xFF5A5A)
    public static let monster = SKColor(hex: 0x8CB369)
    public static let hp = SKColor(hex: 0x5BE07A)
    public static let mana = SKColor(hex: 0x4AA3FF)
    public static let flux = SKColor(hex: 0x4DE8C8)
    public static let gold = SKColor(hex: 0xC8AA6E)
    public static let text = SKColor(hex: 0xF2F0FF)
    public static let textDim = SKColor(hex: 0x9A98B8)
    public static let fog = SKColor(hex: 0x0A0C1C)
    public static let portal = SKColor(hex: 0x9B6BFF)
    public static let dummy = SKColor(hex: 0xC9A37A)

    public static func team(_ team: Team) -> SKColor {
        switch team {
        case .light: light
        case .shadow: shadow
        case .neutral: monster
        }
    }

    public static func hero(_ id: HeroID) -> SKColor {
        SKColor(hex: HeroDefinition.definition(for: id).color)
    }
}

extension SKColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
