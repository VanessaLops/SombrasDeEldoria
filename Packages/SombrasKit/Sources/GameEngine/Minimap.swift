import SimCore
import SpriteKit

/// Minimapa no canto (em pontos de tela): estruturas, campeões e o retângulo da câmera.
/// Os pontos vêm de um conjunto reaproveitado de sprites, sem criar nós a cada atualização.
@MainActor
final class Minimap: SKNode {
    static let side: CGFloat = 150
    private let background: SKSpriteNode
    private let viewRect = SKShapeNode()
    private var dots: [SKSpriteNode] = []
    private let worldSize: Vec2

    init(worldSize: Vec2) {
        self.worldSize = worldSize
        background = SKSpriteNode(color: SKColor(hex: 0x05060D, alpha: 0.82), size: CGSize(width: Self.side, height: Self.side))
        background.anchorPoint = CGPoint(x: 0, y: 1)
        super.init()
        zPosition = Layer.hud
        addChild(background)
        let frame = SKShapeNode(rect: CGRect(x: 0, y: -Self.side, width: Self.side, height: Self.side))
        frame.strokeColor = Palette.gold
        frame.lineWidth = 2
        frame.zPosition = 2
        addChild(frame)
        viewRect.strokeColor = SKColor(white: 1, alpha: 0.7)
        viewRect.lineWidth = 1
        viewRect.zPosition = 3
        addChild(viewRect)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    private func point(_ world: Vec2) -> CGPoint {
        CGPoint(x: world.x / worldSize.x * Self.side, y: -world.y / worldSize.y * Self.side)
    }

    /// Ponto do mundo correspondente a um toque no minimapa (coordenadas locais), ou `nil` fora dele.
    func worldPoint(at local: CGPoint) -> Vec2? {
        guard local.x >= 0, local.x <= Self.side, local.y <= 0, local.y >= -Self.side else { return nil }
        return Vec2(local.x / Self.side * worldSize.x, -local.y / Self.side * worldSize.y)
    }

    func update(_ sim: Simulation, cameraCenter: Vec2, viewSize: CGSize) {
        var used = 0
        func dot(_ position: Vec2, size: CGFloat, color: SKColor, z: CGFloat) {
            if used == dots.count {
                let sprite = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
                addChild(sprite)
                dots.append(sprite)
            }
            let sprite = dots[used]
            sprite.isHidden = false
            sprite.color = color
            sprite.size = CGSize(width: size, height: size)
            sprite.position = point(position)
            sprite.zPosition = z
            used += 1
        }

        for relic in sim.relics {
            dot(relic.position, size: 7, color: relic.owner.map { Palette.team($0) } ?? Palette.portal, z: 1)
        }
        for pair in sim.portals {
            dot(pair.a, size: 5, color: Palette.portal, z: 1)
            dot(pair.b, size: 5, color: Palette.portal, z: 1)
        }
        for unit in sim.units where unit.isAlive && sim.isKnownToLocalTeam(unit.id) {
            let friendly = unit.team == sim.localTeam
            let color: SKColor = unit.team == .neutral ? Palette.monster : friendly ? Palette.ally : Palette.enemy
            switch unit.role {
            case .tower: dot(unit.position, size: 7, color: color, z: 1)
            case .nexus: dot(unit.position, size: 11, color: color, z: 1)
            case .minion, .monster: dot(unit.position, size: 3, color: color, z: 1)
            case .hero(let id):
                let local = unit.id == sim.localHero
                dot(unit.position, size: local ? 13 : 11, color: local ? Palette.gold : color, z: local ? 2.2 : 2)
                dot(unit.position, size: local ? 9 : 7, color: Palette.hero(id), z: local ? 2.3 : 2.1)
            case .trainingDummy, .sentinel: dot(unit.position, size: 5, color: color, z: 1)
            }
        }
        for index in used..<dots.count { dots[index].isHidden = true }

        let w = viewSize.width / worldSize.x * Self.side
        let h = viewSize.height / worldSize.y * Self.side
        let c = point(cameraCenter)
        viewRect.path = CGPath(rect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), transform: nil)
    }
}
