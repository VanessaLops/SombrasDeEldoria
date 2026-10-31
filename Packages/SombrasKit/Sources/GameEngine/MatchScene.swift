import SimCore
import SpriteKit
#if os(iOS)
import UIKit
#endif

/// Cena de uma partida. Pipeline por quadro (ordem importa):
///
///     simulação (passo fixo, 30 Hz) → eventos (efeitos, háptico, HUD) → desenho interpolado → câmera
public final class MatchScene: SKScene {
    let sim: Simulation
    /// Chamado a cada quadro com os eventos do quadro (a sessão monta o HUD a partir daqui).
    var onFrame: (([SimEvent]) -> Void)?
    var isSuspended = false {
        didSet { lastUpdateTime = nil }
    }

    private let renderer: WorldRenderer
    private let cameraNode = SKCameraNode()
    /// Tudo que fica em pontos de tela, preso à câmera.
    private let hud = SKNode()
    private let minimap: Minimap
    #if os(iOS)
    private let controls: MatchControls
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()
    #endif
    private var focus: Vec2
    private var lastUpdateTime: TimeInterval?
    private var minimapClock = 0.0
    /// Acelera o relógio da partida (só em DEBUG, com `-timescale N`, para testar o fim no Simulador).
    private let timeScale: Double = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-timescale"), arguments.indices.contains(index + 1),
           let value = Double(arguments[index + 1]), value > 0 {
            return value
        }
        #endif
        return 1
    }()

    /// Altura do mundo visível na tela, igual em qualquer aparelho.
    private static let visibleWorldHeight: CGFloat = 1000
    /// Segundos de movimento que a câmera antecipa e quão "grudada" ela segue o herói (1/s).
    private static let cameraLead = 0.3
    private static let cameraSharpness = 5.0

    init(sim: Simulation) {
        self.sim = sim
        renderer = WorldRenderer(sim: sim)
        minimap = Minimap(worldSize: sim.map.size)
        #if os(iOS)
        controls = MatchControls(sim: sim, minimap: minimap)
        #endif
        focus = sim.hero.position
        super.init(size: CGSize(width: 1024, height: 768))
        scaleMode = .resizeFill
        backgroundColor = Palette.background
        addChild(renderer.root)
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.addChild(hud)
        hud.addChild(minimap)
        #if os(iOS)
        hud.addChild(controls)
        controls.sceneLocation = { [unowned self] touch in touch.location(in: self) }
        controls.onAttackPress = { [unowned self] in impact.impactOccurred() }
        #endif
        cameraNode.position = focus.scenePoint
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        layoutForViewport()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutForViewport()
    }

    private func layoutForViewport() {
        guard size.height > 0 else { return }
        let scale = Self.visibleWorldHeight / size.height
        cameraNode.setScale(scale)
        // Os filhos da câmera não herdam o zoom: o HUD já fica em pontos de tela.
        #if os(iOS)
        let insets = view?.safeAreaInsets ?? .zero
        controls.layout(viewport: size, insets: insets)
        minimap.position = CGPoint(x: -size.width / 2 + insets.left + 12, y: size.height / 2 - insets.top - 12)
        #else
        minimap.position = CGPoint(x: -size.width / 2 + 12, y: size.height / 2 - 12)
        #endif
    }

    // MARK: Quadro

    public override func update(_ currentTime: TimeInterval) {
        guard !isSuspended else { return }
        let delta = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime

        let alpha = sim.advance(by: delta * timeScale)
        let events = sim.drainEvents()
        renderer.play(events, sim: sim)
        #if os(iOS)
        haptics(for: events)
        controls.refresh()
        renderer.render(sim, alpha: alpha, aim: controls.aimPreview)
        #else
        renderer.render(sim, alpha: alpha, aim: nil)
        #endif
        followHero(alpha: alpha, delta: delta)

        minimapClock += delta
        if minimapClock >= 0.15 {
            minimapClock = 0
            let scale = Double(cameraNode.xScale)
            minimap.update(sim, cameraCenter: cameraNode.position.world, viewSize: CGSize(width: size.width * scale, height: size.height * scale))
        }
        onFrame?(events)
    }

    /// A câmera segue com atraso suave e olha um pouco à frente de para onde o herói anda,
    /// presa aos limites do mapa. Saltos grandes (renascer, portal, retorno) vão direto.
    private func followHero(alpha: Double, delta: Double) {
        let hero = sim.hero
        let at = hero.previousPosition + (hero.position - hero.previousPosition) * alpha
        let velocity = (hero.position - hero.previousPosition) / Simulation.tickInterval
        let target = at + velocity * Self.cameraLead
        if focus.distance(to: target) > 900 {
            focus = target
        } else {
            focus += (target - focus) * (1 - exp(-Self.cameraSharpness * delta))
        }
        let scale = Double(cameraNode.xScale)
        let half = Vec2(size.width * scale / 2, size.height * scale / 2)
        let map = sim.map.size
        let clamped = Vec2(
            map.x > half.x * 2 ? min(max(focus.x, half.x), map.x - half.x) : map.x / 2,
            map.y > half.y * 2 ? min(max(focus.y, half.y), map.y - half.y) : map.y / 2
        )
        cameraNode.position = clamped.scenePoint
    }

    #if os(iOS)
    private func haptics(for events: [SimEvent]) {
        for event in events {
            switch event {
            case let .killed(target, killer):
                if killer == sim.localHero, sim.unit(target)?.isHero == true { notify.notificationOccurred(.success) }
                if target == sim.localHero { notify.notificationOccurred(.error) }
            case .levelUp(let unit, _) where unit == sim.localHero:
                impact.impactOccurred(intensity: 0.7)
            case .matchEnded:
                notify.notificationOccurred(.success)
            default:
                break
            }
        }
    }

    // MARK: Toques

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controls.touchesBegan(touches, minimapOrigin: minimap.position)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        controls.touchesMoved(touches)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        controls.touchesEnded(touches)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        controls.touchesEnded(touches)
    }

    func cancelTouches() {
        controls.cancelAll()
    }
    #endif
}
