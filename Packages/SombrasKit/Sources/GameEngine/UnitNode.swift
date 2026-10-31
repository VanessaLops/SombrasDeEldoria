import SimCore
import SpriteKit

/// Desenho de uma unidade. Criado uma vez por unidade (ou quando o lugar é reaproveitado por outra)
/// e atualizado a cada quadro; nada é recriado no caminho quente.
final class UnitNode: SKNode {
    let role: UnitRole
    private let body = SKNode()
    private let facingMarker: SKShapeNode?
    private let ring: SKShapeNode?
    private let shieldBubble: SKShapeNode?
    private let recallRing: SKShapeNode?
    private let protectedRing: SKShapeNode?
    private let rangeRing: SKShapeNode?
    private let targetRing: SKShapeNode
    private let bars = SKNode()
    private let healthFill: SKSpriteNode
    private let manaFill: SKSpriteNode?
    private let levelLabel: SKLabelNode?
    private let barWidth: CGFloat
    private let statusRing = SKShapeNode(ellipseOf: CGSize(width: 64, height: 22))
    private let isHero: Bool
    private var lastPosition: Vec2?
    private var stride = 0.0

    /// - Parameters:
    ///   - ringColor: cor do anel no chão (você, aliado ou inimigo); `nil` para quem não tem anel.
    ///   - face: face visível para o time local (`nil` para inimigos: a face é segredo).
    init(unit: SimCore.Unit, ringColor: SKColor?, face: Face?, isLocal: Bool) {
        role = unit.role
        let radius = CGFloat(unit.radius)
        var marker: SKShapeNode?
        var ringNode: SKShapeNode?
        var shield: SKShapeNode?
        var recall: SKShapeNode?
        var protected: SKShapeNode?
        var range: SKShapeNode?
        var label: SKLabelNode?
        var figureHeight: CGFloat = 0
        let width: CGFloat

        switch unit.role {
        case .hero(let id):
            width = 90
            // Figura desenhada do campeão (o inimigo vê o visual neutro: a face é segredo).
            let scale = CGFloat((unit.radius / 18).squareRoot())
            let figure = SKNode()
            figure.xScale = scale
            figure.yScale = -scale
            figure.position = CGPoint(x: -HeroArt.width / 2 * scale, y: HeroArt.height * scale)
            for part in HeroArt.parts(id, face: face) {
                let shape = SKShapeNode(path: part.path)
                shape.fillColor = part.fill.flatMap { SKColor(cgColor: $0) as SKColor? } ?? .clear
                shape.strokeColor = part.stroke.flatMap { SKColor(cgColor: $0) as SKColor? } ?? .clear
                shape.lineWidth = part.lineWidth
                shape.lineJoin = .round
                shape.lineCap = .round
                figure.addChild(shape)
            }
            body.addChild(figure)
            figureHeight = HeroArt.height * scale
            if let ringColor {
                let r = SKShapeNode(ellipseOf: CGSize(width: 70 * scale, height: 22 * scale))
                r.strokeColor = ringColor
                r.lineWidth = isLocal ? 5 : 4
                r.fillColor = ringColor.withAlphaComponent(0.12)
                ringNode = r
            }
            let bubble = SKShapeNode(ellipseOf: CGSize(width: 80, height: 130))
            bubble.position = CGPoint(x: 0, y: 58)
            bubble.fillColor = Palette.crystal.withAlphaComponent(0.15)
            bubble.strokeColor = Palette.crystalEdge.withAlphaComponent(0.85)
            bubble.lineWidth = 3
            bubble.isHidden = true
            shield = bubble
            let recallNode = SKShapeNode(circleOfRadius: radius * 2.4)
            recallNode.strokeColor = Palette.mana
            recallNode.lineWidth = 5
            recallNode.fillColor = Palette.mana.withAlphaComponent(0.12)
            recallNode.isHidden = true
            recall = recallNode
            let levelNode = SKLabelNode(text: "1")
            levelNode.fontName = "AvenirNext-Bold"
            levelNode.fontSize = 15
            levelNode.fontColor = Palette.text
            levelNode.verticalAlignmentMode = .center
            levelNode.horizontalAlignmentMode = .right
            label = levelNode
            if isLocal, let attack = unit.attack {
                let reach = SKShapeNode(circleOfRadius: attack.range)
                reach.strokeColor = Palette.light.withAlphaComponent(0.18)
                reach.lineWidth = 2
                reach.fillColor = .clear
                range = reach
            }
        case .minion(let kind):
            width = 44
            let shape = kind == .guardian
                ? SKShapeNode(rectOf: CGSize(width: radius * 2, height: radius * 2), cornerRadius: 4)
                : SKShapeNode(path: Self.diamond(radius * 1.3))
            shape.fillColor = Palette.team(unit.team)
            shape.strokeColor = SKColor(white: 0.05, alpha: 1)
            shape.lineWidth = 2
            body.addChild(shape)
            let pointer = SKShapeNode(path: Self.triangle(length: radius * 0.8, width: radius * 0.6))
            pointer.fillColor = SKColor(white: 0.1, alpha: 0.8)
            pointer.strokeColor = .clear
            marker = pointer
        case .tower:
            width = 120
            let base = SKShapeNode(rectOf: CGSize(width: radius * 2.2, height: radius * 2.2), cornerRadius: 10)
            base.fillColor = SKColor(hex: 0x555B70)
            base.strokeColor = SKColor(hex: 0x2F3242)
            base.lineWidth = 5
            body.addChild(base)
            let crystal = SKShapeNode(path: Self.diamond(radius * 0.9))
            crystal.fillColor = Palette.team(unit.team)
            crystal.strokeColor = .white
            crystal.lineWidth = 2
            crystal.glowWidth = 6
            body.addChild(crystal)
            protected = Self.barrier(radius * 2)
            if let attack = unit.attack, unit.team != .light {
                let reach = SKShapeNode(circleOfRadius: attack.range)
                reach.strokeColor = Palette.enemy.withAlphaComponent(0.35)
                reach.lineWidth = 4
                reach.fillColor = .clear
                range = reach
            }
        case .nexus:
            width = 180
            let base = SKShapeNode(circleOfRadius: radius)
            base.fillColor = SKColor(hex: 0x4A4F63)
            base.strokeColor = Palette.team(unit.team)
            base.lineWidth = 8
            body.addChild(base)
            let crystal = SKShapeNode(path: Self.diamond(radius * 0.8))
            crystal.fillColor = Palette.team(unit.team)
            crystal.strokeColor = .white
            crystal.lineWidth = 3
            crystal.glowWidth = 10
            body.addChild(crystal)
            crystal.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 8)))
            protected = Self.barrier(radius * 1.6)
        case .monster(let kind):
            width = kind == .relic ? 120 : 60
            let shape = SKShapeNode(circleOfRadius: radius)
            shape.fillColor = kind == .relic ? Palette.portal : (kind == .beast ? SKColor(hex: 0x5A4632) : SKColor(hex: 0x7A6A4A))
            shape.strokeColor = kind == .relic ? Palette.crystalEdge : SKColor(hex: 0x2A2014)
            shape.lineWidth = kind == .relic ? 4 : 2
            if kind == .relic { shape.glowWidth = 8 }
            body.addChild(shape)
            let pointer = SKShapeNode(path: Self.triangle(length: radius * 0.8, width: radius * 0.7))
            pointer.fillColor = SKColor(hex: 0xE8DCC0)
            pointer.strokeColor = .clear
            marker = pointer
        case .trainingDummy:
            width = 90
            for (r, color) in [(radius, Palette.dummy), (radius * 0.66, SKColor.white), (radius * 0.4, Palette.enemy)] {
                let disc = SKShapeNode(circleOfRadius: r)
                disc.fillColor = color
                disc.strokeColor = SKColor(hex: 0x6B4A2A)
                disc.lineWidth = 2
                body.addChild(disc)
            }
        case .sentinel:
            width = 90
            let shape = SKShapeNode(path: Self.diamond(radius * 1.2))
            shape.fillColor = SKColor(hex: 0x4A4F63)
            shape.strokeColor = Palette.enemy
            shape.lineWidth = 3
            body.addChild(shape)
            let eye = SKShapeNode(circleOfRadius: radius * 0.35)
            eye.fillColor = Palette.enemy
            eye.strokeColor = .clear
            eye.glowWidth = 4
            body.addChild(eye)
        }

        let target = SKShapeNode(circleOfRadius: radius * 1.5 + 14)
        target.strokeColor = Palette.enemy
        target.lineWidth = 5
        target.fillColor = .clear
        target.isHidden = true
        targetRing = target

        let height: CGFloat = width < 60 ? 6 : 9
        let back = SKSpriteNode(color: SKColor(white: 0, alpha: 0.7), size: CGSize(width: width + 4, height: height + 4 + (unit.maxMana > 0 ? height - 2 : 0)))
        back.anchorPoint = CGPoint(x: 0.5, y: 1)
        back.position = CGPoint(x: 0, y: 2)
        bars.addChild(back)
        let hpColor: SKColor = isLocal || unit.team == .light ? Palette.hp : (unit.team == .neutral ? Palette.monster : Palette.enemy)
        healthFill = SKSpriteNode(color: hpColor, size: CGSize(width: width, height: height))
        healthFill.anchorPoint = CGPoint(x: 0, y: 1)
        healthFill.position = CGPoint(x: -width / 2, y: 0)
        bars.addChild(healthFill)
        if unit.maxMana > 0 {
            let mana = SKSpriteNode(color: Palette.mana, size: CGSize(width: width, height: height - 3))
            mana.anchorPoint = CGPoint(x: 0, y: 1)
            mana.position = CGPoint(x: -width / 2, y: -height - 1)
            bars.addChild(mana)
            manaFill = mana
        } else {
            manaFill = nil
        }
        if let label {
            label.position = CGPoint(x: -width / 2 - 6, y: -height / 2)
            bars.addChild(label)
        }
        bars.position = CGPoint(x: 0, y: figureHeight > 0 ? figureHeight + 14 : radius * 1.6 + 30)
        bars.zPosition = Layer.bars

        facingMarker = marker
        ring = ringNode
        shieldBubble = shield
        recallRing = recall
        protectedRing = protected
        rangeRing = range
        levelLabel = label
        barWidth = width
        isHero = unit.isHero
        super.init()
        statusRing.lineWidth = 4
        statusRing.fillColor = .clear
        statusRing.isHidden = true
        statusRing.zPosition = 0.02
        addChild(statusRing)

        for decal in [range, ringNode, target] {
            if let decal {
                decal.zPosition = Layer.decals - Layer.units
                addChild(decal)
            }
        }
        if let marker {
            marker.zPosition = -0.01
            addChild(marker)
        }
        addChild(body)
        for overlay in [shield, recall, protected] {
            if let overlay { addChild(overlay) }
        }
        addChild(bars)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    func update(_ unit: SimCore.Unit, at position: Vec2, isTarget: Bool, isProtected: Bool, inDanger: Bool) {
        self.position = position.scenePoint
        zPosition = SceneSpace.depth(position.y)
        if isHero {
            // Olha para o lado em que anda; balança a cada passo.
            body.xScale = cos(unit.facing) < -0.05 ? -1 : 1
            if let lastPosition { stride += lastPosition.distance(to: position) }
            lastPosition = position
            body.position.y = CGFloat(abs(sin(stride / 22))) * 4
            // Invisível: só o próprio time vê, e transparente.
            alpha = unit.isStealthed ? 0.4 : 1
        }
        if unit.isStunned {
            statusRing.isHidden = false
            statusRing.strokeColor = SKColor(hex: 0xFFE04A)
            statusRing.position = CGPoint(x: 0, y: (isHero ? 140 : unit.radius * 2 + 20))
            statusRing.zRotation += 0.2
        } else if unit.rootRemaining > 0 {
            statusRing.isHidden = false
            statusRing.strokeColor = SKColor(hex: 0x5BD68A)
            statusRing.position = .zero
            statusRing.zRotation = 0
        } else if unit.slowRemaining > 0 {
            statusRing.isHidden = false
            statusRing.strokeColor = SKColor(hex: 0x8AD0FF, alpha: 0.8)
            statusRing.position = .zero
            statusRing.zRotation = 0
        } else {
            statusRing.isHidden = true
        }
        if let facingMarker {
            let reach = unit.radius * (unit.isHero ? 1.35 : 1)
            facingMarker.position = Vec2(angle: unit.facing, length: reach).scenePoint
            facingMarker.zRotation = SceneSpace.rotation(unit.facing)
        }
        healthFill.xScale = CGFloat(max(0, min(1, unit.healthFraction)))
        manaFill?.xScale = CGFloat(max(0, min(1, unit.manaFraction)))
        // Monstros só mostram a vida depois de apanhar.
        bars.isHidden = unit.isMonster && unit.health >= unit.maxHealth
        levelLabel?.text = "\(unit.level)"
        shieldBubble?.isHidden = unit.shield <= 0
        if let recallRing {
            if let remaining = unit.recallRemaining {
                recallRing.isHidden = false
                let progress = 1 - remaining / RecallTuning.duration
                recallRing.setScale(CGFloat(0.4 + 0.6 * progress))
            } else {
                recallRing.isHidden = true
            }
        }
        protectedRing?.isHidden = !isProtected
        targetRing.isHidden = !isTarget
        // Alcance da torre só aparece com o herói por perto.
        if case .tower = unit.role { rangeRing?.isHidden = !inDanger }
    }

    // MARK: Formas

    private static func triangle(length: CGFloat, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: length, y: 0))
        path.addLine(to: CGPoint(x: 0, y: width / 2))
        path.addLine(to: CGPoint(x: 0, y: -width / 2))
        path.closeSubpath()
        return path
    }

    private static func diamond(_ r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: r))
        path.addLine(to: CGPoint(x: r * 0.7, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -r))
        path.addLine(to: CGPoint(x: -r * 0.7, y: 0))
        path.closeSubpath()
        return path
    }

    private static func barrier(_ r: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: r)
        node.fillColor = Palette.crystalEdge.withAlphaComponent(0.08)
        node.strokeColor = Palette.crystalEdge.withAlphaComponent(0.6)
        node.lineWidth = 4
        node.isHidden = true
        return node
    }
}
