import SimCore
import SpriteKit

/// Desenha a partida: sincroniza um nó por unidade e por projétil com a simulação, interpolando
/// entre ticks, e mantém a névoa (uma textura de baixa resolução esticada sobre o mapa).
@MainActor
final class WorldRenderer {
    let root = SKNode()
    private let unitLayer = SKNode()
    private let projectileLayer = SKNode()
    private let effectLayer = SKNode()
    private let aimNode = SKShapeNode()
    private let fogSprite: SKSpriteNode
    private var altars: [SKShapeNode] = []
    private var unitNodes: [Int: UnitNode] = [:]
    private var projectileNodes: [Int: SKShapeNode] = [:]
    private var zoneNodes: [Int: SKShapeNode] = [:]
    private var fogVersion = -1
    private var fogPixels: [UInt8]

    init(sim: Simulation) {
        let terrain = Terrain.build(for: sim)
        root.addChild(terrain)
        altars = terrain.children.compactMap { $0.name == "altar" ? $0 as? SKShapeNode : nil }
        unitLayer.zPosition = 0
        root.addChild(unitLayer)
        projectileLayer.zPosition = Layer.projectiles
        root.addChild(projectileLayer)
        effectLayer.zPosition = Layer.effects
        root.addChild(effectLayer)
        aimNode.zPosition = Layer.decals
        aimNode.fillColor = Palette.crystal.withAlphaComponent(0.25)
        aimNode.strokeColor = Palette.crystalEdge.withAlphaComponent(0.8)
        aimNode.lineWidth = 2
        aimNode.isHidden = true
        root.addChild(aimNode)

        let fog = sim.fog
        fogPixels = [UInt8](repeating: 0, count: fog.cols * fog.rows * 4)
        fogSprite = SKSpriteNode(color: .clear, size: CGSize(width: Double(fog.cols) * fog.cellSize, height: Double(fog.rows) * fog.cellSize))
        fogSprite.anchorPoint = CGPoint(x: 0, y: 1)
        fogSprite.position = .zero
        fogSprite.zPosition = Layer.fog
        root.addChild(fogSprite)
    }

    // MARK: Quadro

    func render(_ sim: Simulation, alpha: Double, aim: AimPreview?) {
        renderUnits(sim, alpha: alpha)
        renderProjectiles(sim, alpha: alpha)
        renderZones(sim)
        renderFog(sim)
        renderAim(sim, aim, alpha: alpha)
        for (index, relic) in sim.relics.enumerated() where altars.indices.contains(index) {
            altars[index].strokeColor = relic.owner.map { Palette.team($0) } ?? Palette.portal.withAlphaComponent(0.6)
        }
    }

    private func renderUnits(_ sim: Simulation, alpha: Double) {
        let hero = sim.hero
        for unit in sim.units {
            let key = unit.id.rawValue
            guard unit.isAlive, sim.isKnownToLocalTeam(unit.id) else {
                unitNodes[key]?.isHidden = true
                continue
            }
            var node = unitNodes[key]
            if node == nil || node?.role != unit.role {
                // Lugar reaproveitado por outra unidade (esbirros): refaz o desenho.
                node?.removeFromParent()
                let ring: SKColor? = unit.isHero ? (unit.id == sim.localHero ? Palette.gold : unit.team == sim.localTeam ? Palette.ally : Palette.enemy) : nil
                let created = UnitNode(unit: unit, ringColor: ring, face: sim.visibleFace(unit.id), isLocal: unit.id == sim.localHero)
                unitLayer.addChild(created)
                unitNodes[key] = created
                node = created
            }
            guard let node else { continue }
            node.isHidden = false
            let at = unit.previousPosition + (unit.position - unit.previousPosition) * alpha
            let nearHero = unit.position.distance(to: hero.position) < (unit.attack?.range ?? 0) + 500
            node.update(unit, at: at, isTarget: hero.targetID == unit.id, isProtected: unit.isStructure && sim.isProtected(unit.id), inDanger: nearHero)
        }
    }

    private func renderProjectiles(_ sim: Simulation, alpha: Double) {
        var alive: Set<Int> = []
        for projectile in sim.projectiles {
            let at = projectile.previousPosition + (projectile.position - projectile.previousPosition) * alpha
            if projectile.team != sim.localTeam, !sim.fog.isVisible(at) { continue }
            alive.insert(projectile.id)
            let node = projectileNodes[projectile.id] ?? {
                let fromTower = sim.unit(projectile.source)?.isStructure == true
                let radius = projectile.isSkillshot ? projectile.hitRadius : (fromTower ? 16 : 8)
                let shape = SKShapeNode(circleOfRadius: radius)
                let tone = projectile.team == .light ? SKColor(hex: 0xFFF2B0) : SKColor(hex: 0xE0B0FF)
                shape.fillColor = tone
                shape.strokeColor = .white
                shape.lineWidth = projectile.isSkillshot ? 3 : 1
                shape.glowWidth = projectile.isSkillshot || fromTower ? 8 : 3
                projectileLayer.addChild(shape)
                projectileNodes[projectile.id] = shape
                return shape
            }()
            node.position = at.scenePoint
        }
        for (id, node) in projectileNodes where !alive.contains(id) {
            node.removeFromParent()
            projectileNodes[id] = nil
        }
    }

    /// Áreas de habilidade: círculo no chão enquanto durarem (as inimigas só se visíveis).
    private func renderZones(_ sim: Simulation) {
        var alive: Set<Int> = []
        for zone in sim.zones {
            if zone.team != sim.localTeam, !sim.fog.isVisible(zone.position) { continue }
            alive.insert(zone.id)
            let node = zoneNodes[zone.id] ?? {
                let shape = SKShapeNode(circleOfRadius: zone.radius)
                let tone = zone.team == sim.localTeam ? Palette.ally : Palette.enemy
                shape.fillColor = tone.withAlphaComponent(0.14)
                shape.strokeColor = tone.withAlphaComponent(0.8)
                shape.lineWidth = 4
                shape.zPosition = Layer.decals
                effectLayer.addChild(shape)
                zoneNodes[zone.id] = shape
                return shape
            }()
            node.position = zone.position.scenePoint
            // Pisca rápido no fim do atraso, avisando quem está dentro.
            node.alpha = zone.timer < 0.3 ? 1 : 0.6 + 0.3 * CGFloat(sin(zone.age * 8))
        }
        for (id, node) in zoneNodes where !alive.contains(id) {
            node.removeFromParent()
            zoneNodes[id] = nil
        }
    }

    /// Névoa: uma célula por pixel, refeita só quando a simulação recalcula a visão.
    private func renderFog(_ sim: Simulation) {
        let fog = sim.fog
        guard fog.version != fogVersion else { return }
        fogVersion = fog.version
        for row in 0..<fog.rows {
            // A textura começa embaixo; a grade da névoa, em cima.
            let textureRow = fog.rows - 1 - row
            for col in 0..<fog.cols {
                let alphaByte: UInt8 = switch fog.state(col: col, row: row) {
                case .visible: 0
                case .explored: 95
                case .hidden: 175
                }
                let i = (textureRow * fog.cols + col) * 4
                // RGBA pré-multiplicado com a cor da névoa (quase preta).
                fogPixels[i] = UInt8(10 * Int(alphaByte) / 255)
                fogPixels[i + 1] = UInt8(12 * Int(alphaByte) / 255)
                fogPixels[i + 2] = UInt8(28 * Int(alphaByte) / 255)
                fogPixels[i + 3] = alphaByte
            }
        }
        let texture = SKTexture(data: Data(fogPixels), size: CGSize(width: fog.cols, height: fog.rows))
        texture.filteringMode = .linear
        fogSprite.texture = texture
        fogSprite.color = .white
        fogSprite.colorBlendFactor = 0
    }

    private func renderAim(_ sim: Simulation, _ aim: AimPreview?, alpha: Double) {
        let hero = sim.hero
        guard let aim, hero.isAlive, let ability = sim.ability(of: hero, slot: aim.slot) else {
            aimNode.isHidden = true
            return
        }
        let origin = hero.previousPosition + (hero.position - hero.previousPosition) * alpha
        let path = CGMutablePath()
        let direction = aim.direction
        switch ability.effect {
        case let .nova(_, _, radius, _, _, _):
            path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        case .shield, .buff:
            path.addEllipse(in: CGRect(x: -hero.radius * 2.5, y: -hero.radius * 2.5, width: hero.radius * 5, height: hero.radius * 5))
        case let .skillshot(_, _, range, radius, _, _, _):
            path.addPath(Self.band(direction: direction, length: range, halfWidth: radius))
        case let .dash(distance, _, _, _, _):
            path.addPath(Self.band(direction: direction, length: distance, halfWidth: hero.radius))
        case let .blink(distance):
            if let direction, direction != .zero {
                let tip = (direction.normalized * distance).scenePoint
                path.addEllipse(in: CGRect(x: tip.x - hero.radius * 1.5, y: tip.y - hero.radius * 1.5, width: hero.radius * 3, height: hero.radius * 3))
                path.move(to: .zero)
                path.addLine(to: tip)
            } else {
                path.addEllipse(in: CGRect(x: -distance, y: -distance, width: distance * 2, height: distance * 2))
            }
        case let .cone(_, _, range, angle, _):
            let facing = direction.map { $0 == .zero ? hero.facing : $0.angle } ?? hero.facing
            path.move(to: .zero)
            path.addArc(center: .zero, radius: range, startAngle: SceneSpace.rotation(facing) - angle / 2,
                        endAngle: SceneSpace.rotation(facing) + angle / 2, clockwise: false)
            path.closeSubpath()
        case let .zone(_, _, range, radius, _, _, _, _, _, follow):
            let center: CGPoint
            if follow {
                center = .zero
            } else if let direction, direction != .zero {
                let length = direction.length > 1.5 ? min(direction.length, range) : range
                center = (direction.normalized * length).scenePoint
            } else {
                center = .zero
                path.addEllipse(in: CGRect(x: -range, y: -range, width: range * 2, height: range * 2))
            }
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        aimNode.path = path
        aimNode.position = origin.scenePoint
        aimNode.isHidden = false
    }

    /// Faixa da largura do projétil, na direção da mira (direção no mundo; vetor nulo = sem mira manual).
    private static func band(direction: Vec2?, length: Double, halfWidth: Double) -> CGPath {
        let path = CGMutablePath()
        guard let direction, direction != .zero else {
            path.addEllipse(in: CGRect(x: -length, y: -length, width: length * 2, height: length * 2))
            return path
        }
        let d = direction.normalized.scenePoint
        let n = CGPoint(x: -d.y * halfWidth, y: d.x * halfWidth)
        let tip = CGPoint(x: d.x * length, y: d.y * length)
        path.move(to: n)
        path.addLine(to: CGPoint(x: tip.x + n.x, y: tip.y + n.y))
        path.addLine(to: CGPoint(x: tip.x - n.x, y: tip.y - n.y))
        path.addLine(to: CGPoint(x: -n.x, y: -n.y))
        path.closeSubpath()
        return path
    }

    // MARK: Efeitos

    func play(_ events: [SimEvent], sim: Simulation) {
        for event in events {
            switch event {
            case .moveOrdered(let to):
                pulse(at: to, radius: 22, color: SKColor(hex: 0x8DFFB0), duration: 0.5)
            case let .damaged(target, _, _, position, _):
                guard sim.isVisibleToLocalTeam(target) else { continue }
                flash(at: position)
            case let .killed(target, _):
                if let unit = sim.unit(target), sim.fog.isVisible(unit.position) {
                    pulse(at: unit.position, radius: unit.radius * 3, color: Palette.crystalEdge, duration: 0.5)
                }
            case let .cast(unit, slot, position):
                guard let caster = sim.unit(unit), sim.isVisibleToLocalTeam(unit) else { continue }
                // Só a equipe vê a face; o inimigo conjura em branco.
                let face = sim.visibleFace(unit)
                let color: SKColor = face == .light ? Palette.light : face == .shadow ? Palette.shadow : .white
                if let ability = sim.ability(of: caster, slot: slot), case let .nova(_, _, radius, _, _, _) = ability.effect {
                    pulse(at: position, radius: radius, color: color, duration: 0.55, filled: true)
                } else {
                    pulse(at: position, radius: caster.radius * 2.5, color: color, duration: 0.3)
                }
            case let .zonePulse(position, radius, team):
                if team == sim.localTeam || sim.fog.isVisible(position) {
                    pulse(at: position, radius: radius, color: team == sim.localTeam ? Palette.ally : Palette.enemy, duration: 0.45, filled: true)
                }
            case let .donated(_, _, _, position):
                pulse(at: position, radius: 80, color: Palette.flux, duration: 0.9, filled: true)
            case let .teleported(_, from, to), let .recalled(_, from, to):
                pulse(at: from, radius: 90, color: Palette.portal, duration: 0.6, filled: true)
                pulse(at: to, radius: 90, color: Palette.portal, duration: 0.6, filled: true)
            case let .levelUp(unit, _):
                if let hero = sim.unit(unit), hero.team == sim.localTeam {
                    pulse(at: hero.position, radius: 70, color: Palette.gold, duration: 0.8)
                }
            case let .relicCaptured(relic, team):
                pulse(at: sim.relics[relic].position, radius: 260, color: Palette.team(team), duration: 1.2, filled: true)
            case let .structureDestroyed(id, _):
                if let unit = sim.unit(id) { pulse(at: unit.position, radius: 220, color: .orange, duration: 1, filled: true) }
            default:
                break
            }
        }
    }

    private func pulse(at point: Vec2, radius: Double, color: SKColor, duration: Double, filled: Bool = false) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = color
        ring.lineWidth = 5
        ring.fillColor = filled ? color.withAlphaComponent(0.2) : .clear
        ring.position = point.scenePoint
        ring.setScale(0.3)
        effectLayer.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: duration), .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }

    private func flash(at point: Vec2) {
        let spark = SKShapeNode(circleOfRadius: 12)
        spark.fillColor = .white
        spark.strokeColor = .clear
        spark.alpha = 0.8
        spark.position = Vec2(point.x, point.y - 40).scenePoint
        effectLayer.addChild(spark)
        spark.run(.sequence([.group([.scale(to: 2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }
}

/// Habilidade sendo mirada pelo jogador (botão segurado).
struct AimPreview {
    let slot: Int
    /// Direção no mundo; `nil` enquanto o dedo não arrastou o bastante (mira automática).
    let direction: Vec2?
}
