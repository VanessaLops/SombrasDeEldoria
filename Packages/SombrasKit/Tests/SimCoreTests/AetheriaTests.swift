import Foundation
import Testing
@testable import SimCore

@Suite("Mapa Aetheria")
struct AetheriaMapTests {
    let scenario = Scenario.aetheria

    @Test func lanesStructuresBasesRelicsAndPortalsAreClear() {
        let map = scenario.map
        for lane in scenario.lanes {
            for step in 0...100 {
                #expect(map.clearance(at: Scenario.point(along: lane.waypoints, fraction: Double(step) / 100)) > 100)
            }
        }
        for structure in scenario.structures { #expect(map.clearance(at: structure.position) > 100) }
        for relic in scenario.relics { #expect(map.clearance(at: relic.position) > 150) }
        for pair in scenario.portals { #expect(map.clearance(at: pair.a) > 150 && map.clearance(at: pair.b) > 150) }
        #expect(map.clearance(at: scenario.heroSpawn) > 100)
        #expect(map.clearance(at: scenario.enemySpawn!) > 100)
    }

    @Test func isSymmetricForBothTeams() {
        let light = scenario.structures.filter { $0.team == .light }
        let shadow = scenario.structures.filter { $0.team == .shadow }
        #expect(light.count == shadow.count)
        #expect(light.filter { $0.kind == .tower }.count == 9)
        for s in scenario.structures {
            let mirrored = scenario.structures.contains {
                $0.team != s.team && $0.tier == s.tier && abs($0.position.x - s.position.y) < 1 && abs($0.position.y - s.position.x) < 1
            }
            #expect(mirrored)
        }
        #expect(scenario.camps.count == 8)
        #expect(scenario.relics.count == 4)
        // As relíquias do rio ficam à mesma distância das duas bases.
        for relic in scenario.relics.prefix(2) {
            #expect(abs(relic.position.distance(to: scenario.heroSpawn) - relic.position.distance(to: scenario.enemySpawn!)) < 1)
        }
    }

    @Test func thereIsAPathBetweenBases() {
        let nav = NavGrid(map: scenario.map, cellSize: 40, agentRadius: 18)
        #expect(nav.findPath(from: scenario.heroSpawn, to: scenario.enemySpawn!, in: scenario.map) != nil)
    }
}

@Suite("Rotas, torres e objetivos")
struct ObjectiveTests {
    @Test func wavesSpawnOnTimeOnAllLanesForBothTeams() {
        let sim = Simulation(scenario: .aetheria)
        sim.step(WaveTuning.first - 0.5)
        #expect(sim.aliveMinions.isEmpty)
        sim.step(1)
        #expect(sim.aliveMinions.count == 3 * 2 * WaveTuning.composition.count)
    }

    @Test func wavesMeetAndFightAndSlotsAreReused() {
        let sim = Simulation(scenario: .aetheria)
        sim.step(200)
        #expect(sim.units.filter(\.isMinion).contains { !$0.isAlive })
        #expect(sim.units.count < 260)
        // Esbirros não atacam a selva.
        #expect(sim.units.filter(\.isMonster).allSatisfy { $0.health == $0.maxHealth })
    }

    @Test func innerTowersAndNexusAreProtected() {
        let sim = Simulation(scenario: .aetheria)
        let outer = sim.tower(.shadow, tier: 0, lane: 1)
        let inner = sim.tower(.shadow, tier: 1, lane: 1)
        #expect(!sim.isProtected(outer.id))
        #expect(sim.isProtected(inner.id))
        #expect(sim.isProtected(sim.nexus(.shadow).id))

        sim.place(at: outer.position + Vec2(-300, 300))
        sim.units[outer.id.rawValue].health = 1
        sim.submit(.attack(outer.id), for: sim.localHero)
        sim.step(4)
        #expect(!sim.units[outer.id.rawValue].isAlive)
        #expect(!sim.isProtected(inner.id))
        #expect(sim.stats.gold >= TowerTuning.gold)
    }

    @Test func nexusStaysSealedWithoutConvergence() {
        let sim = Simulation(scenario: .aetheria)
        for tower in sim.units where tower.team == .shadow && tower.role == .tower(tier: 2) {
            sim.units[tower.id.rawValue].isAlive = false
            sim.units[tower.id.rawValue].respawnRemaining = .infinity
        }
        let nexus = sim.nexus(.shadow)
        #expect(!sim.hasConvergence(.light))
        #expect(sim.isProtected(nexus.id))

        // Duas relíquias: a Convergência abre o Nexus.
        sim.relics[0].owner = .light
        sim.relics[2].owner = .light
        #expect(sim.hasConvergence(.light))
        #expect(!sim.isProtected(nexus.id))
        sim.place(at: nexus.position + Vec2(-250, 250))
        sim.units[nexus.id.rawValue].health = 40
        sim.submit(.attack(nexus.id), for: sim.localHero)
        sim.step(5)
        #expect(sim.winner == .light)
        let frozen = sim.time
        sim.step(1)
        #expect(sim.time == frozen)
    }

    @Test func convergenceOpensForEveryoneLate() {
        let sim = Simulation(scenario: .aetheria)
        #expect(!sim.hasConvergence(.shadow))
        sim.step(dt)
        sim.relics[0].owner = .shadow
        #expect(!sim.hasConvergence(.shadow))
        #expect(sim.relicsOwned(by: .shadow) == 1)
    }

    @Test func killingRelicGuardianCapturesRelic() {
        let sim = Simulation(scenario: .aetheria)
        let relic = sim.relics[0]
        sim.place(at: relic.position + Vec2(-200, 0))
        sim.submit(.attack(relic.guardian), for: sim.localHero)
        sim.step(1.5) // o primeiro golpe provoca o guardião (provocado, ele não se cura)
        #expect(sim.units[relic.guardian.rawValue].targetID == sim.localHero)
        sim.units[relic.guardian.rawValue].health = 1
        sim.step(3)
        #expect(sim.relics[0].owner == .light)
        #expect(sim.drainEvents().contains(.relicCaptured(relic: 0, team: .light)))
    }

    @Test func towerDefendsHeroAttackedByHero() {
        let sim = Simulation(scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 1)))
        let tower = sim.tower(.light, tier: 0, lane: 1)
        let enemy = sim.first { $0.isHero && $0.team == .shadow }
        // Sem o cérebro, o inimigo não foge da torre: testa só a regra da torre.
        sim.bots.removeAll { $0.unitID == enemy.id }
        sim.place(at: tower.position + Vec2(80, 0))
        sim.units[enemy.id.rawValue].position = tower.position + Vec2(250, -200)
        sim.submit(.attack(sim.localHero), for: enemy.id)
        sim.step(1.5)
        #expect(sim.units[tower.id.rawValue].targetID == enemy.id)
    }

    @Test func fountainHealsAllyAndBurnsEnemy() {
        let sim = Simulation(scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 2)))
        sim.units[0].health = 50
        sim.step(1)
        #expect(sim.hero.health > 100)
        let enemy = sim.first { $0.isHero && $0.team == .shadow }
        sim.units[enemy.id.rawValue].position = Scenario.aetheria.heroSpawn + Vec2(100, 0)
        sim.step(0.5)
        #expect(sim.units[enemy.id.rawValue].health < enemy.maxHealth)
    }

    @Test func portalTakesPlayerAcrossTheRiver() {
        let sim = Simulation(scenario: .aetheria)
        let portal = Scenario.aetheria.portals[0]
        sim.place(at: portal.a + Vec2(-120, 0), tough: false)
        sim.submit(.moveTo(portal.a), for: sim.localHero)
        sim.step(1)
        #expect(sim.hero.position.distance(to: portal.b) < 250)
        #expect(sim.hero.portalCooldown > 0)
    }

    @Test func heroWalksAroundAlliedTower() {
        let sim = Simulation(scenario: .aetheria, hero: .korrath)
        let goal = Vec2(1500, 4500)
        sim.submit(.moveTo(goal), for: sim.localHero)
        sim.step(9)
        #expect(sim.hero.position.distance(to: goal) < 25)
    }
}

@Suite("Times e bots")
struct BotTests {
    @Test func lineupSplitsAllTenHeroes() {
        for player in Roster.order {
            let lineup = Lineup.random(player: player, seed: 42)
            let all = [player] + lineup.allies.map(\.hero) + lineup.enemies.map(\.hero)
            #expect(Set(all).count == 10)
            #expect(lineup.allies.count == 4 && lineup.enemies.count == 5)
        }
        #expect(Lineup.random(player: .alaric, seed: 7) == Lineup.random(player: .alaric, seed: 7))
    }

    @Test func postsCoverLanesAndJungle() {
        let posts = Lineup.assignPosts([.kaelor, .saria, .korrath, .nyx, .kallindra], posts: Lineup.teamPosts)
        #expect(posts == [.lane(2), .lane(2), .lane(0), .jungle, .lane(1)])
        #expect(!Lineup.freePosts(withPlayer: true).contains(.lane(1)))
    }

    @Test func normalMatchHasFiveHeroesPerTeam() {
        let sim = Simulation(scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 3)))
        #expect(sim.units.filter { $0.isHero && $0.team == .light }.count == 5)
        #expect(sim.units.filter { $0.isHero && $0.team == .shadow }.count == 5)
        #expect(!sim.isBot(sim.localHero))
    }

    @Test func botsLeaveBaseFarmAndFight() {
        let sim = Simulation(scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 4)))
        var wentOut: Set<UnitID> = []
        for _ in 0..<15 {
            sim.step(10)
            for bot in sim.units where bot.isHero && sim.isBot(bot.id) && bot.position.distance(to: sim.spawnPoint(of: bot.team)) > 1500 {
                wentOut.insert(bot.id)
            }
        }
        let bots = sim.units.filter { $0.isHero && sim.isBot($0.id) }
        #expect(wentOut.count == bots.count)
        #expect(bots.contains { $0.level > 1 })
        #expect(bots.reduce(0) { $0 + $1.damageDealt } > 2000)
    }

    @Test func enemyBotsDoNotSeeThroughFog() {
        let sim = Simulation(scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 5)))
        let enemy = sim.first { $0.isHero && $0.team == .shadow }
        // O herói local fica longe de qualquer olho inimigo.
        #expect(!sim.canTarget(sim.localHero, by: enemy))
    }

    /// A prova de que o jogo fecha: 10 bots jogam uma partida inteira até um Nexus cair.
    @Test(arguments: [11, 12, 13, 14] as [UInt64])
    func fullBotMatchEndsWithAWinner(seed: UInt64) {
        let sim = Simulation(
            scenario: .aetheria, hero: .lyara,
            options: MatchOptions(lineup: Lineup.random(player: .lyara, seed: seed), autopilot: true)
        )
        sim.run(seconds: 40 * 60)
        #expect(sim.winner != nil)
        #expect(sim.time < 40 * 60)
        #expect(sim.teamKills.values.reduce(0, +) > 0)
        #expect(sim.relics.contains { $0.owner != nil })
    }

    @Test func sameSeedSameMatch() {
        func play() -> [Double] {
            let sim = Simulation(
                scenario: .aetheria, options: MatchOptions(lineup: Lineup.random(player: .alaric, seed: 9), autopilot: true)
            )
            sim.run(seconds: 120)
            return sim.units.flatMap { [$0.health.rounded(), $0.position.x.rounded(), $0.position.y.rounded()] }
        }
        #expect(play() == play())
    }
}
