import SimCore
import SpriteKit

/// Terreno estático do mapa (chão, rio, rotas, bases, obstáculos, altares e portais), montado uma vez.
@MainActor
enum Terrain {
    static func build(for sim: Simulation) -> SKNode {
        let root = SKNode()
        root.zPosition = Layer.ground
        let size = sim.map.size

        let grass = SKSpriteNode(color: Palette.grass, size: CGSize(width: size.x, height: size.y))
        grass.anchorPoint = CGPoint(x: 0, y: 1)
        grass.position = .zero
        root.addChild(grass)

        // Manchas de grama mais escura, com sorteio fixo (o mapa sai igual em toda partida).
        var random = SeededRandom(seed: 1337)
        for _ in 0..<Int(size.x * size.y / 250_000) {
            let blob = SKShapeNode(ellipseOf: CGSize(width: .random(in: 160...440, using: &random), height: .random(in: 100...280, using: &random)))
            blob.fillColor = Palette.grassDark
            blob.strokeColor = .clear
            blob.alpha = 0.6
            blob.position = Vec2(.random(in: 0...size.x, using: &random), .random(in: 0...size.y, using: &random)).scenePoint
            root.addChild(blob)
        }

        if sim.lanes.count >= 3 {
            // Rio na diagonal, com curvas suaves; as rotas o cruzam por vaus.
            let river = CGMutablePath()
            river.move(to: Vec2(-200, -200).scenePoint)
            for i in 1...12 {
                let t = Double(i) / 12
                let wiggle = sin(t * .pi * 3) * 220
                river.addLine(to: Vec2(t * (size.x + 400) - 200 + wiggle, t * (size.y + 400) - 200 - wiggle).scenePoint)
            }
            root.addChild(stroke(river, width: 430, color: SKColor(hex: 0x1D4560)))
            root.addChild(stroke(river, width: 300, color: Palette.river))
        }

        // Bases: praças de pedra em volta de cada Nexus; a fonte brilha no canto.
        for unit in sim.units where unit.role == .nexus {
            let plaza = SKShapeNode(circleOfRadius: 760)
            plaza.fillColor = Palette.base
            plaza.strokeColor = Palette.team(unit.team).withAlphaComponent(0.35)
            plaza.lineWidth = 10
            plaza.position = unit.position.scenePoint
            root.addChild(plaza)
        }
        if sim.hasFountains {
            for team in [Team.light, .shadow] {
                let fountain = SKShapeNode(circleOfRadius: FountainTuning.radius)
                fountain.fillColor = Palette.team(team).withAlphaComponent(0.18)
                fountain.strokeColor = Palette.team(team).withAlphaComponent(0.7)
                fountain.lineWidth = 6
                fountain.glowWidth = 4
                fountain.position = sim.spawnPoint(of: team).scenePoint
                root.addChild(fountain)
            }
        }

        // Rotas de terra batida.
        for lane in sim.lanes {
            let path = CGMutablePath()
            path.move(to: lane.waypoints[0].scenePoint)
            for point in lane.waypoints.dropFirst() { path.addLine(to: point.scenePoint) }
            root.addChild(stroke(path, width: 300, color: Palette.laneEdge))
            root.addChild(stroke(path, width: 230, color: Palette.lane))
        }

        // Altares das relíquias e portais do Véu.
        for relic in sim.relics {
            let altar = SKShapeNode(circleOfRadius: 120)
            altar.fillColor = SKColor(hex: 0x2A2440)
            altar.strokeColor = Palette.portal.withAlphaComponent(0.6)
            altar.lineWidth = 6
            altar.position = relic.position.scenePoint
            altar.name = "altar"
            root.addChild(altar)
        }
        for pair in sim.portals {
            for point in [pair.a, pair.b] { root.addChild(portal(at: point)) }
        }

        for obstacle in sim.map.obstacles { root.addChild(node(for: obstacle)) }

        let border = SKShapeNode(rect: CGRect(x: 0, y: -size.y, width: size.x, height: size.y))
        border.strokeColor = Palette.background
        border.lineWidth = 24
        border.fillColor = .clear
        root.addChild(border)
        return root
    }

    private static func stroke(_ path: CGPath, width: CGFloat, color: SKColor) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = .round
        node.lineJoin = .round
        node.fillColor = .clear
        return node
    }

    private static func portal(at point: Vec2) -> SKNode {
        let node = SKNode()
        node.position = point.scenePoint
        let ring = SKShapeNode(circleOfRadius: PortalTuning.radius)
        ring.fillColor = Palette.portal.withAlphaComponent(0.25)
        ring.strokeColor = Palette.portal
        ring.lineWidth = 6
        ring.glowWidth = 6
        node.addChild(ring)
        let inner = SKShapeNode(circleOfRadius: PortalTuning.radius * 0.55)
        inner.strokeColor = Palette.crystalEdge.withAlphaComponent(0.8)
        inner.lineWidth = 3
        inner.fillColor = .clear
        node.addChild(inner)
        inner.run(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.9), .scale(to: 0.8, duration: 0.9)])))
        ring.run(.repeatForever(.rotate(byAngle: .pi, duration: 3)))
        return node
    }

    private static func node(for obstacle: Obstacle) -> SKNode {
        switch obstacle {
        case .rect(let rect):
            let size = CGSize(width: rect.max.x - rect.min.x, height: rect.max.y - rect.min.y)
            let wall = SKShapeNode(rectOf: size, cornerRadius: 8)
            wall.fillColor = Palette.wall
            wall.strokeColor = Palette.wallEdge
            wall.lineWidth = 6
            wall.position = rect.center.scenePoint
            return wall
        case .circle(let circle):
            let node = SKShapeNode(circleOfRadius: circle.radius)
            node.position = circle.center.scenePoint
            if circle.radius >= 60 {
                // Bosque: copa de árvores.
                node.fillColor = Palette.tree
                node.strokeColor = SKColor(hex: 0x1C4428)
                node.lineWidth = 8
                let top = SKShapeNode(circleOfRadius: circle.radius * 0.5)
                top.fillColor = SKColor(hex: 0x2F7040)
                top.strokeColor = .clear
                top.position = CGPoint(x: -circle.radius * 0.2, y: circle.radius * 0.25)
                node.addChild(top)
            } else {
                // Pilar de cristal.
                node.fillColor = SKColor(hex: 0x3A3F55)
                node.strokeColor = Palette.crystal
                node.lineWidth = 3
                let shard = SKShapeNode(path: {
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: -circle.radius * 0.45, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: circle.radius * 1.9))
                    path.addLine(to: CGPoint(x: circle.radius * 0.45, y: 0))
                    path.closeSubpath()
                    return path
                }())
                shard.fillColor = Palette.crystal.withAlphaComponent(0.9)
                shard.strokeColor = Palette.crystalEdge
                node.addChild(shard)
            }
            return node
        }
    }
}
