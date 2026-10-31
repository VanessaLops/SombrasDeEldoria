import Foundation

/// Comandos pontuais (o movimento analógico e o "segurar ataque" são estado).
/// O jogador e os bots usam exatamente os mesmos comandos.
public enum Command: Sendable, Equatable {
    /// Ir até um ponto, com pathfinding.
    case moveTo(Vec2)
    /// Atacar um alvo específico (perseguindo se preciso).
    case attack(UnitID)
    /// Botão de ataque: escolhe o inimigo visível mais próximo.
    case attackNearest
    /// Conjura a habilidade `slot` (0 = Q … 3 = R) na direção dada (vetor nulo = direção atual).
    case cast(slot: Int, direction: Vec2)
    /// Doa parte do Fluxo a um aliado (no máximo duas vezes por partida).
    case donateFlux(to: UnitID)
    /// Canaliza o retorno à base; mover-se, agir ou apanhar cancela.
    case recall
    /// Compra um item (só na base ou morto); a receita usa os componentes que o campeão já tem.
    case buy(ItemID)
    /// Vende o item do espaço `slot` por parte do preço.
    case sell(slot: Int)
    case stop
}

/// Estado de uma Relíquia durante a partida: quem a domina e qual unidade é o seu guardião.
public struct RelicState: Sendable {
    public let kind: RelicKind
    public let name: String
    public let position: Vec2
    public internal(set) var owner: Team?
    public let guardian: UnitID
}

/// Como montar a partida além do cenário.
public struct MatchOptions: Sendable {
    /// Heróis controlados por bots: aliados (time da Luz) e inimigos (Sombra).
    public var lineup: Lineup?
    /// O herói local também é controlado por bot (partidas sem interface, testes de equilíbrio).
    public var autopilot = false

    public init(lineup: Lineup? = nil, autopilot: Bool = false) {
        self.lineup = lineup
        self.autopilot = autopilot
    }
}

/// Simulação determinística em passo fixo. Não conhece SpriteKit, SwiftUI nem relógio:
/// quem a usa (cliente, servidor, bot) chama `advance(by:)` e lê o estado.
public final class Simulation {
    public static let tickRate = 30.0
    public static let tickInterval = 1.0 / tickRate

    /// Tempo de simulação acumulado, em segundos.
    public private(set) var time = 0.0
    public internal(set) var units: [Unit] = []
    public private(set) var projectiles: [Projectile] = []
    /// Áreas de habilidade ativas.
    public private(set) var zones: [Zone] = []
    public private(set) var stats = MatchStats()
    /// Abates de heróis por time (placar).
    public private(set) var teamKills: [Team: Int] = [.light: 0, .shadow: 0]
    public internal(set) var relics: [RelicState] = []
    /// Time vencedor, quando o Nexus de alguém cai. A simulação congela depois disso.
    public private(set) var winner: Team?
    public let map: ArenaMap
    public let lanes: [Lane]
    public let portals: [Scenario.PortalPair]
    public let hasFountains: Bool
    public let localHero: UnitID
    public let localTeam: Team = .light
    /// Névoa do time local (inclui o que aliados, esbirros e torres enxergam).
    public let fog: FogOfWar

    private let nav: NavGrid
    private var pendingEvents: [SimEvent] = []
    private var pendingCommands: [(unit: UnitID, command: Command)] = []
    private var accumulator = 0.0
    private var nextProjectileID = 0
    private var nextZoneID = 0
    private var firstBloodTaken = false
    private var ticksSinceFog = 0
    private var nextWaveAt = WaveTuning.first
    private var spawns: [Team: Vec2] = [:]
    private var nexusIDs: [Team: UnitID] = [:]
    /// Torres de base de cada time, por rota (para reforçar as ondas de quem as derrubou).
    private var baseTowers: [Team: [Int: UnitID]] = [.light: [:], .shadow: [:]]
    var bots: [BotBrain] = []
    /// Olhos de cada time no tick atual (visão dos bots inimigos, que não usam a névoa local).
    private var eyesCache: (tick: Int, team: Team, eyes: [(Vec2, Double)])?
    private var tickCount = 0

    private static let navCellSize = 40.0
    private static let fogCellSize = 40.0
    private static let fogEveryTicks = 4
    private static let repathInterval = 0.3
    private static let arrivalDistance = 6.0
    private static let turnRate = 14.0
    /// O auto-alvo do botão de ataque olha um pouco além do alcance (o herói se aproxima).
    private static let acquireMargin = 220.0
    private static let botSpawnRing = 75.0

    public init(
        scenario: Scenario = .trainingGrounds,
        hero heroID: HeroID = .alaric,
        face: Face = startingFace,
        options: MatchOptions = MatchOptions()
    ) {
        map = scenario.map
        lanes = scenario.lanes
        portals = scenario.portals
        hasFountains = scenario.fountains
        let definition = HeroDefinition.definition(for: heroID)
        nav = NavGrid(map: scenario.map, cellSize: Self.navCellSize, agentRadius: definition.radius)
        fog = FogOfWar(map: scenario.map, cellSize: Self.fogCellSize)
        localHero = UnitID(rawValue: 0)
        spawns[.light] = scenario.heroSpawn
        if let enemySpawn = scenario.enemySpawn { spawns[.shadow] = enemySpawn }

        units.append(makeHero(heroID, face: face, team: .light, position: scenario.heroSpawn, name: definition.name))
        for spawn in scenario.dummies {
            let isSentinel = spawn.role == .sentinel
            units.append(Unit(
                id: nextID, role: spawn.role, team: .shadow, name: spawn.name,
                position: spawn.position, radius: DummyTuning.radius, sightRadius: 0,
                armor: DummyTuning.armor, magicResist: 0,
                maxHealth: DummyTuning.maxHealth, maxMana: 0, healthRegen: 0, manaRegen: 0,
                moveSpeed: 0, attack: isSentinel ? DummyTuning.sentinelAttack : nil
            ))
        }
        for position in scenario.allies {
            units.append(makeHero(heroID, face: face, team: .light, position: position, name: "Aliado"))
        }
        buildStructures(scenario)
        buildCamps(scenario)
        buildRelics(scenario)
        if let lineup = options.lineup { buildTeams(lineup, autopilot: options.autopilot) }
        refreshFog()
    }

    private var nextID: UnitID { UnitID(rawValue: units.count) }

    // MARK: Construção da partida

    private func makeHero(_ heroID: HeroID, face: Face, team: Team, position: Vec2, name: String) -> Unit {
        let definition = HeroDefinition.definition(for: heroID)
        let mods = definition.face(face)
        var attack = definition.attack
        attack.damage *= mods.attackDamageMult
        var hero = Unit(
            id: nextID, role: .hero(heroID), team: team, face: face, name: name,
            position: position, radius: definition.radius, sightRadius: definition.sightRadius,
            armor: definition.armor + mods.armorBonus, magicResist: definition.magicResist + mods.magicResistBonus,
            maxHealth: definition.maxHealth, maxMana: definition.maxMana,
            healthRegen: definition.healthRegen * mods.healthRegenMult, manaRegen: definition.manaRegen,
            moveSpeed: definition.moveSpeed * mods.moveSpeedMult, attack: attack
        )
        hero.gold = GoldTuning.starting
        return hero
    }

    private func buildTeams(_ lineup: Lineup, autopilot: Bool) {
        guard let lightSpawn = spawns[.light] else { return }
        // Aliados: os postos livres depois do jogador (ou os cinco, se o jogador também é bot).
        var lightHeroes = lineup.allies.map(\.hero)
        if autopilot, let hero = units[localHero.rawValue].heroID { lightHeroes.insert(hero, at: 0) }
        let lightPosts = Lineup.assignPosts(lightHeroes, posts: Lineup.freePosts(withPlayer: !autopilot))
        var postIndex = 0
        if autopilot {
            bots.append(BotBrain(unit: localHero, post: lightPosts[0]))
            postIndex = 1
        }
        for (i, pick) in lineup.allies.enumerated() {
            let position = lightSpawn + Vec2(angle: Double(i + 1) * 1.26, length: Self.botSpawnRing)
            let unit = makeHero(pick.hero, face: pick.face, team: .light, position: position, name: HeroDefinition.definition(for: pick.hero).name)
            units.append(unit)
            bots.append(BotBrain(unit: unit.id, post: lightPosts[postIndex]))
            postIndex += 1
        }

        guard let shadowSpawn = spawns[.shadow] else { return }
        let shadowPosts = Lineup.assignPosts(lineup.enemies.map(\.hero), posts: Lineup.teamPosts)
        for (i, pick) in lineup.enemies.enumerated() {
            let position = shadowSpawn + Vec2(angle: Double(i) * 1.26, length: Self.botSpawnRing)
            let unit = makeHero(pick.hero, face: pick.face, team: .shadow, position: position, name: HeroDefinition.definition(for: pick.hero).name)
            units.append(unit)
            bots.append(BotBrain(unit: unit.id, post: shadowPosts[i]))
        }
    }

    private func buildStructures(_ scenario: Scenario) {
        var towerIDs: [String: UnitID] = [:]
        var towers: [(id: UnitID, team: Team, lane: Int, tier: Int)] = []
        for spawn in scenario.structures {
            let id = nextID
            switch spawn.kind {
            case .tower:
                units.append(Unit(
                    id: id, role: .tower(tier: spawn.tier), team: spawn.team, name: "Torre \(spawn.tier + 1)",
                    position: spawn.position, radius: TowerTuning.radius, sightRadius: TowerTuning.sightRadius,
                    armor: TowerTuning.armor, magicResist: TowerTuning.magicResist,
                    maxHealth: TowerTuning.maxHealth, maxMana: 0, healthRegen: 0, manaRegen: 0,
                    moveSpeed: 0, attack: TowerTuning.attack
                ))
                towerIDs["\(spawn.team):\(spawn.lane):\(spawn.tier)"] = id
                towers.append((id, spawn.team, spawn.lane, spawn.tier))
                if spawn.tier == 2 { baseTowers[spawn.team, default: [:]][spawn.lane] = id }
            case .nexus:
                units.append(Unit(
                    id: id, role: .nexus, team: spawn.team, name: "Torre da Convergência",
                    position: spawn.position, radius: NexusTuning.radius, sightRadius: NexusTuning.sightRadius,
                    armor: NexusTuning.armor, magicResist: NexusTuning.magicResist,
                    maxHealth: NexusTuning.maxHealth, maxMana: 0, healthRegen: 0, manaRegen: 0,
                    moveSpeed: 0, attack: nil
                ))
                nexusIDs[spawn.team] = id
            }
        }
        // Uma torre só é alvo depois que a anterior da mesma rota cai; o Nexus, depois de uma torre de base.
        for tower in towers where tower.tier > 0 {
            if let previous = towerIDs["\(tower.team):\(tower.lane):\(tower.tier - 1)"] {
                units[tower.id.rawValue].requiresAnyDead = [previous]
            }
        }
        for (team, nexus) in nexusIDs {
            units[nexus.rawValue].requiresAnyDead = towers.filter { $0.team == team && $0.tier == 2 }.map(\.id)
        }
    }

    private func buildCamps(_ scenario: Scenario) {
        for camp in scenario.camps {
            for member in camp.monsters {
                units.append(makeMonster(member.kind, at: camp.position + member.offset, camp: camp.name))
            }
        }
    }

    private func buildRelics(_ scenario: Scenario) {
        for (index, spawn) in scenario.relics.enumerated() {
            var guardian = makeMonster(.relic, at: spawn.position, camp: "relíquia-\(index)")
            guardian.relic = index
            units.append(guardian)
            relics.append(RelicState(kind: spawn.kind, name: spawn.name, position: spawn.position, owner: nil, guardian: guardian.id))
        }
    }

    private func makeMonster(_ kind: MonsterKind, at position: Vec2, camp: String) -> Unit {
        let stats = MonsterTuning.stats(kind)
        let name: String = switch kind {
        case .beast: "Fera da Selva"
        case .cub: "Cria da Selva"
        case .relic: "Guardião da Relíquia"
        }
        var unit = Unit(
            id: nextID, role: .monster(kind), team: .neutral, name: name, position: position,
            radius: stats.radius, sightRadius: 0, armor: stats.armor, magicResist: stats.magicResist,
            maxHealth: stats.maxHealth, maxMana: 0, healthRegen: 0, manaRegen: 0,
            moveSpeed: stats.moveSpeed, attack: stats.attack
        )
        unit.camp = camp
        return unit
    }

    // MARK: Leitura

    public func unit(_ id: UnitID) -> Unit? {
        units.indices.contains(id.rawValue) ? units[id.rawValue] : nil
    }

    public var hero: Unit { units[localHero.rawValue] }

    /// Base (fonte e renascimento) do time.
    public func spawnPoint(of team: Team) -> Vec2 {
        spawns[team] ?? spawns[.light] ?? .zero
    }

    /// Unidades controladas por bots.
    public func isBot(_ id: UnitID) -> Bool { bots.contains { $0.unitID == id } }

    /// Posto de um bot (rota ou selva).
    public func post(of id: UnitID) -> Post? { bots.first { $0.unitID == id }?.post }

    /// A unidade é visível para o time local?
    public func isVisibleToLocalTeam(_ id: UnitID) -> Bool {
        guard let unit = unit(id) else { return false }
        return unit.team == localTeam || (fog.isVisible(unit.position) && !unit.isStealthed)
    }

    /// Visível agora, ou uma estrutura já avistada antes (ela não some do mapa).
    public func isKnownToLocalTeam(_ id: UnitID) -> Bool {
        guard let unit = unit(id) else { return false }
        if isVisibleToLocalTeam(id) { return true }
        guard unit.isStructure else { return false }
        let col = Int(unit.position.x / fog.cellSize)
        let row = Int(unit.position.y / fog.cellSize)
        return fog.state(col: col, row: row) != .hidden
    }

    /// O time pode atacar o Nexus inimigo? Sem relíquias no cenário, sempre. Com elas, precisa dominar
    /// `RelicTuning.needed` relíquias, ou a partida já passou do tempo em que a Convergência se abre para todos.
    public func hasConvergence(_ team: Team) -> Bool {
        guard !relics.isEmpty else { return true }
        guard team != .neutral else { return false }
        return relicsOwned(by: team) >= RelicTuning.needed || time >= RelicTuning.fallbackTime
    }

    public func relicsOwned(by team: Team) -> Int {
        relics.filter { $0.owner == team }.count
    }

    /// Estrutura ainda protegida (não pode ser alvo): falta cair a torre que a guarda, ou, no Nexus,
    /// o atacante ainda não tem a Convergência.
    public func isProtected(_ id: UnitID) -> Bool {
        guard let unit = unit(id) else { return false }
        if let required = unit.requiresAnyDead, !required.contains(where: { !units[$0.rawValue].isAlive }) { return true }
        if unit.role == .nexus, !hasConvergence(unit.team.opponent) { return true }
        return false
    }

    /// Face do herói, se o time local pode vê-la: inimigos nunca revelam a face.
    public func visibleFace(_ id: UnitID) -> Face? {
        guard let unit = unit(id), unit.team == localTeam else { return nil }
        return unit.face
    }

    /// Habilidade `slot` da unidade (só heróis têm).
    public func ability(of unit: Unit, slot: Int) -> AbilityDefinition? {
        guard let heroID = unit.heroID, let face = unit.face else { return nil }
        let abilities = HeroDefinition.definition(for: heroID).abilities(face)
        return abilities.indices.contains(slot) ? abilities[slot] : nil
    }

    /// O atacante pode mirar nesta unidade agora (viva, inimiga, visível, não protegida)?
    public func canTarget(_ id: UnitID, by attacker: Unit) -> Bool {
        isValidTarget(id, for: attacker)
    }

    /// XP que falta para o próximo nível do herói (0 no nível máximo).
    public func xpToNextLevel(of unit: Unit) -> Double {
        unit.level >= LevelTuning.max ? 0 : LevelTuning.xpToNext(unit.level)
    }

    public func drainEvents() -> [SimEvent] {
        defer { pendingEvents.removeAll(keepingCapacity: true) }
        return pendingEvents
    }

    // MARK: Entrada

    public func setMoveAxis(_ axis: Vec2, for id: UnitID) {
        guard units.indices.contains(id.rawValue) else { return }
        units[id.rawValue].inputAxis = axis.clampedLength(to: 1)
    }

    public func setAttackHeld(_ held: Bool, for id: UnitID) {
        guard units.indices.contains(id.rawValue) else { return }
        units[id.rawValue].attackHeld = held
    }

    /// Enfileira um comando para o próximo tick.
    public func submit(_ command: Command, for id: UnitID) {
        pendingCommands.append((id, command))
    }

    // MARK: Passo de simulação

    /// Avança a simulação pelo tempo real decorrido e devolve a fração [0, 1) do tick em curso,
    /// usada pelo renderizador para interpolar posições.
    @discardableResult
    public func advance(by realDelta: Double) -> Double {
        accumulator += Swift.min(Swift.max(realDelta, 0), 0.25)
        while accumulator >= Self.tickInterval {
            accumulator -= Self.tickInterval
            tick(Self.tickInterval)
        }
        return accumulator / Self.tickInterval
    }

    /// Avança a simulação `seconds` segundos de uma vez (partidas sem interface, testes).
    public func run(seconds: Double) {
        let ticks = Int((seconds / Self.tickInterval).rounded())
        for _ in 0..<ticks where winner == nil { tick(Self.tickInterval) }
    }

    func tick(_ dt: Double) {
        guard winner == nil else { return }
        time += dt
        tickCount += 1
        if !lanes.isEmpty, time >= nextWaveAt {
            spawnWave()
            nextWaveAt += WaveTuning.interval
        }

        for index in units.indices {
            units[index].previousPosition = units[index].position
        }
        for index in projectiles.indices {
            projectiles[index].previousPosition = projectiles[index].position
        }

        for bot in bots { bot.think(self) }
        applyPendingCommands()

        for index in units.indices {
            if units[index].isAlive {
                updateLiving(index, dt)
            } else {
                updateDead(index, dt)
            }
        }
        updateProjectiles(dt)
        updateZones(dt)
        if time >= GoldTuning.passiveFrom {
            for index in units.indices where units[index].isHero { giveGold(index, GoldTuning.passivePerSecond * dt) }
        }

        ticksSinceFog += 1
        if ticksSinceFog >= Self.fogEveryTicks { refreshFog() }
    }

    // MARK: Comandos

    private func applyPendingCommands() {
        let commands = pendingCommands
        pendingCommands.removeAll(keepingCapacity: true)
        for (id, command) in commands {
            guard units.indices.contains(id.rawValue) else { continue }
            let index = id.rawValue
            // Morto só faz compras.
            switch command {
            case .buy(let item):
                buy(item, for: index)
                continue
            case .sell(let slot):
                sell(slot: slot, for: index)
                continue
            default:
                guard units[index].isAlive else { continue }
            }
            if command != .recall, units[index].recallRemaining != nil { units[index].recallRemaining = nil }
            switch command {
            case .moveTo(let point):
                let goal = map.clampToBounds(point, radius: units[index].radius)
                units[index].targetID = nil
                units[index].windupRemaining = nil
                units[index].moveGoal = goal
                units[index].path = nav.findPath(from: units[index].position, to: goal, in: map) ?? []
                if id == localHero { pendingEvents.append(.moveOrdered(to: goal)) }
            case .attack(let targetID):
                guard isValidTarget(targetID, for: units[index]) else { continue }
                units[index].moveGoal = nil
                units[index].path = []
                units[index].targetID = targetID
            case .attackNearest:
                if let target = nearestEnemy(to: units[index], within: acquireRange(of: units[index])) {
                    units[index].moveGoal = nil
                    units[index].path = []
                    units[index].targetID = target
                }
            case let .cast(slot, direction):
                cast(index, slot: slot, aim: direction)
            case .donateFlux(let to):
                donateFlux(from: index, to: to)
            case .recall:
                guard units[index].isHero, units[index].recallRemaining == nil, units[index].dash == nil else { continue }
                units[index].recallRemaining = RecallTuning.duration
                units[index].targetID = nil
                units[index].moveGoal = nil
                units[index].path = []
                units[index].windupRemaining = nil
                pendingEvents.append(.recallStarted(id))
            case .buy, .sell:
                break
            case .stop:
                units[index].targetID = nil
                units[index].moveGoal = nil
                units[index].path = []
                units[index].windupRemaining = nil
            }
        }
    }

    // MARK: Unidades vivas

    private func updateLiving(_ index: Int, _ dt: Double) {
        regenerate(index, dt)
        units[index].cooldownRemaining = Swift.max(0, units[index].cooldownRemaining - dt)
        let cooldownDt = units[index].hasteRemaining > 0 ? dt * FluxTuning.hasteCooldownFactor : dt
        units[index].hasteRemaining = Swift.max(0, units[index].hasteRemaining - dt)
        for slot in units[index].abilityCooldowns.indices {
            units[index].abilityCooldowns[slot] = Swift.max(0, units[index].abilityCooldowns[slot] - cooldownDt)
        }
        if units[index].shieldRemaining > 0 {
            units[index].shieldRemaining -= dt
            if units[index].shieldRemaining <= 0 { units[index].shield = 0 }
        }
        units[index].portalCooldown = Swift.max(0, units[index].portalCooldown - dt)
        tickStatus(index, dt)
        if units[index].isStunned {
            // Atordoado: nada de andar, atacar ou conjurar (a regeneração continua).
            units[index].windupRemaining = nil
            units[index].dash = nil
            units[index].recallRemaining = nil
            if case .hero = units[index].role { applyFountain(index, dt) }
            return
        }

        switch units[index].role {
        case .sentinel:
            runSentinelAI(index)
        case .tower:
            runTowerAI(index)
        case .minion:
            runMinionAI(index, dt)
            return
        case .monster:
            runMonsterAI(index, dt)
            return
        case .nexus:
            return
        case .hero:
            applyFountain(index, dt)
            guard units[index].isAlive else { return }
            runHeroControl(index, dt)
            return
        case .trainingDummy:
            break
        }
        // Sentinela, torre e boneco não se movem: só encaram o alvo e atacam.
        engage(index, dt)
    }

    private func tickStatus(_ index: Int, _ dt: Double) {
        let unit = units[index]
        guard unit.stunRemaining > 0 || unit.rootRemaining > 0 || unit.slowRemaining > 0
            || unit.buffRemaining > 0 || unit.stealthRemaining > 0 else { return }
        units[index].stunRemaining = Swift.max(0, unit.stunRemaining - dt)
        units[index].rootRemaining = Swift.max(0, unit.rootRemaining - dt)
        units[index].slowRemaining = Swift.max(0, unit.slowRemaining - dt)
        units[index].stealthRemaining = Swift.max(0, unit.stealthRemaining - dt)
        if unit.buffRemaining > 0 {
            units[index].buffRemaining = Swift.max(0, unit.buffRemaining - dt)
            if units[index].buffRemaining == 0 {
                units[index].attackSpeedMult = 1
                units[index].moveSpeedMult = 1
            }
        }
    }

    /// Aplica controle de grupo (o mais forte em curso prevalece).
    private func applyCrowdControl(_ index: Int, _ cc: CrowdControl) {
        guard !cc.isNone, units[index].isAlive, !units[index].isStructure else { return }
        if cc.stun > 0 {
            units[index].stunRemaining = Swift.max(units[index].stunRemaining, cc.stun)
            units[index].dash = nil
        }
        if cc.root > 0 { units[index].rootRemaining = Swift.max(units[index].rootRemaining, cc.root) }
        if cc.slow > 0 {
            units[index].slowAmount = Swift.max(units[index].slowRemaining > 0 ? units[index].slowAmount : 0, cc.slow)
            units[index].slowRemaining = Swift.max(units[index].slowRemaining, cc.slowDuration)
        }
        units[index].recallRemaining = nil
        pendingEvents.append(.crowdControlled(units[index].id))
    }

    private func regenerate(_ index: Int, _ dt: Double) {
        units[index].timeSinceDamage += dt
        let unit = units[index]
        var health = unit.health
        if unit.role == .trainingDummy {
            if unit.timeSinceDamage > DummyTuning.recoveryDelay {
                health = Swift.min(unit.maxHealth, health + DummyTuning.recoveryPerSecond * dt)
            }
        } else {
            let bonus = unit.isHero ? relicBonuses(unit.team) : RelicBonuses()
            health = Swift.min(unit.maxHealth, health + unit.healthRegen * bonus.healthRegen * dt)
            units[index].mana = Swift.min(unit.maxMana, unit.mana + unit.manaRegen * bonus.manaRegen * dt)
        }
        units[index].health = health
    }

    /// Fonte: cura e restaura mana de quem é da base; queima heróis inimigos.
    private func applyFountain(_ index: Int, _ dt: Double) {
        guard hasFountains else { return }
        let unit = units[index]
        for team in [Team.light, .shadow] {
            guard let spawn = spawns[team], unit.position.distance(to: spawn) <= FountainTuning.radius else { continue }
            if team == unit.team {
                units[index].health = Swift.min(unit.maxHealth, unit.health + unit.maxHealth * FountainTuning.healPerSecond * dt)
                units[index].mana = Swift.min(unit.maxMana, unit.mana + unit.maxMana * FountainTuning.healPerSecond * dt)
            } else if let nexus = nexusIDs[team] {
                applyDamage(to: unit.id, amount: FountainTuning.enemyDamagePerSecond * dt, type: .trueDamage, source: nexus)
            }
        }
    }

    private func runSentinelAI(_ index: Int) {
        let unit = units[index]
        guard let attack = unit.attack else { return }
        if let current = unit.targetID, isValidTarget(current, for: unit, ignoreVision: true),
           let target = self.unit(current),
           unit.position.distance(to: target.position) <= attack.range + target.radius + 20 {
            return
        }
        units[index].targetID = nearestEnemy(to: unit, within: attack.range, ignoreVision: true)
    }

    /// Prioridade do herói: retorno > investida > ataque segurado com alvo > joystick > ordens > ocioso.
    private func runHeroControl(_ index: Int, _ dt: Double) {
        if let recall = units[index].recallRemaining {
            if units[index].inputAxis != .zero {
                units[index].recallRemaining = nil
            } else if recall - dt <= 0 {
                let from = units[index].position
                let home = spawnPoint(of: units[index].team)
                units[index].recallRemaining = nil
                units[index].position = home
                units[index].previousPosition = home
                pendingEvents.append(.recalled(units[index].id, from: from, to: home))
                if units[index].id == localHero { refreshFog() }
                return
            } else {
                units[index].recallRemaining = recall - dt
                return
            }
        }
        if let dash = units[index].dash {
            runDash(index, dash, dt)
            return
        }
        if units[index].attackHeld, !hasValidTarget(index) {
            units[index].targetID = nearestEnemy(to: units[index], within: acquireRange(of: units[index]))
        }

        let hasAxis = units[index].inputAxis != .zero
        if hasAxis, !(units[index].attackHeld && hasValidTarget(index)) {
            // O joystick manda: cancela alvo, destino e golpe em andamento.
            units[index].targetID = nil
            units[index].moveGoal = nil
            units[index].path = []
            units[index].windupRemaining = nil
            let direction = units[index].inputAxis
            face(index, toward: direction.angle, dt)
            step(index, direction: direction.normalized, speedScale: direction.length, dt)
        } else if units[index].targetID != nil {
            engage(index, dt)
        } else if units[index].moveGoal != nil {
            followPath(index, dt)
        }
        usePortal(index)
    }

    /// Portais do Véu: só para quem joga (os bots não planejam rotas por eles).
    private func usePortal(_ index: Int) {
        guard !portals.isEmpty, units[index].portalCooldown <= 0, !isBot(units[index].id) else { return }
        for pair in portals {
            for (entry, exit) in [(pair.a, pair.b), (pair.b, pair.a)]
            where units[index].position.distance(to: entry) <= PortalTuning.radius {
                let from = units[index].position
                let landing = map.resolve(exit + (exit - entry).normalized * PortalTuning.exitOffset, radius: units[index].radius)
                units[index].position = landing
                units[index].previousPosition = landing
                units[index].portalCooldown = PortalTuning.cooldown
                units[index].moveGoal = nil
                units[index].path = []
                pendingEvents.append(.teleported(units[index].id, from: from, to: landing))
                if units[index].id == localHero { refreshFog() }
                return
            }
        }
    }

    // MARK: Combate

    private func acquireRange(of unit: Unit) -> Double {
        (unit.attack?.range ?? 0) + Self.acquireMargin
    }

    private func hasValidTarget(_ index: Int) -> Bool {
        guard let id = units[index].targetID else { return false }
        return isValidTarget(id, for: units[index])
    }

    private func isValidTarget(_ id: UnitID, for attacker: Unit, ignoreVision: Bool = false) -> Bool {
        guard let target = unit(id), target.isAlive, target.team != attacker.team else { return false }
        // Invisível: ninguém do outro time mira (nem torres).
        if target.isStealthed { return false }
        if let required = target.requiresAnyDead, !required.contains(where: { !units[$0.rawValue].isAlive }) { return false }
        if target.role == .nexus, !hasConvergence(attacker.team) { return false }
        if ignoreVision { return true }
        if attacker.team == localTeam { return fog.isVisible(target.position) }
        // Heróis inimigos (bots) também só miram no que o time deles enxerga.
        return attacker.isHero ? isSeen(target.position, by: attacker.team) : true
    }

    /// Algum olho do time alcança o ponto? (Visão sem obstáculos: é só para os bots do outro time.)
    private func isSeen(_ point: Vec2, by team: Team) -> Bool {
        if eyesCache?.tick != tickCount || eyesCache?.team != team {
            let eyes = units.filter { $0.team == team && $0.isAlive && $0.sightRadius > 0 }.map { ($0.position, $0.sightRadius) }
            eyesCache = (tickCount, team, eyes)
        }
        return eyesCache!.eyes.contains { ($0.0 - point).lengthSquared <= $0.1 * $0.1 }
    }

    private func nearestEnemy(to unit: Unit, within range: Double, ignoreVision: Bool = false, includeNeutral: Bool = true) -> UnitID? {
        var best: (id: UnitID, distance: Double)?
        for other in units where includeNeutral || other.team != .neutral {
            guard isValidTarget(other.id, for: unit, ignoreVision: ignoreVision) else { continue }
            let distance = unit.position.distance(to: other.position) - other.radius
            guard distance <= range else { continue }
            if best == nil || distance < best!.distance { best = (other.id, distance) }
        }
        return best?.id
    }

    /// Persegue o alvo até o alcance e ataca. Chamado só quando há (ou havia) um alvo.
    private func engage(_ index: Int, _ dt: Double) {
        let unit = units[index]
        guard let attack = unit.attack, let targetID = unit.targetID,
              isValidTarget(targetID, for: unit, ignoreVision: !unit.isHero),
              let target = self.unit(targetID)
        else {
            units[index].targetID = nil
            units[index].windupRemaining = nil
            return
        }

        let distance = unit.position.distance(to: target.position)
        let reach = attack.range + target.radius
        let winding = unit.windupRemaining != nil

        // Folga de 12% enquanto o golpe já saiu da mão: o alvo se mexendo não "rouba" o ataque.
        if distance > reach * (winding ? 1.12 : 1) {
            units[index].windupRemaining = nil
            guard unit.moveSpeed > 0 else {
                units[index].targetID = nil
                return
            }
            chase(index, target.position, dt)
            return
        }

        face(index, toward: (target.position - unit.position).angle, dt)
        units[index].path = []

        if let remaining = unit.windupRemaining {
            let left = remaining - dt
            if left <= 0 {
                units[index].windupRemaining = nil
                fire(from: index, at: target)
            } else {
                units[index].windupRemaining = left
            }
        } else if unit.cooldownRemaining <= 0 {
            units[index].windupRemaining = attack.windup
            units[index].cooldownRemaining = attack.cooldown / (unit.buffRemaining > 0 ? unit.attackSpeedMult : 1)
            pendingEvents.append(.attackStarted(attacker: unit.id, target: targetID))
        }
    }

    private func chase(_ index: Int, _ destination: Vec2, _ dt: Double) {
        units[index].repathIn -= dt
        if units[index].path.isEmpty || units[index].repathIn <= 0 {
            units[index].repathIn = Self.repathInterval
            units[index].path = nav.findPath(from: units[index].position, to: destination, in: map) ?? [destination]
        }
        advanceAlongPath(index, dt)
    }

    private func followPath(_ index: Int, _ dt: Double) {
        guard let goal = units[index].moveGoal else { return }
        if units[index].path.isEmpty {
            // Já chegou (ou o destino é inalcançável).
            if units[index].position.distance(to: goal) <= Self.arrivalDistance * 3 {
                units[index].moveGoal = nil
                return
            }
            units[index].path = nav.findPath(from: units[index].position, to: goal, in: map) ?? []
            if units[index].path.isEmpty {
                units[index].moveGoal = nil
                return
            }
        }
        let stuck = advanceAlongPath(index, dt)
        // Caminho acabou porque chegou; se só esbarrou em algo, o caminho é refeito e a ordem continua.
        if units[index].path.isEmpty, !stuck { units[index].moveGoal = nil }
    }

    /// Anda pelo caminho; devolve `true` se ficou preso (e o caminho foi descartado para ser refeito).
    @discardableResult
    private func advanceAlongPath(_ index: Int, _ dt: Double) -> Bool {
        guard let waypoint = units[index].path.first else { return false }
        let offset = waypoint - units[index].position
        if offset.length <= Self.arrivalDistance {
            units[index].path.removeFirst()
            return false
        }
        face(index, toward: offset.angle, dt)
        let before = units[index].position
        step(index, direction: offset.normalized, speedScale: 1, dt)
        // Preso (empurrado por outra unidade ou quina): força novo caminho no próximo tick.
        if units[index].position.distance(to: before) < units[index].moveSpeed * dt * 0.1 {
            units[index].repathIn = 0
            units[index].path = []
            return true
        }
        return false
    }

    private func fire(from index: Int, at target: Unit) {
        let attacker = units[index]
        guard let attack = attacker.attack else { return }
        units[index].stealthRemaining = 0
        // Corpo a corpo: o golpe acerta na hora, sem projétil.
        if attack.isMelee {
            applyDamage(to: target.id, amount: attack.damage, type: attack.damageType, source: attacker.id)
            return
        }
        let origin = attacker.position + Vec2(angle: attacker.facing, length: attacker.radius)
        projectiles.append(Projectile(
            id: nextProjectileID, source: attacker.id, target: target.id, team: attacker.team,
            position: origin, previousPosition: origin,
            speed: attack.projectileSpeed, damage: attack.damage, damageType: attack.damageType,
            direction: nil, rangeLeft: 0, hitRadius: 0
        ))
        nextProjectileID += 1
    }

    private func updateProjectiles(_ dt: Double) {
        var remaining: [Projectile] = []
        remaining.reserveCapacity(projectiles.count)
        for var projectile in projectiles {
            guard let targetID = projectile.target else {
                if updateSkillshot(&projectile, dt) { remaining.append(projectile) }
                continue
            }
            guard let target = unit(targetID), target.isAlive else { continue }
            let offset = target.position - projectile.position
            let travel = projectile.speed * dt
            if offset.length <= travel + target.radius {
                applyDamage(to: target.id, amount: projectile.damage, type: projectile.damageType, source: projectile.source)
            } else {
                projectile.position += offset.normalized * travel
                remaining.append(projectile)
            }
        }
        projectiles = remaining
    }

    /// Avança um projétil direcional. Devolve `true` se continua no ar.
    private func updateSkillshot(_ projectile: inout Projectile, _ dt: Double) -> Bool {
        guard let direction = projectile.direction else { return false }
        let travel = Swift.min(projectile.speed * dt, projectile.rangeLeft)
        let from = projectile.position
        let to = from + direction * travel
        projectile.position = to
        projectile.rangeLeft -= travel
        for unit in units where unit.isAlive && unit.team != projectile.team && !projectile.hit.contains(unit.id) {
            guard !unit.isStealthed, !isProtected(unit.id) || unit.team == .neutral,
                  Geometry.distance(from: unit.position, toSegment: from, to) <= unit.radius + projectile.hitRadius
            else { continue }
            applyDamage(to: unit.id, amount: projectile.damage, type: projectile.damageType, source: projectile.source)
            applyCrowdControl(unit.id.rawValue, projectile.cc)
            projectile.hit.append(unit.id)
            if !projectile.pierce { return false }
        }
        return projectile.rangeLeft > 0 && map.clearance(at: to) > 0
    }

    struct RelicBonuses {
        var healthRegen = 1.0
        var manaRegen = 1.0
        var heroDamage = 1.0
        var structureDamage = 1.0
    }

    /// Bônus que as relíquias dominadas dão ao time.
    func relicBonuses(_ team: Team) -> RelicBonuses {
        var bonuses = RelicBonuses()
        for relic in relics where relic.owner == team {
            switch relic.kind {
            case .light: bonuses.healthRegen += RelicTuning.regenBonus
            case .life: bonuses.manaRegen += RelicTuning.regenBonus
            case .shadow: bonuses.heroDamage += RelicTuning.heroDamageBonus
            case .death: bonuses.structureDamage += RelicTuning.structureDamageBonus
            }
        }
        return bonuses
    }

    private func applyDamage(to id: UnitID, amount: Double, type: DamageType, source: UnitID) {
        let index = id.rawValue
        guard units[index].isAlive else { return }
        var amount = amount
        if let attacker = unit(source), !relics.isEmpty, attacker.team != .neutral {
            let bonus = relicBonuses(attacker.team)
            if attacker.isHero { amount *= bonus.heroDamage }
            if units[index].isStructure { amount *= bonus.structureDamage }
        }
        if units[index].isStructure, unit(source)?.isMinion == true { amount *= MinionTuning.structureDamageMult }
        let resistance: Double = switch type {
        case .physical: units[index].armor
        case .magic: units[index].magicResist
        case .trueDamage: 0
        }
        // Fórmula clássica: cada ponto de resistência reduz em 100/(100+r).
        let dealt = amount * 100 / (100 + Swift.max(resistance, 0))
        let absorbed = Swift.min(units[index].shield, dealt)
        units[index].shield -= absorbed
        let applied = Swift.min(dealt - absorbed, units[index].health)
        units[index].health -= applied
        units[index].timeSinceDamage = 0
        units[index].recallRemaining = nil

        if source == localHero { stats.damageDealt += applied }
        units[source.rawValue].damageDealt += applied
        if units[source.rawValue].isHero {
            if units[index].isHero, units[source.rawValue].team != units[index].team {
                units[index].recentAttackers.removeAll { $0.id == source }
                units[index].recentAttackers.append((source, time))
            }
            if type == .physical, units[source.rawValue].lifesteal > 0, units[source.rawValue].isAlive {
                let s = source.rawValue
                units[s].health = Swift.min(units[s].maxHealth, units[s].health + applied * units[s].lifesteal)
            }
        }
        pendingEvents.append(.damaged(
            target: id, source: source, amount: dealt,
            position: units[index].position,
            remainingFraction: units[index].healthFraction
        ))
        if units[index].isMonster, units[index].health > 0 { provokeCamp(index, aggressor: source) }
        if units[index].isHero, units[source.rawValue].isHero { callTowers(defending: index, against: source) }
        if units[index].health <= 0 { kill(id, by: source) }
    }

    /// Herói atacado por herói perto de uma torre aliada: a torre passa a mirar no agressor.
    private func callTowers(defending victim: Int, against aggressor: UnitID) {
        let team = units[victim].team
        let attacker = units[aggressor.rawValue]
        for index in units.indices where units[index].team == team && units[index].isAlive {
            guard case .tower = units[index].role, let attack = units[index].attack else { continue }
            if units[index].position.distance(to: attacker.position) <= attack.range + attacker.radius {
                units[index].targetID = aggressor
            }
        }
    }

    private func kill(_ id: UnitID, by killer: UnitID) {
        let index = id.rawValue
        units[index].isAlive = false
        units[index].health = 0
        units[index].shield = 0
        units[index].dash = nil
        units[index].recallRemaining = nil
        units[index].targetID = nil
        units[index].windupRemaining = nil
        units[index].moveGoal = nil
        units[index].path = []
        let local = killer == localHero
        var farm = false // golpe final em esbirro/monstro/boneco: gera Fluxo
        var counts = false // conta como abate para o desempenho
        var gold = 0.0 // para quem deu o golpe final (se for herói)
        var xp = 0.0

        switch units[index].role {
        case .hero(let heroID):
            let level = Double(units[index].level - 1)
            units[index].respawnRemaining = HeroDefinition.definition(for: heroID).respawnTime + level * LevelTuning.respawnPerLevel
            if id == localHero { stats.deaths += 1 }
            // Placar do time: conta qualquer abate de herói pelo time adversário (herói, torre ou esbirro).
            if let team = unit(killer)?.team, team != .neutral, team != units[index].team { teamKills[team, default: 0] += 1 }
            counts = true
            xp = LevelTuning.heroKillXP + level * LevelTuning.heroKillXPPerLevel
            rewardHeroKill(victim: index, killer: killer)
        case .trainingDummy, .sentinel:
            units[index].respawnRemaining = DummyTuning.respawnTime
            farm = true
            counts = true
            gold = DummyTuning.goldReward
        case .minion(let kind):
            units[index].respawnRemaining = .infinity
            farm = true
            gold = MinionTuning.stats(kind).gold
            xp = MinionTuning.stats(kind).xp
            if local { stats.creeps += 1 }
        case .monster(let kind):
            units[index].respawnRemaining = MonsterTuning.stats(kind).respawn
            farm = true
            gold = MonsterTuning.stats(kind).gold
            xp = MonsterTuning.stats(kind).xp
            if local { stats.creeps += 1 }
            if let relic = units[index].relic, let team = unit(killer)?.team, team != .neutral {
                relics[relic].owner = team
                pendingEvents.append(.relicCaptured(relic: relic, team: team))
            }
        case .tower:
            units[index].respawnRemaining = .infinity
            gold = GoldTuning.towerLocal
            xp = TowerTuning.xp
            // Torre: o time inteiro de quem derrubou ganha ouro, onde estiver.
            for hero in units.indices where units[hero].isHero && units[hero].team == units[index].team.opponent {
                giveGold(hero, GoldTuning.towerGlobal)
            }
            pendingEvents.append(.structureDestroyed(id, team: units[index].team))
        case .nexus:
            units[index].respawnRemaining = .infinity
            pendingEvents.append(.structureDestroyed(id, team: units[index].team))
            let winner = units[index].team.opponent
            self.winner = winner
            pendingEvents.append(.matchEnded(winner: winner))
        }
        units[index].deaths += 1

        if units.indices.contains(killer.rawValue) {
            if counts { units[killer.rawValue].kills += 1 }
            if farm { units[killer.rawValue].flux = Swift.min(FluxTuning.max, units[killer.rawValue].flux + FluxTuning.perKill) }
            if units[killer.rawValue].isHero, gold > 0 { giveGold(killer.rawValue, gold) }
        }
        if local, counts { stats.kills += 1 }
        pendingEvents.append(.killed(target: id, killer: killer))
        if xp > 0 { shareXP(xp, victim: index, killer: killer) }
    }

    // MARK: Ouro e loja

    private func giveGold(_ index: Int, _ amount: Double) {
        guard amount > 0 else { return }
        units[index].gold += amount
        units[index].goldEarned += amount
        if index == localHero.rawValue { stats.gold += amount }
    }

    /// Abate de herói: ouro e sequência para quem matou, ouro dividido para quem ajudou, Primeiro Sangue.
    private func rewardHeroKill(victim: Int, killer: UnitID) {
        let victimTeam = units[victim].team
        let helpers = units[victim].recentAttackers
            .filter { time - $0.time <= GoldTuning.assistWindow && $0.id != killer && units[$0.id.rawValue].team != victimTeam }
            .map(\.id)
        let assisters = Array(Set(helpers)).sorted()
        units[victim].recentAttackers = []
        for id in assisters {
            units[id.rawValue].assists += 1
            if id == localHero { stats.assists += 1 }
            giveGold(id.rawValue, GoldTuning.assist / Double(assisters.count))
        }
        guard units.indices.contains(killer.rawValue), units[killer.rawValue].isHero else { return }
        let k = killer.rawValue
        var bounty = GoldTuning.heroKill
        if !firstBloodTaken {
            firstBloodTaken = true
            bounty += GoldTuning.firstBlood
            pendingEvents.append(.firstBlood(killer))
        }
        giveGold(k, bounty)
        // Double, triple, quadra, penta: abates emendados dentro da janela.
        units[k].multiKill = time - units[k].lastKillTime <= GoldTuning.multiKillWindow ? Swift.min(units[k].multiKill + 1, 5) : 1
        units[k].lastKillTime = time
        if units[k].multiKill >= 2 { pendingEvents.append(.multiKill(killer, count: units[k].multiKill)) }
    }

    /// Dá para comprar: morto, ou perto da própria base.
    public func canShop(_ id: UnitID) -> Bool {
        guard let unit = unit(id), unit.isHero else { return false }
        return !unit.isAlive || unit.position.distance(to: spawnPoint(of: unit.team)) <= GoldTuning.shopRadius
    }

    /// Preço de um item para o campeão (com desconto dos componentes que ele já tem) e se cabe no inventário.
    public func offer(_ item: ItemID, for id: UnitID) -> (cost: Double, fits: Bool) {
        guard let unit = unit(id) else { return (0, false) }
        let price = ItemCatalog.price(of: item, owned: unit.items)
        let definition = ItemDefinition.definition(item)
        let hasBoots = unit.items.enumerated().contains { ItemDefinition.definition($0.element).isBoots && !price.consumed.contains($0.offset) }
        let fits = unit.items.count - price.consumed.count < ItemCatalog.slots && !(definition.isBoots && hasBoots)
        return (price.cost, fits)
    }

    private func buy(_ item: ItemID, for index: Int) {
        let id = units[index].id
        guard canShop(id) else { return }
        let offer = offer(item, for: id)
        guard offer.fits, units[index].gold >= offer.cost else { return }
        let consumed = ItemCatalog.price(of: item, owned: units[index].items).consumed
        units[index].gold -= offer.cost
        units[index].items = units[index].items.enumerated().filter { !consumed.contains($0.offset) }.map(\.element) + [item]
        recomputeStats(index)
        pendingEvents.append(.purchased(id, item: item))
    }

    private func sell(slot: Int, for index: Int) {
        guard canShop(units[index].id), units[index].items.indices.contains(slot) else { return }
        let item = units[index].items.remove(at: slot)
        units[index].gold += ItemDefinition.definition(item).cost * ItemCatalog.sellBack
        recomputeStats(index)
        pendingEvents.append(.sold(units[index].id, item: item))
    }

    // MARK: Níveis

    /// Heróis do time que abateu (ou do adversário da vítima) por perto ganham XP; quem deu o golpe sempre ganha.
    private func shareXP(_ amount: Double, victim: Int, killer: UnitID) {
        let killerTeam = unit(killer)?.team ?? .neutral
        let team = units[victim].team == .neutral ? killerTeam : units[victim].team.opponent
        guard team != .neutral else { return }
        let place = units[victim].position
        let receivers = units.indices.filter {
            units[$0].isHero && units[$0].isAlive && units[$0].team == team
                && (units[$0].id == killer || units[$0].position.distance(to: place) <= LevelTuning.shareRange)
        }
        let share = receivers.count <= 1 ? amount : amount * LevelTuning.groupBonus / Double(receivers.count)
        for index in receivers { gainXP(index, share) }
    }

    private func gainXP(_ index: Int, _ amount: Double) {
        units[index].xp += amount
        while units[index].level < LevelTuning.max, units[index].xp >= LevelTuning.xpToNext(units[index].level) {
            units[index].xp -= LevelTuning.xpToNext(units[index].level)
            units[index].level += 1
            applyLevelStats(index)
            pendingEvents.append(.levelUp(units[index].id, level: units[index].level))
        }
        if units[index].level >= LevelTuning.max { units[index].xp = 0 }
    }

    /// Atributos do nível atual, a partir dos números-base (o ganho de vida e mana entra na hora).
    private func applyLevelStats(_ index: Int) {
        recomputeStats(index)
    }

    /// Atributos do campeão a partir dos números-base, do nível e dos itens. Ganhos de vida e mana entram na hora.
    private func recomputeStats(_ index: Int) {
        guard let heroID = units[index].heroID, let face = units[index].face else { return }
        let definition = HeroDefinition.definition(for: heroID)
        let mods = definition.face(face)
        let steps = Double(units[index].level - 1)
        let bonus = ItemCatalog.stats(of: units[index].items)
        let maxHealth = definition.maxHealth * (1 + LevelTuning.health * steps) + bonus.health
        let maxMana = definition.maxMana * (1 + LevelTuning.mana * steps) + bonus.mana
        if units[index].isAlive {
            units[index].health = Swift.max(1, units[index].health + maxHealth - units[index].maxHealth)
            units[index].mana = Swift.max(0, units[index].mana + maxMana - units[index].maxMana)
        }
        units[index].maxHealth = maxHealth
        units[index].maxMana = maxMana
        units[index].health = Swift.min(units[index].health, maxHealth)
        units[index].mana = Swift.min(units[index].mana, maxMana)
        units[index].armor = definition.armor + mods.armorBonus + bonus.armor
        units[index].magicResist = definition.magicResist + mods.magicResistBonus + bonus.magicResist
        units[index].moveSpeed = definition.moveSpeed * mods.moveSpeedMult + bonus.moveSpeed
        units[index].attack?.damage = definition.attack.damage * mods.attackDamageMult * (1 + LevelTuning.attackDamage * steps) + bonus.attackDamage
        units[index].attack?.cooldown = definition.attack.cooldown / (1 + bonus.attackSpeed)
        units[index].power = 1 + LevelTuning.abilityPower * steps + bonus.abilityPower
        units[index].lifesteal = bonus.lifesteal
        units[index].haste = Swift.min(bonus.haste, 0.4)
    }

    // MARK: Esbirros, torres e monstros

    private func spawnWave() {
        for (laneIndex, lane) in lanes.enumerated() {
            for team in [Team.light, .shadow] {
                let waypoints = lane.waypoints(for: team)
                let start = waypoints[0]
                let heading = (waypoints[1] - start).normalized
                // A torre de base inimiga desta rota caiu: a onda vem reforçada.
                let enemyBase = baseTowers[team.opponent]?[laneIndex]
                let empowered = enemyBase.map { !units[$0.rawValue].isAlive } ?? false
                for (i, kind) in WaveTuning.composition.enumerated() {
                    let position = start - heading * (Double(i) * WaveTuning.spacing)
                    spawnMinion(kind, team: team, at: position, lane: LaneProgress(waypoints: waypoints, index: 1), laneIndex: laneIndex, empowered: empowered)
                }
            }
        }
    }

    func spawnMinion(_ kind: MinionKind, team: Team, at position: Vec2, lane: LaneProgress, laneIndex: Int, empowered: Bool = false) {
        let stats = MinionTuning.stats(kind)
        // Reaproveita o lugar de um esbirro morto (que nenhum projétil persegue): a lista não cresce a cada onda.
        let chased = Set(projectiles.compactMap(\.target))
        let slot = units.firstIndex { !$0.isAlive && $0.isMinion && !chased.contains($0.id) } ?? units.count
        let lateMinutes = Swift.max(0, (time - RelicTuning.fallbackTime) / 60)
        let tide = 1 + lateMinutes * WaveTuning.lateGrowthPerMinute
        var attack = stats.attack
        attack.damage *= tide * (empowered ? WaveTuning.empoweredDamage : 1)
        var minion = Unit(
            id: UnitID(rawValue: slot), role: .minion(kind), team: team, name: kind == .guardian ? "Guardião" : "Tecelão",
            position: position, radius: stats.radius, sightRadius: MinionTuning.sightRadius,
            armor: stats.armor, magicResist: stats.magicResist,
            maxHealth: stats.maxHealth * tide * (empowered ? WaveTuning.empoweredHealth : 1),
            maxMana: 0, healthRegen: 0, manaRegen: 0, moveSpeed: stats.moveSpeed, attack: attack
        )
        minion.lane = lane
        minion.camp = "rota-\(laneIndex)"
        minion.facing = (lane.waypoints[lane.index] - position).angle
        if slot == units.count { units.append(minion) } else { units[slot] = minion }
    }

    /// Torres miram primeiro nos esbirros e só depois nos heróis (a não ser que um herói ataque outro herói).
    private func runTowerAI(_ index: Int) {
        let unit = units[index]
        guard let attack = unit.attack else { return }
        if let current = unit.targetID, isValidTarget(current, for: unit, ignoreVision: true),
           let target = self.unit(current),
           unit.position.distance(to: target.position) <= attack.range + target.radius {
            return
        }
        var best: (id: UnitID, score: Double)?
        for other in units where other.team != .neutral && isValidTarget(other.id, for: unit, ignoreVision: true) {
            let distance = unit.position.distance(to: other.position) - other.radius
            guard distance <= attack.range else { continue }
            let score = distance + (other.isMinion ? 0 : 10_000)
            if best == nil || score < best!.score { best = (other.id, score) }
        }
        units[index].targetID = best?.id
    }

    /// Marcha pela rota; larga a rota para lutar com o que estiver perto e depois retoma.
    private func runMinionAI(_ index: Int, _ dt: Double) {
        guard var lane = units[index].lane else { return }
        if let current = units[index].targetID {
            let tooFar = unit(current).map { units[index].position.distance(to: $0.position) > MinionTuning.leash } ?? true
            if tooFar || !isValidTarget(current, for: units[index], ignoreVision: true) {
                units[index].targetID = nil
                units[index].windupRemaining = nil
            }
        }
        if units[index].targetID == nil {
            units[index].targetID = nearestEnemy(to: units[index], within: MinionTuning.aggro, ignoreVision: true, includeNeutral: false)
        }
        if units[index].targetID != nil {
            engage(index, dt)
            return
        }
        if units[index].position.distance(to: lane.waypoints[lane.index]) < 80, lane.index < lane.waypoints.count - 1 {
            lane.index += 1
            units[index].lane = lane
        }
        let toward = lane.waypoints[lane.index] - units[index].position
        face(index, toward: toward.angle, dt)
        step(index, direction: toward.normalized, speedScale: 1, dt)
    }

    /// Monstros ficam parados até apanhar; perseguem até o limite e voltam curando.
    private func runMonsterAI(_ index: Int, _ dt: Double) {
        if let current = units[index].targetID {
            let tooFar = units[index].position.distance(to: units[index].spawnPoint) > MonsterTuning.leash
            if tooFar || !isValidTarget(current, for: units[index], ignoreVision: true) {
                units[index].targetID = nil
                units[index].windupRemaining = nil
                units[index].path = []
            }
        }
        if units[index].targetID != nil {
            engage(index, dt)
            return
        }
        let home = units[index].spawnPoint - units[index].position
        if home.length > 8 {
            face(index, toward: home.angle, dt)
            step(index, direction: home.normalized, speedScale: 1, dt)
        }
        units[index].health = Swift.min(units[index].maxHealth, units[index].health + units[index].maxHealth * MonsterTuning.healPerSecond * dt)
    }

    /// Quem apanha chama o grupo: o acampamento inteiro passa a atacar o agressor.
    private func provokeCamp(_ victim: Int, aggressor: UnitID) {
        let camp = units[victim].camp
        for index in units.indices where units[index].camp == camp && units[index].isMonster && units[index].isAlive {
            if units[index].targetID == nil, isValidTarget(aggressor, for: units[index], ignoreVision: true) {
                units[index].targetID = aggressor
            }
        }
    }

    // MARK: Habilidades

    /// Conjura uma habilidade. `aim` é a direção da mira; para áreas no chão, o comprimento do vetor (em
    /// unidades do mundo) diz onde ela cai, limitado ao alcance (vetor curto = alcance máximo).
    private func cast(_ index: Int, slot: Int, aim: Vec2) {
        let unit = units[index]
        guard let ability = ability(of: unit, slot: slot), unit.dash == nil, !unit.isStunned else { return }
        guard unit.abilityCooldowns[slot] <= 0, unit.mana >= ability.manaCost else { return }
        // Enraizado não usa movimento.
        if ability.isMobility, unit.rootRemaining > 0 { return }

        let direction = aim == .zero ? Vec2(angle: unit.facing) : aim.normalized
        let power = unit.power
        units[index].mana -= ability.manaCost
        units[index].abilityCooldowns[slot] = ability.cooldown * (1 - unit.haste)
        units[index].windupRemaining = nil
        units[index].recallRemaining = nil
        units[index].stealthRemaining = 0
        pendingEvents.append(.cast(unit: unit.id, slot: slot, position: unit.position))

        switch ability.effect {
        case let .skillshot(damage, type, range, radius, speed, pierce, cc):
            units[index].facing = direction.angle
            let origin = unit.position + direction * unit.radius
            var projectile = Projectile(
                id: nextProjectileID, source: unit.id, target: nil, team: unit.team,
                position: origin, previousPosition: origin, speed: speed,
                damage: damage * power, damageType: type,
                direction: direction, rangeLeft: range, hitRadius: radius
            )
            projectile.pierce = pierce
            projectile.cc = cc
            projectiles.append(projectile)
            nextProjectileID += 1
        case let .shield(amount, duration, heal):
            units[index].shield = amount * power
            units[index].shieldRemaining = duration
            if heal > 0 { units[index].health = Swift.min(unit.maxHealth, unit.health + heal * power) }
        case let .dash(distance, speed, damage, cc, stopOnHit):
            units[index].facing = direction.angle
            units[index].targetID = nil
            units[index].moveGoal = nil
            units[index].path = []
            units[index].dash = Dash(direction: direction, remaining: distance, speed: speed, damage: damage * power, cc: cc, stopOnHit: stopOnHit)
        case let .blink(distance):
            let from = unit.position
            let landing = map.resolve(map.clampToBounds(from + direction * distance, radius: unit.radius), radius: unit.radius)
            units[index].facing = direction.angle
            units[index].position = landing
            units[index].previousPosition = landing
            units[index].moveGoal = nil
            units[index].path = []
            pendingEvents.append(.teleported(unit.id, from: from, to: landing))
            if unit.id == localHero { refreshFog() }
        case let .nova(damage, type, radius, heal, allyHeal, cc):
            if heal > 0 { units[index].health = Swift.min(unit.maxHealth, unit.health + heal * power) }
            if allyHeal > 0 { healAllies(of: unit.team, around: unit.position, radius: radius, amount: allyHeal * power) }
            hitEnemies(of: index, where: { unit.position.distance(to: $0.position) <= radius + $0.radius }, damage: damage * power, type: type, cc: cc)
        case let .cone(damage, type, range, angle, cc):
            units[index].facing = direction.angle
            hitEnemies(of: index, where: { other in
                let offset = other.position - unit.position
                let distance = offset.length
                if distance > range + other.radius { return false }
                return distance <= other.radius || offset.angle(to: direction) <= angle / 2
            }, damage: damage * power, type: type, cc: cc)
        case let .zone(damage, type, range, radius, delay, pulses, interval, heal, cc, follow):
            let reach = aim.length > 1.5 ? Swift.min(aim.length, range) : range
            let center = follow ? unit.position : map.clampToBounds(unit.position + direction * reach, radius: 0)
            if !follow { units[index].facing = direction.angle }
            zones.append(Zone(
                id: nextZoneID, source: unit.id, team: unit.team, position: center, radius: radius,
                timer: delay, pulsesLeft: pulses, interval: interval, damage: damage * power, damageType: type,
                heal: heal * power, cc: cc, follow: follow
            ))
            nextZoneID += 1
        case let .buff(duration, attackSpeed, moveSpeed, stealth):
            units[index].buffRemaining = duration
            units[index].attackSpeedMult = attackSpeed
            units[index].moveSpeedMult = moveSpeed
            if stealth {
                units[index].stealthRemaining = duration
                // Quem some da vista também some como alvo.
                for other in units.indices where units[other].targetID == unit.id && units[other].team != unit.team {
                    units[other].targetID = nil
                    units[other].windupRemaining = nil
                }
            }
        }
    }

    /// Fere (e aplica controle) em cada inimigo que passa no teste.
    private func hitEnemies(of index: Int, where test: (Unit) -> Bool, damage: Double, type: DamageType, cc: CrowdControl) {
        let caster = units[index]
        for other in units where other.isAlive && other.team != caster.team && test(other) {
            guard isValidTarget(other.id, for: caster, ignoreVision: true) else { continue }
            applyDamage(to: other.id, amount: damage, type: type, source: caster.id)
            applyCrowdControl(other.id.rawValue, cc)
        }
    }

    private func healAllies(of team: Team, around center: Vec2, radius: Double, amount: Double) {
        for index in units.indices where units[index].isHero && units[index].isAlive && units[index].team == team {
            if units[index].position.distance(to: center) <= radius + units[index].radius {
                units[index].health = Swift.min(units[index].maxHealth, units[index].health + amount)
            }
        }
    }

    private func runDash(_ index: Int, _ dash: Dash, _ dt: Double) {
        let before = units[index].position
        var next = dash
        // Subpassos menores que o raio: a investida é rápida demais para não atravessar paredes finas.
        let substeps = Swift.max(1, Int((dash.speed * dt / units[index].radius).rounded(.up)))
        for _ in 0..<substeps {
            step(index, direction: dash.direction, speedScale: 1, dt / Double(substeps), speed: dash.speed)
            guard dash.damage > 0 || !dash.cc.isNone else { continue }
            // Investida que fere: cada inimigo do caminho uma vez; `stopOnHit` para no primeiro.
            let caster = units[index]
            for other in units where other.isAlive && other.team != caster.team && !next.hit.contains(other.id) {
                guard caster.position.distance(to: other.position) <= caster.radius + other.radius + 20,
                      isValidTarget(other.id, for: caster, ignoreVision: true) else { continue }
                next.hit.append(other.id)
                if next.damage > 0 { applyDamage(to: other.id, amount: next.damage, type: .physical, source: caster.id) }
                applyCrowdControl(other.id.rawValue, next.cc)
                if next.stopOnHit {
                    units[index].dash = nil
                    units[index].targetID = other.isAlive ? other.id : nil
                    return
                }
            }
        }
        let moved = units[index].position.distance(to: before)
        next.remaining -= moved
        // Parede à frente (quase não andou) também encerra a investida.
        units[index].dash = next.remaining <= 0 || moved < dash.speed * dt * 0.2 ? nil : next
    }

    // MARK: Áreas

    private func updateZones(_ dt: Double) {
        guard !zones.isEmpty else { return }
        var remaining: [Zone] = []
        for var zone in zones {
            zone.age += dt
            if zone.follow, let source = unit(zone.source) {
                guard source.isAlive else { continue }
                zone.position = source.position
            }
            zone.timer -= dt
            if zone.timer <= 0 {
                pulse(zone)
                zone.pulsesLeft -= 1
                zone.timer += zone.interval
            }
            if zone.pulsesLeft > 0 { remaining.append(zone) }
        }
        zones = remaining
    }

    private func pulse(_ zone: Zone) {
        pendingEvents.append(.zonePulse(position: zone.position, radius: zone.radius, team: zone.team))
        if zone.heal > 0 { healAllies(of: zone.team, around: zone.position, radius: zone.radius, amount: zone.heal) }
        guard zone.damage > 0 || !zone.cc.isNone, let caster = unit(zone.source) else { return }
        for other in units where other.isAlive && other.team != zone.team {
            guard other.position.distance(to: zone.position) <= zone.radius + other.radius,
                  isValidTarget(other.id, for: caster, ignoreVision: true) else { continue }
            if zone.damage > 0 { applyDamage(to: other.id, amount: zone.damage, type: zone.damageType, source: zone.source) }
            applyCrowdControl(other.id.rawValue, zone.cc)
        }
    }

    // MARK: Fluxo

    /// Foi bem na partida: mais abates que mortes e dano mínimo causado.
    private func performedWell(_ unit: Unit) -> Bool {
        unit.kills > unit.deaths && unit.damageDealt >= FluxTuning.goodDamage
    }

    /// Doa Fluxo a um aliado, como mana. Duas doações por partida: a primeira é baixa; a segunda
    /// é maior e ganha +10% se o doador foi bem. O excesso de mana vira Surto de Éter.
    private func donateFlux(from donorIndex: Int, to id: UnitID) {
        let donor = units[donorIndex]
        guard let receiver = unit(id), receiver.id != donor.id, receiver.isAlive, receiver.team == donor.team,
              receiver.isHero, donor.isHero,
              donor.donationsMade < FluxTuning.maxDonations, donor.flux > 0
        else { return }

        let second = donor.donationsMade == 1
        let sent = donor.flux * (second ? FluxTuning.secondShare : FluxTuning.firstShare)
        let delivered = sent * (second && performedWell(donor) ? 1 + FluxTuning.performanceBonus : 1)

        units[donorIndex].flux -= sent
        units[donorIndex].donationsMade += 1
        let toMana = Swift.min(delivered, receiver.maxMana - receiver.mana)
        units[id.rawValue].mana += toMana
        let overflow = delivered - toMana
        if overflow > 0 {
            units[id.rawValue].hasteRemaining = Swift.min(FluxTuning.hasteMax, receiver.hasteRemaining + overflow * FluxTuning.hastePerFlux)
        }
        pendingEvents.append(.donated(from: donor.id, to: id, amount: delivered, position: receiver.position))
    }

    // MARK: Mortos

    private func updateDead(_ index: Int, _ dt: Double) {
        units[index].respawnRemaining -= dt
        guard units[index].respawnRemaining <= 0 else { return }
        let home = units[index].isHero ? spawnPoint(of: units[index].team) : units[index].spawnPoint
        let spawn = units[index].isHero && units[index].spawnPoint.distance(to: home) < 200 ? units[index].spawnPoint : home
        units[index].isAlive = true
        units[index].health = units[index].maxHealth
        units[index].mana = units[index].maxMana
        units[index].position = spawn
        units[index].previousPosition = spawn
        units[index].cooldownRemaining = 0
        units[index].timeSinceDamage = 100
        units[index].targetID = nil
        pendingEvents.append(.respawned(units[index].id))
        if units[index].id == localHero { refreshFog() }
    }

    // MARK: Movimento

    private func face(_ index: Int, toward angle: Double, _ dt: Double) {
        units[index].facing = Angle.rotate(units[index].facing, toward: angle, maxStep: Self.turnRate * dt)
    }

    /// Anda na direção dada. `speed` fixo é para investidas (ignora lentidão e raiz).
    private func step(_ index: Int, direction: Vec2, speedScale: Double, _ dt: Double, speed: Double? = nil) {
        let unit = units[index]
        if speed == nil, !unit.canMove { return }
        let velocity = speed ?? unit.currentMoveSpeed * speedScale
        var position = unit.position + direction * (velocity * dt)
        position = map.resolve(position, radius: unit.radius)
        for other in units where other.id != unit.id && other.isAlive {
            // As torres ficam sobre a rota: os esbirros passam pelas estruturas do próprio time.
            if unit.isMinion, other.isStructure, other.team == unit.team { continue }
            // Campeões atravessam esbirros, monstros e bonecos (e vice-versa): a rota cheia não trava o herói.
            if unit.isHero != other.isHero, !unit.isStructure, !other.isStructure { continue }
            let minimum = unit.radius + other.radius
            let offset = position - other.position
            if offset.lengthSquared < minimum * minimum {
                let away = offset.lengthSquared > 1e-9 ? offset.normalized : -direction
                position = other.position + away * minimum
                // Batendo de frente: desliza pela borda em vez de parar (contorna torres e outros heróis).
                let into = -direction.dot(away)
                if into > 0.2 {
                    var tangent = direction + away * into
                    if tangent.lengthSquared < 0.04 { tangent = Vec2(-away.y, away.x) }
                    position += tangent.normalized * (velocity * dt * into)
                }
            }
        }
        units[index].position = map.resolve(position, radius: unit.radius)
    }

    // MARK: Névoa

    private func refreshFog() {
        ticksSinceFog = 0
        let eyes = units
            .filter { $0.team == localTeam && $0.isAlive && $0.sightRadius > 0 }
            .map { FogOfWar.Eye(position: $0.position, radius: $0.sightRadius) }
        fog.update(eyes: eyes, map: map)
    }
}
