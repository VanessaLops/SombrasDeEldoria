/// IA de um herói controlado pelo computador.
///
/// O bot lê o estado da simulação e envia os mesmos comandos de um jogador (sem atalhos que um humano
/// não teria). Decide 4 vezes por segundo, em ordem de prioridade: voltar à base com pouca vida, sair do
/// tiro da torre, lutar com heróis, disputar relíquias e, por fim, farmar a rota (ou a selva) e empurrar.
final class BotBrain {
    let unitID: UnitID
    let post: Post
    private var nextThink = 0.0
    private var retreating = false
    /// Último destino pedido, para não refazer o caminho (A*) a cada decisão.
    private var goal: Vec2?
    private var lastShopTrip = 0.0

    init(unit: UnitID, post: Post) {
        unitID = unit
        self.post = post
    }

    func think(_ sim: Simulation) {
        guard sim.time >= nextThink else { return }
        nextThink = sim.time + BotTuning.thinkInterval
        guard let me = sim.unit(unitID) else { return }
        if sim.canShop(me.id) { shop(sim, me) }
        guard me.isAlive else {
            goal = nil
            retreating = false
            return
        }
        guard me.recallRemaining == nil, me.dash == nil else { return }

        donateIfUseful(sim, me)
        if retreat(sim, me) { return }
        if goShopping(sim, me) { return }
        if dodgeTower(sim, me) { return }

        if let enemy = nearestEnemyHero(sim, me, within: BotTuning.fightRange) {
            if shouldFight(sim, me, enemy) {
                fight(sim, me, enemy)
                return
            }
            if me.position.distance(to: enemy.position) < 550 {
                let away = (sim.spawnPoint(of: me.team) - me.position).normalized
                move(sim, me, to: me.position + away * 400)
                return
            }
        }
        if contestRelic(sim, me) { return }
        if case .jungle = post, jungle(sim, me) { return }
        if case .lane(let lane) = post {
            farmLane(sim, me, lane)
        } else {
            farmLane(sim, me, 1)
        }
    }

    // MARK: Sobrevivência

    private func retreat(_ sim: Simulation, _ me: Unit) -> Bool {
        let home = sim.spawnPoint(of: me.team)
        if me.healthFraction < BotTuning.retreatHealth { retreating = true }
        guard retreating else { return false }
        if me.position.distance(to: home) < FountainTuning.radius * 0.7 {
            if me.healthFraction >= 0.95, me.maxMana == 0 || me.manaFraction >= 0.8 {
                retreating = false
                return false
            }
            if me.moveGoal != nil || me.targetID != nil { sim.submit(.stop, for: me.id) }
            goal = nil
            return true
        }
        let threat = nearestEnemyHero(sim, me, within: 900)
        if threat == nil, me.timeSinceDamage > 2.5 {
            sim.submit(.recall, for: me.id)
            goal = nil
            return true
        }
        if let threat, threat.position.distance(to: me.position) < 450 {
            let away = (me.position - threat.position).normalized
            if !cast(sim, me, where: { $0.isMobility }, direction: away) {
                cast(sim, me, where: { if case .shield = $0.effect { true } else { false } }, direction: away)
            }
        }
        move(sim, me, to: home)
        return true
    }

    /// A torre inimiga está mirando em mim: sai do alcance, a não ser que o grupo esteja derrubando a torre
    /// e eu ainda aguente alguns tiros.
    private func dodgeTower(_ sim: Simulation, _ me: Unit) -> Bool {
        for tower in sim.units where tower.isAlive && tower.team == me.team.opponent && tower.targetID == me.id {
            guard case .tower = tower.role else { continue }
            if me.healthFraction > 0.55, canPushWithoutMinions(sim, me, tower) { return false }
            let range = tower.attack?.range ?? 600
            let away = (me.position - tower.position).normalized
            move(sim, me, to: tower.position + away * (range + 250), force: true)
            return true
        }
        return false
    }

    private func enemyTower(covering point: Vec2, against team: Team, _ sim: Simulation) -> Unit? {
        sim.units.first { tower in
            guard case .tower = tower.role, tower.isAlive, tower.team == team.opponent else { return false }
            return tower.position.distance(to: point) <= (tower.attack?.range ?? 0) + 60
        }
    }

    /// Empurrada em grupo: aliados suficientes junto à torre (ou fim de jogo) dispensam esbirros tankando.
    private func canPushWithoutMinions(_ sim: Simulation, _ me: Unit, _ tower: Unit) -> Bool {
        let range = (tower.attack?.range ?? 600) + 300
        let group = heroes(of: me.team, near: tower.position, within: range, sim)
        let defenders = heroes(of: tower.team, near: tower.position, within: range, sim)
        return group >= BotTuning.groupPush && group > defenders
    }

    private func minions(of team: Team, near point: Vec2, within radius: Double, _ sim: Simulation) -> Int {
        sim.units.reduce(0) { count, unit in
            count + (unit.isMinion && unit.isAlive && unit.team == team && unit.position.distance(to: point) <= radius ? 1 : 0)
        }
    }

    private func heroes(of team: Team, near point: Vec2, within radius: Double, _ sim: Simulation) -> Int {
        sim.units.reduce(0) { count, unit in
            count + (unit.isHero && unit.isAlive && unit.team == team && unit.position.distance(to: point) <= radius ? 1 : 0)
        }
    }

    // MARK: Luta

    private func nearestEnemyHero(_ sim: Simulation, _ me: Unit, within range: Double) -> Unit? {
        var best: (unit: Unit, distance: Double)?
        for other in sim.units where other.isHero && other.team == me.team.opponent && sim.canTarget(other.id, by: me) {
            let distance = other.position.distance(to: me.position)
            if distance <= range, best == nil || distance < best!.distance { best = (other, distance) }
        }
        return best?.unit
    }

    private func shouldFight(_ sim: Simulation, _ me: Unit, _ enemy: Unit) -> Bool {
        let mine = me.healthFraction
        let theirs = enemy.healthFraction
        if mine < 0.4, theirs > 0.2 { return false }
        // Não mergulha sob a torre inimiga, a não ser para finalizar.
        if let tower = enemyTower(covering: enemy.position, against: me.team, sim), theirs > 0.25,
           minions(of: me.team, near: tower.position, within: tower.attack?.range ?? 600, sim) == 0 {
            return false
        }
        let allies = heroes(of: me.team, near: me.position, within: 900, sim)
        let foes = heroes(of: enemy.team, near: enemy.position, within: 900, sim)
        return theirs <= mine + 0.2 || allies > foes || me.level > enemy.level + 1
    }

    private func fight(_ sim: Simulation, _ me: Unit, _ enemy: Unit) {
        goal = nil
        if me.targetID != enemy.id { sim.submit(.attack(enemy.id), for: me.id) }
        let gap = me.position.distance(to: enemy.position)
        // Vetor até o alvo: dá a direção e, para áreas no chão, onde cair.
        let offset = enemy.position - me.position
        let attackRange = me.attack?.range ?? 150
        let hurt = me.timeSinceDamage < 1.2 && me.healthFraction < 0.75

        // Uma habilidade por decisão; o ultimate primeiro, mas só quando vale a pena.
        for (slot, ability) in readyAbilities(sim, me) {
            var use: Bool
            switch ability.effect {
            case .shield: use = hurt
            case .buff: use = gap <= attackRange + 200
            case .dash, .blink: use = gap > attackRange + 60 && gap < ability.reach + attackRange && me.healthFraction > 0.5
            case .skillshot, .nova, .cone, .zone: use = gap <= ability.reach * 0.9 + enemy.radius
            }
            // Guarda o ultimate de dano para quando o alvo já apanhou ou há mais de um inimigo junto.
            if slot == 3, ability.dealsDamage, enemy.healthFraction > 0.85,
               heroes(of: enemy.team, near: enemy.position, within: 500, sim) < 2 {
                use = false
            }
            guard use else { continue }
            sim.submit(.cast(slot: slot, direction: offset), for: me.id)
            return
        }
    }

    private func readyAbilities(_ sim: Simulation, _ me: Unit) -> [(Int, AbilityDefinition)] {
        let ready = (0..<4).compactMap { slot -> (Int, AbilityDefinition)? in
            guard let ability = sim.ability(of: me, slot: slot),
                  me.abilityCooldowns[slot] <= 0, me.mana >= ability.manaCost else { return nil }
            return (slot, ability)
        }
        return ready.filter { $0.0 == 3 } + ready.filter { $0.0 != 3 }
    }

    @discardableResult
    private func cast(_ sim: Simulation, _ me: Unit, where test: (AbilityDefinition) -> Bool, direction: Vec2) -> Bool {
        guard let (slot, _) = readyAbilities(sim, me).first(where: { test($0.1) }) else { return false }
        sim.submit(.cast(slot: slot, direction: direction), for: me.id)
        return true
    }

    // MARK: Objetivos

    /// Disputa relíquias: o caçador vai atrás delas; os outros ajudam quem do time já está lutando por uma.
    private func contestRelic(_ sim: Simulation, _ me: Unit) -> Bool {
        guard sim.time >= RelicTuning.botsFrom, !sim.relics.isEmpty else { return false }
        var best: (guardian: Unit, position: Vec2, distance: Double)?
        for relic in sim.relics where relic.owner != me.team {
            guard let guardian = sim.unit(relic.guardian), guardian.isAlive else { continue }
            let distance = me.position.distance(to: relic.position)
            let allyFighting = sim.units.contains {
                $0.isHero && $0.team == me.team && $0.id != me.id && $0.isAlive && $0.targetID == guardian.id
            }
            let mine = post == .jungle && me.level >= 5
            guard mine || (allyFighting && distance < BotTuning.relicHelpRange) else { continue }
            if best == nil || distance < best!.distance { best = (guardian, relic.position, distance) }
        }
        guard let best else { return false }
        if best.distance < 650 {
            goal = nil
            if me.targetID != best.guardian.id { sim.submit(.attack(best.guardian.id), for: me.id) }
            cast(sim, me, where: { $0.dealsDamage && $0.key != .r }, direction: best.position - me.position)
        } else {
            move(sim, me, to: best.position)
        }
        return true
    }

    private func jungle(_ sim: Simulation, _ me: Unit) -> Bool {
        let home = sim.spawnPoint(of: me.team)
        let enemyHome = sim.spawnPoint(of: me.team.opponent)
        var best: (unit: Unit, distance: Double)?
        for monster in sim.units where monster.isMonster && monster.relic == nil && monster.isAlive {
            // Não invade a selva do outro lado do rio no começo da partida.
            if sim.time < 5 * 60, monster.position.distance(to: enemyHome) < monster.position.distance(to: home) { continue }
            let distance = me.position.distance(to: monster.position)
            if best == nil || distance < best!.distance { best = (monster, distance) }
        }
        guard let best else { return false }
        if best.distance < 500 {
            goal = nil
            if me.targetID != best.unit.id { sim.submit(.attack(best.unit.id), for: me.id) }
            if me.manaFraction > 0.5 {
                cast(sim, me, where: { $0.dealsDamage && $0.key != .r }, direction: best.unit.position - me.position)
            }
        } else {
            move(sim, me, to: best.unit.position)
        }
        return true
    }

    private func farmLane(_ sim: Simulation, _ me: Unit, _ laneIndex: Int) {
        guard sim.lanes.indices.contains(laneIndex) else { return }
        let waypoints = sim.lanes[laneIndex].waypoints(for: me.team)

        // Algo para bater por perto: esbirros e estruturas, sem entrar sozinho no tiro da torre.
        var target: (unit: Unit, distance: Double)?
        for other in sim.units where other.team == me.team.opponent && (other.isMinion || other.isStructure) {
            guard sim.canTarget(other.id, by: me) else { continue }
            let distance = me.position.distance(to: other.position) - other.radius
            guard distance <= BotTuning.farmRange, target == nil || distance < target!.distance else { continue }
            let tower: Unit? = if case .tower = other.role { other } else { enemyTower(covering: other.position, against: me.team, sim) }
            if let tower, minions(of: me.team, near: tower.position, within: tower.attack?.range ?? 600, sim) == 0,
               !(me.healthFraction > 0.55 && canPushWithoutMinions(sim, me, tower)) { continue }
            target = (other, distance)
        }
        if let target {
            goal = nil
            if me.targetID != target.unit.id { sim.submit(.attack(target.unit.id), for: me.id) }
            return
        }

        // Senão, acompanha o esbirro aliado mais adiantado desta rota, ou espera fora do alcance da torre.
        let enemyBase = sim.spawnPoint(of: me.team.opponent)
        let home = sim.spawnPoint(of: me.team)
        let front = sim.units
            .filter { $0.isMinion && $0.isAlive && $0.team == me.team && $0.camp == "rota-\(laneIndex)" }
            .min { $0.position.distance(to: enemyBase) < $1.position.distance(to: enemyBase) }
        var destination = safePoint(sim, me.team, waypoints)
        if let front {
            // Um pouco atrás da onda; sob a torre inimiga, só se houver esbirros segurando o tiro.
            let behind = front.position + (home - front.position).normalized * 150
            let exposed = enemyTower(covering: behind, against: me.team, sim) != nil
                && minions(of: me.team, near: behind, within: 400, sim) == 0
            if !exposed { destination = behind }
        }
        move(sim, me, to: destination)
    }

    /// Ponto mais avançado da rota fora do alcance de qualquer torre inimiga viva e da fonte inimiga.
    private func safePoint(_ sim: Simulation, _ team: Team, _ waypoints: [Vec2]) -> Vec2 {
        var safe = waypoints[0]
        let enemyBase = sim.spawnPoint(of: team.opponent)
        for step in 0...50 {
            let point = Scenario.point(along: waypoints, fraction: Double(step) / 50)
            if enemyTower(covering: point, against: team, sim) != nil { break }
            if point.distance(to: enemyBase) < FountainTuning.radius + 200 { break }
            safe = point
        }
        return safe
    }

    // MARK: Loja

    /// Compra o próximo item da build do papel; sem ouro para ele inteiro, compra o componente que der.
    private func shop(_ sim: Simulation, _ me: Unit) {
        guard let heroID = me.heroID else { return }
        let build = ItemCatalog.build(for: HeroDefinition.definition(for: heroID).role)
        guard let next = build.first(where: { !me.items.contains($0) }) else { return }
        if let piece = affordablePiece(next, sim, me) {
            sim.submit(.buy(piece), for: me.id)
            lastShopTrip = sim.time
        }
    }

    private func affordablePiece(_ item: ItemID, _ sim: Simulation, _ me: Unit) -> ItemID? {
        let offer = sim.offer(item, for: me.id)
        if offer.fits, me.gold >= offer.cost { return item }
        let components = ItemDefinition.definition(item).components
        for component in Set(components).sorted(by: { $0.rawValue < $1.rawValue }) {
            // Já tem quantos a receita pede: não compra de novo.
            let needed = components.filter { $0 == component }.count
            if me.items.filter({ $0 == component }).count >= needed { continue }
            if let piece = affordablePiece(component, sim, me) { return piece }
        }
        return nil
    }

    /// Com bastante ouro e sem inimigos por perto, volta à base para gastar.
    private func goShopping(_ sim: Simulation, _ me: Unit) -> Bool {
        guard me.gold >= 1300, sim.time - lastShopTrip > 90,
              me.position.distance(to: sim.spawnPoint(of: me.team)) > 2500,
              nearestEnemyHero(sim, me, within: 1000) == nil, me.timeSinceDamage > 3 else { return false }
        lastShopTrip = sim.time
        sim.submit(.recall, for: me.id)
        goal = nil
        return true
    }

    // MARK: Fluxo

    /// Doa Fluxo ao aliado por perto com menos mana (duas vezes por partida, como qualquer jogador).
    private func donateIfUseful(_ sim: Simulation, _ me: Unit) {
        guard me.flux >= BotTuning.donateAt, me.donationsMade < FluxTuning.maxDonations else { return }
        let receiver = sim.units
            .filter {
                $0.isHero && $0.isAlive && $0.team == me.team && $0.id != me.id && $0.maxMana > 0
                    && $0.position.distance(to: me.position) <= 1000 && $0.manaFraction <= 0.45
            }
            .min { $0.manaFraction < $1.manaFraction }
        if let receiver { sim.submit(.donateFlux(to: receiver.id), for: me.id) }
    }

    // MARK: Movimento

    /// Pede caminho só quando o destino muda de verdade (A* é caro para refazer a cada decisão).
    private func move(_ sim: Simulation, _ me: Unit, to point: Vec2, force: Bool = false) {
        if !force, let goal, me.moveGoal != nil, goal.distance(to: point) < 120 { return }
        goal = point
        guard me.position.distance(to: point) >= 40 else { return }
        sim.submit(.moveTo(point), for: me.id)
    }
}
