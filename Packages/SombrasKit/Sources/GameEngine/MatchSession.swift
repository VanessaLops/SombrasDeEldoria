import Observation
import SimCore

/// O que o jogador escolheu no lobby e na seleção de campeão.
public struct MatchSetup: Sendable, Hashable {
    public let mode: GameMode
    public let hero: HeroID
    public let face: Face
    public let seed: UInt64
    /// O herói do jogador também é controlado por bot (demonstração e testes no Simulador).
    public let autopilot: Bool

    public init(mode: GameMode, hero: HeroID, face: Face, seed: UInt64 = .random(in: 1 ... .max), autopilot: Bool = false) {
        self.mode = mode
        self.hero = hero
        self.face = face
        self.seed = seed
        self.autopilot = autopilot
    }
}

/// Retrato do estado para o HUD do SwiftUI (atualizado algumas vezes por segundo, não a cada quadro).
public struct MatchHUD: Sendable, Equatable {
    public var health = 0.0
    public var maxHealth = 1.0
    public var mana = 0.0
    public var maxMana = 1.0
    public var flux = 0.0
    public var donationsLeft = FluxTuning.maxDonations
    public var hasteRemaining = 0.0
    public var level = 1
    public var xpFraction = 0.0
    public var gold = 0
    public var kills = 0
    public var deaths = 0
    public var creeps = 0
    public var lightKills = 0
    public var shadowKills = 0
    public var time = 0.0
    public var isAlive = true
    public var respawnIn = 0.0
    public var trainingKills = 0
    /// Dono de cada relíquia (`nil` = ninguém), na ordem do cenário.
    public var relicOwners: [Team?] = []
    public var hasConvergence = false
    public var enemyHasConvergence = false
    public var fps = 0.0
}

/// Uma linha do registro de abates e objetivos.
public struct FeedLine: Sendable, Identifiable, Equatable {
    public enum Tone: Sendable { case ally, enemy, neutral, gold }
    public let id: Int
    public let text: String
    public let tone: Tone
    let expires: Double
}

/// Resultado final para o app gravar na conta.
public struct MatchOutcome: Sendable, Equatable {
    public let summary: MatchSummary
    /// Face liberada ao concluir o Treino (só para heróis que liberam pelo Treino).
    public let unlockedFace: Face?
}

/// Estado observável de uma partida para a UI e dona da cena.
///
/// A UI lê daqui e chama os métodos públicos; ela nunca fala direto com a simulação.
@MainActor
@Observable
public final class MatchSession {
    public let setup: MatchSetup
    public let definition: HeroDefinition
    /// Rota sugerida ao jogador no modo Normal.
    public let post: Post?
    public let relicNames: [String]
    public let lineup: Lineup?
    public private(set) var hud = MatchHUD()
    public private(set) var feed: [FeedLine] = []
    /// Preenchido uma única vez: vitória/derrota no Normal ou Treino concluído.
    public private(set) var outcome: MatchOutcome?
    public private(set) var winner: Team?
    public private(set) var isPaused = false
    @ObservationIgnored public let scene: MatchScene
    @ObservationIgnored private let sim: Simulation
    @ObservationIgnored private var hudClock = 0.0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var lastFrameTime = 0.0
    @ObservationIgnored private var nextFeedID = 0
    @ObservationIgnored private var isAppActive = true

    private static let hudInterval = 0.15
    private static let feedDuration = 6.0

    public init(setup: MatchSetup) {
        self.setup = setup
        definition = HeroDefinition.definition(for: setup.hero)
        switch setup.mode {
        case .normal, .ranked:
            let lineup = Lineup.random(player: setup.hero, seed: setup.seed)
            self.lineup = lineup
            sim = Simulation(scenario: .aetheria, hero: setup.hero, face: setup.face, options: MatchOptions(lineup: lineup, autopilot: setup.autopilot))
            post = Lineup.playerPost
        case .training:
            lineup = nil
            sim = Simulation(scenario: .trainingGrounds, hero: setup.hero, face: setup.face)
            post = nil
        }
        relicNames = sim.relics.map(\.name)
        scene = MatchScene(sim: sim)
        scene.onFrame = { [weak self] events in self?.frame(events) }
        refreshHUD()
    }

    public var abilities: [AbilityDefinition] { definition.abilities(setup.face) }
    public var isOver: Bool { winner != nil }

    // MARK: Controle

    public func pause() {
        isPaused = true
        applySuspension()
    }

    public func resume() {
        isPaused = false
        applySuspension()
    }

    /// Chamado pela UI quando o app entra/sai de primeiro plano.
    public func setAppActive(_ active: Bool) {
        isAppActive = active
        applySuspension()
    }

    private func applySuspension() {
        scene.isSuspended = isPaused || !isAppActive || winner != nil
        #if os(iOS)
        if scene.isSuspended { scene.cancelTouches() }
        #endif
    }

    /// Saída antes do fim: recompensa parcial se jogou o mínimo (e ainda não recebeu nada).
    public func leaveEarly() -> MatchOutcome? {
        guard outcome == nil, sim.time >= Account.minimumPlayForReward else { return nil }
        let partial = MatchOutcome(
            summary: MatchSummary(mode: setup.mode, won: false, completed: false, durationSeconds: sim.time, creeps: sim.stats.creeps),
            unlockedFace: nil
        )
        outcome = partial
        return partial
    }

    // MARK: Quadro

    private func frame(_ events: [SimEvent]) {
        for event in events { record(event) }
        if winner == nil, let won = sim.winner {
            winner = won
            outcome = MatchOutcome(
                summary: MatchSummary(mode: setup.mode, won: won == sim.localTeam, completed: true, durationSeconds: sim.time, creeps: sim.stats.creeps),
                unlockedFace: nil
            )
            applySuspension()
        }
        // Treino: a meta de abates conclui o Treino (e libera a outra face de quem libera por ele).
        if setup.mode == .training, outcome == nil, sim.hero.kills >= DummyTuning.trainingGoal {
            outcome = MatchOutcome(
                summary: MatchSummary(mode: .training, won: true, completed: true, durationSeconds: sim.time, creeps: sim.stats.creeps),
                unlockedFace: definition.otherFaceUnlockedByTraining ? setup.face.other : nil
            )
        }

        let now = sim.time
        frames += 1
        hudClock += max(0, now - lastFrameTime)
        lastFrameTime = now
        if hudClock >= Self.hudInterval || winner != nil {
            refreshHUD()
            feed.removeAll { $0.expires < now }
            hudClock = 0
            frames = 0
        }
    }

    private func refreshHUD() {
        let hero = sim.hero
        let toNext = sim.xpToNextLevel(of: hero)
        let measured = hudClock > 0 ? Double(frames) / hudClock : hud.fps
        hud = MatchHUD(
            health: hero.health, maxHealth: hero.maxHealth, mana: hero.mana, maxMana: max(hero.maxMana, 1),
            flux: hero.flux, donationsLeft: FluxTuning.maxDonations - hero.donationsMade, hasteRemaining: hero.hasteRemaining,
            level: hero.level, xpFraction: toNext > 0 ? hero.xp / toNext : 1, gold: Int(sim.stats.gold),
            kills: sim.stats.kills, deaths: sim.stats.deaths, creeps: sim.stats.creeps,
            lightKills: sim.teamKills[.light] ?? 0, shadowKills: sim.teamKills[.shadow] ?? 0,
            time: sim.time, isAlive: hero.isAlive, respawnIn: hero.respawnRemaining, trainingKills: hero.kills,
            relicOwners: sim.relics.map(\.owner),
            hasConvergence: !sim.relics.isEmpty && sim.hasConvergence(sim.localTeam),
            enemyHasConvergence: !sim.relics.isEmpty && sim.hasConvergence(sim.localTeam.opponent),
            fps: measured
        )
    }

    private func record(_ event: SimEvent) {
        switch event {
        case let .killed(target, killer):
            guard let victim = sim.unit(target), victim.isHero else { return }
            let killerUnit = sim.unit(killer)
            let by = killerUnit.map { $0.isHero ? $0.name : $0.isStructure ? "uma torre" : "esbirros" } ?? "?"
            let mine = victim.team != sim.localTeam
            let you = target == sim.localHero ? "Você foi abatido por \(by)" : killer == sim.localHero ? "Você abateu \(victim.name)!" : "\(by) abateu \(victim.name)"
            push(you, tone: mine ? .ally : .enemy)
        case let .structureDestroyed(id, team):
            guard let unit = sim.unit(id), unit.role != .nexus else { return }
            push(team == sim.localTeam ? "Uma torre aliada caiu" : "Torre inimiga destruída!", tone: team == sim.localTeam ? .enemy : .ally)
        case let .relicCaptured(relic, team):
            let name = sim.relics[relic].name
            push(team == sim.localTeam ? "Relíquia dominada: \(name)" : "Inimigos dominaram \(name)", tone: team == sim.localTeam ? .gold : .enemy)
            if team == sim.localTeam, sim.relicsOwned(by: team) == RelicTuning.needed {
                push("CONVERGÊNCIA! O Nexus inimigo está aberto.", tone: .gold)
            }
        case let .levelUp(unit, level) where unit == sim.localHero:
            push("Nível \(level)!", tone: .gold)
        case let .donated(from, to, amount, _):
            if from == sim.localHero, let receiver = sim.unit(to) {
                push("Fluxo doado a \(receiver.name) (+\(Int(amount)))", tone: .ally)
            } else if to == sim.localHero, let donor = sim.unit(from) {
                push("\(donor.name) doou Fluxo a você (+\(Int(amount)))", tone: .ally)
            }
        default:
            break
        }
    }

    private func push(_ text: String, tone: FeedLine.Tone) {
        feed.append(FeedLine(id: nextFeedID, text: text, tone: tone, expires: sim.time + Self.feedDuration))
        nextFeedID += 1
        if feed.count > 5 { feed.removeFirst(feed.count - 5) }
    }
}
