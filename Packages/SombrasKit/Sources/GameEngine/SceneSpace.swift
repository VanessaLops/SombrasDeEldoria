import CoreGraphics
import SimCore

// A simulação usa y para baixo (como uma tela); o SpriteKit usa y para cima.
// Toda conversão entre os dois espaços passa por aqui.

extension Vec2 {
    /// Posição na cena (y invertido).
    var scenePoint: CGPoint { CGPoint(x: x, y: -y) }
}

extension CGPoint {
    /// Posição no mundo da simulação.
    var world: Vec2 { Vec2(Double(x), Double(-y)) }
}

enum SceneSpace {
    /// Rotação do SpriteKit para um ângulo da simulação.
    static func rotation(_ angle: Double) -> CGFloat { CGFloat(-angle) }

    /// Profundidade: quem está mais embaixo na tela (y maior no mundo) fica na frente.
    static func depth(_ worldY: Double) -> CGFloat { Layer.units + CGFloat(worldY / 100_000) }
}

/// Camadas de desenho (zPosition).
enum Layer {
    static let ground: CGFloat = 0
    static let decals: CGFloat = 5
    static let units: CGFloat = 10
    static let projectiles: CGFloat = 20
    static let effects: CGFloat = 25
    static let fog: CGFloat = 30
    static let bars: CGFloat = 35
    static let hud: CGFloat = 100
}
