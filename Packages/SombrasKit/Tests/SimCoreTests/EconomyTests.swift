import Testing
@testable import SimCore

@Suite("Ouro, loja e abates em sequência")
struct EconomyTests {
    func normal(seed: UInt64 = 21) -> Simulation {
        Simulation(scenario: .aetheria, hero: .lyara, options: MatchOptions(lineup: Lineup.random(player: .lyara, seed: seed)))
    }

    @Test func everyChampionStartsWithGoldAndEarnsPassively() {
        let sim = normal()
        #expect(sim.units.filter(\.isHero).allSatisfy { $0.gold == GoldTuning.starting })
        sim.bots.removeAll()
        sim.step(GoldTuning.passiveFrom + 10)
        #expect(abs(sim.hero.gold - (GoldTuning.starting + 10 * GoldTuning.passivePerSecond)) < 1)
    }

    @Test func lastHittingMinionGivesGold() {
        let sim = Simulation(scenario: openArena())
        sim.spawnMinion(.guardian, team: .shadow, at: Vec2(500, 500), lane: LaneProgress(waypoints: [Vec2(500, 500)], index: 0), laneIndex: 0)
        let minion = sim.units.last!
        sim.units[minion.id.rawValue].health = 1
        sim.submit(.attack(minion.id), for: sim.localHero)
        sim.step(1.5)
        #expect(sim.hero.gold == GoldTuning.starting + MinionTuning.guardian.gold)
        #expect(sim.stats.gold == MinionTuning.guardian.gold)
    }

    @Test func towerGivesGoldToKillerAndWholeTeam() {
        let sim = normal()
        sim.bots.removeAll()
        let outer = sim.tower(.shadow, tier: 0, lane: 1)
        sim.place(at: outer.position + Vec2(-300, 300))
        sim.units[outer.id.rawValue].health = 1
        sim.submit(.attack(outer.id), for: sim.localHero)
        sim.step(3)
        #expect(!sim.units[outer.id.rawValue].isAlive)
        #expect(sim.hero.gold >= GoldTuning.starting + GoldTuning.towerLocal + GoldTuning.towerGlobal)
        let ally = sim.first { $0.isHero && $0.team == .light && $0.id != sim.localHero }
        #expect(ally.gold >= GoldTuning.starting + GoldTuning.towerGlobal)
    }

    /// Mata `count` heróis inimigos em sequência com o herói local.
    func killEnemies(_ sim: Simulation, count: Int, gap: Double = 1) {
        let enemies = sim.units.filter { $0.isHero && $0.team == .shadow }.prefix(count)
        for enemy in enemies {
            let index = enemy.id.rawValue
            sim.units[index].position = sim.hero.position + Vec2(120, 0)
            sim.units[index].health = 1
            sim.submit(.attack(enemy.id), for: sim.localHero)
            sim.step(gap)
        }
    }

    @Test func heroKillsPayAndChainIntoMultiKills() {
        let sim = normal()
        sim.bots.removeAll()
        sim.place(at: Vec2(3000, 3000))
        let before = sim.hero.gold
        _ = sim.drainEvents()
        var events: [SimEvent] = []
        let enemies = sim.units.filter { $0.isHero && $0.team == .shadow }
        for enemy in enemies {
            let index = enemy.id.rawValue
            sim.units[index].position = sim.hero.position + Vec2(110, 0)
            sim.units[index].previousPosition = sim.units[index].position
            sim.units[index].health = 1
            sim.submit(.attack(enemy.id), for: sim.localHero)
            sim.step(1)
            events += sim.drainEvents()
        }
        #expect(events.contains(.firstBlood(sim.localHero)))
        for count in 2...5 { #expect(events.contains(.multiKill(sim.localHero, count: count))) }
        #expect(sim.hero.gold >= before + 5 * GoldTuning.heroKill + GoldTuning.firstBlood)
        #expect(sim.teamKills[.light] == 5)
    }

    @Test func slowKillsDoNotChain() {
        let sim = normal()
        sim.bots.removeAll()
        sim.place(at: Vec2(3000, 3000))
        _ = sim.drainEvents()
        var events: [SimEvent] = []
        for enemy in sim.units.filter({ $0.isHero && $0.team == .shadow }).prefix(2) {
            let index = enemy.id.rawValue
            sim.units[index].position = sim.hero.position + Vec2(110, 0)
            sim.units[index].health = 1
            sim.submit(.attack(enemy.id), for: sim.localHero)
            sim.step(GoldTuning.multiKillWindow + 2)
            events += sim.drainEvents()
        }
        #expect(!events.contains { if case .multiKill = $0 { true } else { false } })
    }

    @Test func assistsShareGold() {
        let sim = normal()
        sim.bots.removeAll()
        let ally = sim.first { $0.isHero && $0.team == .light && $0.id != sim.localHero }
        let enemy = sim.first { $0.isHero && $0.team == .shadow }
        sim.place(at: Vec2(3000, 3000))
        sim.units[ally.id.rawValue].position = Vec2(3000, 3100)
        sim.units[enemy.id.rawValue].position = Vec2(3100, 3000)
        sim.units[enemy.id.rawValue].health = 2000
        sim.submit(.attack(enemy.id), for: ally.id)
        sim.step(2)
        let allyGold = sim.units[ally.id.rawValue].gold
        sim.units[enemy.id.rawValue].health = 1
        sim.submit(.stop, for: ally.id)
        sim.submit(.attack(enemy.id), for: sim.localHero)
        sim.step(1)
        #expect(!sim.units[enemy.id.rawValue].isAlive)
        #expect(sim.units[ally.id.rawValue].assists == 1)
        #expect(sim.units[ally.id.rawValue].gold >= allyGold + GoldTuning.assist - 1)
    }

    @Test func buyingOnlyAtBaseOrDead() {
        let sim = Simulation(scenario: openArena())
        sim.submit(.buy(.longSword), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.items == [.longSword])
        #expect(sim.hero.gold == GoldTuning.starting - 350)
        sim.place(at: Vec2(2000, 500), tough: false)
        sim.submit(.buy(.dagger), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.items == [.longSword])
    }

    @Test func itemsChangeStats() {
        let sim = Simulation(scenario: openArena(), hero: .korrath)
        let damage = sim.hero.attack!.damage
        let health = sim.hero.maxHealth
        sim.units[0].gold = 10_000
        sim.submit(.buy(.longSword), for: sim.localHero)
        sim.submit(.buy(.rubyCrystal), for: sim.localHero)
        sim.submit(.buy(.clothArmor), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.attack!.damage == damage + 10)
        #expect(sim.hero.maxHealth == health + 150)
        #expect(sim.hero.armor == HeroDefinition.definition(for: .korrath).armor + 6 + 15)
    }

    @Test func recipeUsesComponentsAndDiscounts() {
        let sim = Simulation(scenario: openArena())
        sim.units[0].gold = 10_000
        sim.submit(.buy(.longSword), for: sim.localHero)
        sim.submit(.buy(.longSword), for: sim.localHero)
        sim.step(dt)
        #expect(sim.offer(.serratedBlade, for: sim.localHero).cost == 1100 - 700)
        sim.submit(.buy(.serratedBlade), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.items == [.serratedBlade])
        #expect(sim.hero.gold == 10_000 - 1100)
        #expect(ItemCatalog.price(of: .eclipseBlade, owned: []).cost == 3000)
    }

    @Test func sixSlotsAndOnlyOnePairOfBoots() {
        let sim = Simulation(scenario: openArena())
        sim.units[0].gold = 100_000
        sim.submit(.buy(.boots), for: sim.localHero)
        sim.submit(.buy(.boots), for: sim.localHero)
        for _ in 0..<7 { sim.submit(.buy(.rubyCrystal), for: sim.localHero) }
        sim.step(dt)
        #expect(sim.hero.items.filter { $0 == .boots }.count == 1)
        #expect(sim.hero.items.count == ItemCatalog.slots)
        // Botas melhores usam as botas que já tem.
        sim.submit(.sell(slot: 5), for: sim.localHero)
        sim.submit(.buy(.swiftBoots), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.items.contains(.swiftBoots) && !sim.hero.items.contains(.boots))
    }

    @Test func sellingRefundsPart() {
        let sim = Simulation(scenario: openArena())
        sim.submit(.buy(.longSword), for: sim.localHero)
        sim.step(dt)
        sim.submit(.sell(slot: 0), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.items.isEmpty)
        #expect(sim.hero.gold == GoldTuning.starting - 350 + 350 * ItemCatalog.sellBack)
    }

    @Test func lifestealHealsAndHasteShortensCooldowns() {
        let sim = Simulation(scenario: openArena(), hero: .lyara)
        sim.units[0].gold = 10_000
        sim.submit(.buy(.eclipseBlade), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.lifesteal > 0)
        sim.submit(.cast(slot: 0, direction: Vec2(1, 0)), for: sim.localHero)
        sim.step(dt)
        let base = HeroDefinition.definition(for: .lyara).abilities(.light)[0].cooldown
        #expect(sim.hero.abilityCooldowns[0] < base * 0.95)
    }

    @Test func botsBuyItemsDuringTheMatch() {
        let sim = Simulation(
            scenario: .aetheria, hero: .lyara,
            options: MatchOptions(lineup: Lineup.random(player: .lyara, seed: 31), autopilot: true)
        )
        sim.run(seconds: 8 * 60)
        let heroes = sim.units.filter(\.isHero)
        #expect(heroes.allSatisfy { !$0.items.isEmpty })
        #expect(heroes.contains { $0.items.contains { ItemDefinition.definition($0).tier >= .epic } })
    }
}
