import Testing
@testable import SimCore

@Suite("Combate, habilidades e faces")
struct CombatTests {
    func duel(distance: Double = 400) -> Scenario {
        var scenario = openArena()
        scenario.dummies = [.init(role: .trainingDummy, name: "Alvo", position: Vec2(300 + distance, 500))]
        scenario.allies = [Vec2(300, 600)]
        return scenario
    }

    @Test func rosterHasTenHeroesWithFullKitsOnBothFaces() {
        #expect(Roster.order.count == 10)
        #expect(Set(Roster.order).count == 10)
        for id in Roster.order {
            let hero = HeroDefinition.definition(for: id)
            for face in Face.allCases {
                let abilities = hero.abilities(face)
                #expect(abilities.map(\.key) == [.q, .w, .e, .r])
                #expect(abilities.allSatisfy { $0.cooldown > 0 && $0.manaCost > 0 && !$0.name.isEmpty && !$0.summary.isEmpty })
            }
            #expect(hero.abilities(.light).map(\.name) != hero.abilities(.shadow).map(\.name))
        }
        #expect(Roster.order.filter { HeroDefinition.definition(for: $0).otherFaceUnlockedByTraining } == [.alaric])
    }

    @Test func basicAttackKillsDummyAndCounts() {
        let sim = Simulation(scenario: duel())
        let dummy = sim.first { $0.role == .trainingDummy }
        sim.units[dummy.id.rawValue].health = 30
        sim.units[dummy.id.rawValue].timeSinceDamage = 0 // senão ele se recupera antes do golpe
        sim.submit(.attack(dummy.id), for: sim.localHero)
        sim.step(2)
        #expect(!sim.units[dummy.id.rawValue].isAlive)
        #expect(sim.stats.kills == 1)
        #expect(sim.hero.flux == FluxTuning.perKill)
    }

    @Test func meleeHeroWalksIntoRangeBeforeHitting() {
        let sim = Simulation(scenario: duel(distance: 420), hero: .lyara)
        let dummy = sim.first { $0.role == .trainingDummy }
        sim.submit(.attack(dummy.id), for: sim.localHero)
        sim.step(3)
        #expect(sim.units[dummy.id.rawValue].health < DummyTuning.maxHealth)
        #expect(sim.hero.position.distance(to: dummy.position) < 200)
    }

    @Test func skillshotHitsInLineAndSpendsMana() {
        let sim = Simulation(scenario: duel(distance: 500))
        let mana = sim.hero.mana
        sim.submit(.cast(slot: 0, direction: Vec2(1, 0)), for: sim.localHero)
        sim.step(1)
        #expect(sim.hero.mana < mana)
        #expect(sim.first { $0.role == .trainingDummy }.health < DummyTuning.maxHealth)
        #expect(sim.hero.abilityCooldowns[0] > 0)
    }

    @Test func skillshotMissesWhenAimedAway() {
        let sim = Simulation(scenario: duel(distance: 500))
        sim.submit(.cast(slot: 0, direction: Vec2(-1, 0)), for: sim.localHero)
        sim.step(1.5)
        #expect(sim.first { $0.role == .trainingDummy }.health == DummyTuning.maxHealth)
    }

    @Test func shieldAbsorbsDamageAndDashMoves() {
        let sim = Simulation(scenario: duel())
        sim.submit(.cast(slot: 1, direction: .zero), for: sim.localHero)
        sim.step(dt * 2)
        #expect(sim.hero.shield > 0)
        let start = sim.hero.position
        sim.submit(.cast(slot: 2, direction: Vec2(0, 1)), for: sim.localHero)
        sim.step(0.6)
        #expect(sim.hero.position.distance(to: start) > 250)
    }

    @Test func cannotCastWithoutManaOrOnCooldown() {
        let sim = Simulation(scenario: duel())
        sim.units[0].mana = 0
        sim.submit(.cast(slot: 0, direction: Vec2(1, 0)), for: sim.localHero)
        sim.step(dt * 2)
        #expect(sim.hero.abilityCooldowns[0] == 0)
        #expect(sim.projectiles.isEmpty)
    }

    @Test func facesChangeKitAndStatsButNeverChangeMidMatch() {
        let light = Simulation(scenario: duel(), hero: .alaric, face: .light).hero
        let shadow = Simulation(scenario: duel(), hero: .alaric, face: .shadow).hero
        #expect(shadow.moveSpeed > light.moveSpeed)
        #expect(light.armor > shadow.armor)
        let sim = Simulation(scenario: duel(), hero: .alaric, face: .shadow)
        sim.submit(.cast(slot: 0, direction: Vec2(1, 0)), for: sim.localHero)
        sim.submit(.stop, for: sim.localHero)
        sim.step(3)
        #expect(sim.hero.face == .shadow)
    }

    @Test func faceIsOnlyVisibleToOwnTeam() {
        let sim = Simulation(scenario: duel())
        let ally = sim.first { $0.name == "Aliado" }
        let dummy = sim.first { $0.role == .trainingDummy }
        #expect(sim.visibleFace(sim.localHero) == .light)
        #expect(sim.visibleFace(ally.id) == .light)
        #expect(sim.visibleFace(dummy.id) == nil)
    }

    @Test func lightNovaHealsShadowDoesNot() {
        let light = Simulation(scenario: duel(), face: .light)
        light.units[0].health = 100
        light.submit(.cast(slot: 3, direction: .zero), for: light.localHero)
        light.step(dt * 2)
        #expect(light.hero.health > 200)

        let shadow = Simulation(scenario: duel(), face: .shadow)
        shadow.units[0].health = 100
        shadow.submit(.cast(slot: 3, direction: .zero), for: shadow.localHero)
        shadow.step(dt * 2)
        #expect(shadow.hero.health < 120)
    }

    @Test func sentinelShootsHeroInRange() {
        var scenario = openArena()
        scenario.dummies = [.init(role: .sentinel, name: "S", position: Vec2(500, 500))]
        let sim = Simulation(scenario: scenario)
        sim.step(3)
        #expect(sim.hero.health < sim.hero.maxHealth)
    }
}

@Suite("Fluxo de Éter")
struct FluxTests {
    func sim() -> Simulation {
        var scenario = openArena()
        scenario.allies = [Vec2(400, 500)]
        let sim = Simulation(scenario: scenario)
        sim.units[0].flux = 200
        return sim
    }

    var ally: UnitID { UnitID(rawValue: 1) }

    @Test func firstDonationSendsQuarterAsMana() {
        let sim = sim()
        sim.units[1].mana = 0
        sim.submit(.donateFlux(to: ally), for: sim.localHero)
        sim.step(dt)
        #expect(abs(sim.units[1].mana - 50) < 1)
        #expect(sim.hero.flux == 150)
        #expect(sim.hero.donationsMade == 1)
    }

    @Test func onlyTwoDonationsPerMatch() {
        let sim = sim()
        for _ in 0..<3 {
            sim.units[1].mana = 0
            sim.submit(.donateFlux(to: ally), for: sim.localHero)
            sim.step(dt)
        }
        #expect(sim.hero.donationsMade == 2)
        #expect(sim.hero.flux == 75)
    }

    @Test func secondDonationGetsBonusWhenDonorDidWell() {
        let sim = sim()
        sim.units[0].kills = 3
        sim.units[0].damageDealt = 500
        sim.submit(.donateFlux(to: ally), for: sim.localHero)
        sim.step(dt)
        sim.units[1].mana = 0
        sim.submit(.donateFlux(to: ally), for: sim.localHero)
        sim.step(dt)
        #expect(abs(sim.units[1].mana - 75 * 1.1) < 1)
    }

    @Test func overflowBecomesHaste() {
        let sim = sim()
        sim.submit(.donateFlux(to: ally), for: sim.localHero)
        sim.step(dt)
        #expect(sim.units[1].hasteRemaining > 0)
    }

    @Test func cannotDonateToSelfOrEnemies() {
        var scenario = openArena()
        scenario.dummies = [.init(role: .trainingDummy, name: "Alvo", position: Vec2(500, 500))]
        let sim = Simulation(scenario: scenario)
        sim.units[0].flux = 200
        sim.submit(.donateFlux(to: sim.localHero), for: sim.localHero)
        sim.submit(.donateFlux(to: UnitID(rawValue: 1)), for: sim.localHero)
        sim.step(dt)
        #expect(sim.hero.donationsMade == 0)
    }
}

@Suite("Recall, níveis e progressão")
struct ProgressTests {
    @Test func recallTeleportsHomeAfterChannel() {
        let sim = Simulation(scenario: openArena())
        sim.place(at: Vec2(2000, 500), tough: false)
        sim.submit(.recall, for: sim.localHero)
        sim.step(RecallTuning.duration - 0.5)
        #expect(sim.hero.position.distance(to: Vec2(2000, 500)) < 1)
        sim.step(1)
        #expect(sim.hero.position.distance(to: Vec2(300, 500)) < 1)
    }

    @Test func movingCancelsRecall() {
        let sim = Simulation(scenario: openArena())
        sim.place(at: Vec2(2000, 500), tough: false)
        sim.submit(.recall, for: sim.localHero)
        sim.step(1)
        sim.setMoveAxis(Vec2(0, 1), for: sim.localHero)
        sim.step(0.2)
        sim.setMoveAxis(.zero, for: sim.localHero)
        sim.step(RecallTuning.duration)
        #expect(sim.hero.recallRemaining == nil)
        #expect(sim.hero.position.x > 1900)
    }

    @Test func killingMinionsLevelsUpAndGrowsStats() {
        var scenario = openArena()
        scenario.dummies = []
        let sim = Simulation(scenario: scenario)
        let health = sim.hero.maxHealth
        let damage = sim.hero.attack!.damage
        for _ in 0..<6 {
            sim.spawnMinion(.guardian, team: .shadow, at: Vec2(500, 500), lane: LaneProgress(waypoints: [Vec2(500, 500)], index: 0), laneIndex: 0)
            let minion = sim.units.last { $0.isMinion && $0.isAlive }!
            sim.units[minion.id.rawValue].health = 1
            sim.submit(.attack(minion.id), for: sim.localHero)
            sim.step(1.5)
        }
        #expect(sim.hero.level >= 2)
        #expect(sim.hero.maxHealth > health)
        #expect(sim.hero.attack!.damage > damage)
        #expect(sim.hero.power > 1)
    }

    @Test func accountLevelsAndRewards() {
        var account = Account()
        #expect(account.level == 1)
        #expect(!account.isRankedUnlocked)
        let won = account.apply(MatchSummary(mode: .normal, won: true, completed: true, durationSeconds: 900, creeps: 40))
        #expect(won.rewards.xp == 40 + 45 + 20 + 60)
        #expect(account.level == 2)
        #expect(won.levelsGained == 1)
        #expect(account.crystals == won.rewards.crystals + Account.levelUpCrystals)
        let quit = Account.rewards(for: MatchSummary(mode: .normal, won: false, completed: false, durationSeconds: 900, creeps: 40))
        #expect(quit.xp < won.rewards.xp / 2)
        account.xp = Account.xpToReach(Account.rankedUnlockLevel)
        #expect(account.isRankedUnlocked)
    }

    @Test func facesUnlockPerHero() {
        var account = Account()
        #expect(account.faces(of: .alaric) == [.light])
        let first = account.unlock(.shadow, for: .alaric)
        let again = account.unlock(.shadow, for: .alaric)
        #expect(first)
        #expect(!again)
        #expect(account.isFaceUnlocked(.shadow, for: .alaric))
        #expect(!account.isFaceUnlocked(.shadow, for: .lyara))
    }
}
