#if os(iOS)
import SimCore
import SpriteKit
import UIKit

/// Controles de toque, como no Wild Rift (filhos da câmera, em pontos de tela, origem no centro):
///
/// - Esquerda: joystick *flutuante*, que nasce onde o polegar encosta.
/// - Direita: ataque (segurar mira sozinho no inimigo mais próximo) e Q/W/E/R em arco. Segurar uma
///   habilidade e arrastar mira; soltar conjura. Um toque rápido mira sozinho no inimigo mais próximo.
/// - Botão de retorno à base ao lado das habilidades.
/// - Toque no mundo: aliado = doar Fluxo; inimigo = atacar; chão = andar. Toque no minimapa = andar até lá.
@MainActor
final class MatchControls: SKNode {
    private let sim: Simulation
    private let minimap: Minimap
    /// Converte um ponto da tela (na cena) para o mundo; dado pela cena, que conhece a câmera.
    var sceneLocation: (UITouch) -> CGPoint = { _ in .zero }
    var onAttackPress: () -> Void = {}

    private let joystickBase = SKShapeNode(circleOfRadius: MatchControls.joystickRadius)
    private let joystickKnob = SKShapeNode(circleOfRadius: 26)
    private let attackButton = SKShapeNode(circleOfRadius: 54)
    private var skillButtons: [SKShapeNode] = []
    private var skillKeys: [SKLabelNode] = []
    private var skillCooldowns: [SKLabelNode] = []
    private let recallButton = SKShapeNode(circleOfRadius: 26)
    private let recallLabel = SKLabelNode(text: "B")

    private weak var joystickTouch: UITouch?
    private var joystickOrigin: CGPoint = .zero
    private weak var attackTouch: UITouch?
    private var skillTouch: (touch: UITouch, slot: Int, current: CGPoint)?
    private var taps: [ObjectIdentifier: (start: CGPoint, time: TimeInterval, moved: Bool)] = [:]
    private var viewport: CGSize = .zero
    private var safeInsets: UIEdgeInsets = .zero

    static let joystickRadius: CGFloat = 64
    private static let deadZone = 0.12
    private static let skillAngles: [CGFloat] = [180, 143, 106, 69].map { $0 * .pi / 180 }
    private static let skillDistance: CGFloat = 122
    private static let tapSlop: CGFloat = 18
    private static let tapMaxDuration: TimeInterval = 0.35
    private static let dragMinimum: CGFloat = 16
    /// Arrasto (pt) que leva a mira ao alcance máximo.
    private static let dragFullRange = 110.0
    private static let autoAimRange = 900.0
    private static let pickSlop: CGFloat = 28

    init(sim: Simulation, minimap: Minimap) {
        self.sim = sim
        self.minimap = minimap
        super.init()
        zPosition = Layer.hud

        joystickBase.fillColor = SKColor(white: 1, alpha: 0.08)
        joystickBase.strokeColor = SKColor(white: 1, alpha: 0.35)
        joystickBase.lineWidth = 3
        joystickBase.isHidden = true
        addChild(joystickBase)
        joystickKnob.fillColor = SKColor(white: 1, alpha: 0.45)
        joystickKnob.strokeColor = .clear
        joystickBase.addChild(joystickKnob)

        attackButton.fillColor = Palette.enemy.withAlphaComponent(0.45)
        attackButton.strokeColor = SKColor(white: 1, alpha: 0.7)
        attackButton.lineWidth = 3
        let swords = SKLabelNode(text: "⚔︎")
        swords.fontSize = 44
        swords.verticalAlignmentMode = .center
        attackButton.addChild(swords)
        addChild(attackButton)

        for slot in 0..<4 {
            let button = SKShapeNode(circleOfRadius: slot == 3 ? 36 : 32)
            button.fillColor = SKColor(hex: slot == 3 ? 0x3A1F5E : 0x1B2A4A, alpha: 0.85)
            button.strokeColor = Palette.crystalEdge
            button.lineWidth = 3
            let key = SKLabelNode(text: ["Q", "W", "E", "R"][slot])
            key.fontName = "AvenirNext-Heavy"
            key.fontSize = 20
            key.verticalAlignmentMode = .center
            key.fontColor = Palette.text
            button.addChild(key)
            let cooldown = SKLabelNode(text: "")
            cooldown.fontName = "AvenirNext-Heavy"
            cooldown.fontSize = 22
            cooldown.verticalAlignmentMode = .center
            cooldown.fontColor = .white
            button.addChild(cooldown)
            addChild(button)
            skillButtons.append(button)
            skillKeys.append(key)
            skillCooldowns.append(cooldown)
        }

        recallButton.fillColor = SKColor(hex: 0x1B2A4A, alpha: 0.85)
        recallButton.strokeColor = Palette.mana
        recallButton.lineWidth = 3
        recallLabel.fontName = "AvenirNext-Heavy"
        recallLabel.fontSize = 13
        recallLabel.text = "Base"
        recallLabel.verticalAlignmentMode = .center
        recallButton.addChild(recallLabel)
        addChild(recallButton)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    // MARK: Layout

    func layout(viewport: CGSize, insets: UIEdgeInsets) {
        self.viewport = viewport
        safeInsets = insets
        let attack = CGPoint(x: viewport.width / 2 - insets.right - 96, y: -viewport.height / 2 + insets.bottom + 96)
        attackButton.position = attack
        for (slot, button) in skillButtons.enumerated() {
            let angle = Self.skillAngles[slot]
            button.position = CGPoint(x: attack.x + cos(angle) * Self.skillDistance, y: attack.y + sin(angle) * Self.skillDistance)
        }
        // À esquerda do Q e mais baixo, fora do painel do herói (centro da tela).
        recallButton.position = CGPoint(x: attack.x - 190, y: attack.y - 52)
    }

    /// Cooldowns e mana nos botões (chamado a cada quadro).
    func refresh() {
        let hero = sim.hero
        for slot in 0..<4 {
            guard let ability = sim.ability(of: hero, slot: slot) else { continue }
            let cooldown = hero.abilityCooldowns[slot]
            let noMana = hero.mana < ability.manaCost
            skillCooldowns[slot].text = cooldown > 0 ? "\(Int(cooldown.rounded(.up)))" : ""
            skillKeys[slot].isHidden = cooldown > 0
            let ready = cooldown <= 0 && !noMana && hero.isAlive
            skillButtons[slot].strokeColor = ready ? (slot == 3 ? Palette.shadow : Palette.crystalEdge) : Palette.textDim
            skillButtons[slot].alpha = ready ? 1 : 0.6
            skillButtons[slot].setScale(skillTouch?.slot == slot ? 1.1 : 1)
        }
        recallButton.alpha = hero.recallRemaining != nil ? 1 : 0.85
        recallLabel.text = hero.recallRemaining.map { "\(Int($0.rounded(.up)))s" } ?? "Base"
        attackButton.alpha = attackTouch != nil ? 1 : 0.8
        attackButton.setScale(attackTouch != nil ? 0.94 : 1)
    }

    /// Habilidade sendo mirada, para o desenho da mira no mundo.
    var aimPreview: AimPreview? {
        guard let skillTouch else { return nil }
        return AimPreview(slot: skillTouch.slot, direction: dragDirection(skillTouch.slot, skillTouch.current))
    }

    // MARK: Toques

    func touchesBegan(_ touches: Set<UITouch>, minimapOrigin: CGPoint) {
        let hero = sim.localHero
        for touch in touches {
            let p = touch.location(in: self)
            if skillTouch == nil, let slot = skillSlot(at: p) {
                skillTouch = (touch, slot, p)
                continue
            }
            if distance(p, recallButton.position) <= 26 + Self.pickSlop {
                sim.submit(.recall, for: hero)
                continue
            }
            if attackTouch == nil, distance(p, attackButton.position) <= 54 * 1.35 {
                attackTouch = touch
                sim.setAttackHeld(true, for: hero)
                // Um toque rápido pode começar e terminar entre dois ticks: o comando garante o alvo.
                sim.submit(.attackNearest, for: hero)
                onAttackPress()
                continue
            }
            let local = CGPoint(x: p.x - minimapOrigin.x, y: p.y - minimapOrigin.y)
            if let world = minimap.worldPoint(at: local) {
                sim.submit(.moveTo(world), for: hero)
                continue
            }
            if joystickTouch == nil, p.x < -viewport.width * 0.08 {
                joystickTouch = touch
                joystickOrigin = p
                joystickBase.position = p
                joystickKnob.position = .zero
                joystickBase.isHidden = false
                continue
            }
            taps[ObjectIdentifier(touch)] = (p, touch.timestamp, false)
        }
    }

    func touchesMoved(_ touches: Set<UITouch>) {
        for touch in touches {
            let p = touch.location(in: self)
            if let skill = skillTouch, skill.touch === touch {
                skillTouch?.current = p
                continue
            }
            if touch === joystickTouch {
                // A base acompanha o dedo que passa da borda, para nunca ser preciso voltar o polegar.
                var pull = CGPoint(x: p.x - joystickOrigin.x, y: p.y - joystickOrigin.y)
                let length = hypot(pull.x, pull.y)
                if length > Self.joystickRadius {
                    joystickOrigin = CGPoint(x: p.x - pull.x / length * Self.joystickRadius, y: p.y - pull.y / length * Self.joystickRadius)
                    joystickBase.position = joystickOrigin
                    pull = CGPoint(x: p.x - joystickOrigin.x, y: p.y - joystickOrigin.y)
                }
                joystickKnob.position = pull
                // Tela com y para cima → mundo com y para baixo.
                let axis = JoystickMath.axis(for: Vec2(pull.x, -pull.y), radius: Self.joystickRadius, deadZone: Self.deadZone)
                // Como no Wild Rift: passou da zona morta, o campeão corre na velocidade máxima.
                sim.setMoveAxis(axis == .zero ? .zero : axis.normalized, for: sim.localHero)
                continue
            }
            if let tap = taps[ObjectIdentifier(touch)], distance(tap.start, p) > Self.tapSlop {
                taps[ObjectIdentifier(touch)]?.moved = true
            }
        }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches {
            if let skill = skillTouch, skill.touch === touch {
                release(slot: skill.slot, at: skill.current)
                skillTouch = nil
            } else if touch === joystickTouch {
                joystickTouch = nil
                joystickBase.isHidden = true
                sim.setMoveAxis(.zero, for: sim.localHero)
            } else if touch === attackTouch {
                attackTouch = nil
                sim.setAttackHeld(false, for: sim.localHero)
            } else if let tap = taps.removeValue(forKey: ObjectIdentifier(touch)),
                      !tap.moved, touch.timestamp - tap.time <= Self.tapMaxDuration {
                tapWorld(sceneLocation(touch).world)
            }
        }
    }

    func cancelAll() {
        joystickTouch = nil
        attackTouch = nil
        skillTouch = nil
        taps.removeAll()
        joystickBase.isHidden = true
        sim.setMoveAxis(.zero, for: sim.localHero)
        sim.setAttackHeld(false, for: sim.localHero)
    }

    // MARK: Ações

    private func skillSlot(at p: CGPoint) -> Int? {
        skillButtons.indices.first { distance(p, skillButtons[$0].position) <= (($0 == 3) ? 36 : 32) * 1.3 }
    }

    /// Mira do arrasto no mundo; `nil` se foi só um toque. O comprimento cresce com o arrasto
    /// (até o alcance da habilidade): é onde as áreas no chão vão cair.
    private func dragDirection(_ slot: Int, _ current: CGPoint) -> Vec2? {
        let origin = skillButtons[slot].position
        let drag = CGPoint(x: current.x - origin.x, y: current.y - origin.y)
        let length = hypot(drag.x, drag.y)
        guard length >= Self.dragMinimum else { return nil }
        let reach = sim.ability(of: sim.hero, slot: slot)?.reach ?? 0
        let fraction = min(Double(length) / Self.dragFullRange, 1)
        return Vec2(drag.x, -drag.y).normalized * max(reach * fraction, 2)
    }

    /// Toque simples mira sozinho no inimigo visível mais próximo; arrastar mira na mão.
    private func release(slot: Int, at current: CGPoint) {
        var direction = dragDirection(slot, current) ?? .zero
        if direction == .zero {
            let hero = sim.hero
            var nearest = Self.autoAimRange
            for unit in sim.units where unit.team != sim.localTeam && unit.isAlive && sim.isVisibleToLocalTeam(unit.id) {
                let d = hero.position.distance(to: unit.position)
                if d < nearest, !sim.isProtected(unit.id) {
                    nearest = d
                    // Vetor inteiro até o alvo: áreas no chão caem em cima dele.
                    direction = unit.position - hero.position
                }
            }
        }
        sim.submit(.cast(slot: slot, direction: direction), for: sim.localHero)
    }

    /// Toque num aliado doa Fluxo; num inimigo visível ataca; no chão anda com pathfinding.
    private func tapWorld(_ world: Vec2) {
        let hero = sim.localHero
        let slop = Double(Self.pickSlop) * 1.5
        for unit in sim.units where unit.isHero && unit.team == sim.localTeam && unit.id != hero && unit.isAlive {
            if world.distance(to: unit.position) - unit.radius <= slop {
                sim.submit(.donateFlux(to: unit.id), for: hero)
                return
            }
        }
        var best: (id: UnitID, gap: Double)?
        for unit in sim.units where unit.team != sim.localTeam && unit.isAlive && sim.isVisibleToLocalTeam(unit.id) {
            let gap = world.distance(to: unit.position) - unit.radius
            if gap <= slop, best == nil || gap < best!.gap { best = (unit.id, gap) }
        }
        if let best {
            sim.submit(.attack(best.id), for: hero)
        } else {
            sim.submit(.moveTo(world), for: hero)
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
#endif
