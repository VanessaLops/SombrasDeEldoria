import Foundation
import Testing
@testable import SimCore

@Suite("Habilidades únicas")
struct AbilityTests {
    /// Herói em (300, 500) e um boneco à frente, a `distance`.
    func duel(_ hero: HeroID, _ face: Face, distance: Double = 300) -> (Simulation, UnitID) {
        var scenario = openArena()
        scenario.dummies = [.init(role: .trainingDummy, name: "Alvo", position: Vec2(300 + distance, 500))]
        let sim = Simulation(scenario: scenario, hero: hero, face: face)
        return (sim, UnitID(rawValue: 1))
    }

    func cast(_ sim: Simulation, _ slot: Int, toward point: Vec2) {
        sim.submit(.cast(slot: slot, direction: point - sim.hero.position), for: sim.localHero)
    }

    @Test func everyHeroHasItsOwnKit() {
        var names: Set<String> = []
        for id in Roster.order {
            for face in Face.allCases {
                for ability in HeroDefinition.definition(for: id).abilities(face) { names.insert(ability.name) }
            }
        }
        #expect(names.count == Roster.order.count * 8)
        // Nem todo mundo é "projétil, escudo, avanço, explosão": os kits variam de verdade.
        let shapes = Set(Roster.order.map { id in
            HeroDefinition.definition(for: id).abilities(.light).map { "\($0.effect)".prefix(5) }.joined()
        })
        #expect(shapes.count >= 6)
    }

    @Test func skillshotStuns() {
        let (sim, dummy) = duel(.alaric, .shadow, distance: 400)
        cast(sim, 0, toward: Vec2(700, 500))
        sim.step(0.4)
        #expect(sim.units[dummy.rawValue].isStunned)
        #expect(sim.units[dummy.rawValue].health < DummyTuning.maxHealth)
    }

    @Test func piercingShotHitsEveryoneInLine() {
        var scenario = openArena()
        scenario.dummies = [
            .init(role: .trainingDummy, name: "A", position: Vec2(500, 500)),
            .init(role: .trainingDummy, name: "B", position: Vec2(700, 500)),
        ]
        let sim = Simulation(scenario: scenario, hero: .kaelith, face: .shadow)
        cast(sim, 0, toward: Vec2(900, 500))
        sim.step(0.6)
        #expect(sim.units[1].health < DummyTuning.maxHealth && sim.units[2].health < DummyTuning.maxHealth)
    }

    @Test func rootStopsMovementButNotCasting() {
        let (sim, _) = duel(.eryon, .light)
        sim.units[0].rootRemaining = 1
        sim.setMoveAxis(Vec2(1, 0), for: sim.localHero)
        sim.step(0.5)
        #expect(sim.hero.position.distance(to: Vec2(300, 500)) < 1)
        cast(sim, 0, toward: Vec2(600, 500))
        sim.step(dt)
        #expect(sim.hero.abilityCooldowns[0] > 0)
    }

    @Test func stunnedHeroCannotActAndRecovers() {
        let (sim, _) = duel(.alaric, .light)
        sim.units[0].stunRemaining = 1
        cast(sim, 0, toward: Vec2(600, 500))
        sim.setMoveAxis(Vec2(1, 0), for: sim.localHero)
        sim.step(0.5)
        #expect(sim.hero.abilityCooldowns[0] == 0)
        #expect(sim.hero.position.x < 301)
        sim.step(1)
        #expect(sim.hero.position.x > 320)
    }

    @Test func slowReducesSpeed() {
        let (sim, _) = duel(.alaric, .light)
        sim.units[0].slowRemaining = 5
        sim.units[0].slowAmount = 0.5
        #expect(abs(sim.hero.currentMoveSpeed - sim.hero.moveSpeed * 0.5) < 1e-9)
    }

    @Test func coneHitsInFrontOnly() {
        var scenario = openArena()
        scenario.dummies = [
            .init(role: .trainingDummy, name: "Frente", position: Vec2(500, 500)),
            .init(role: .trainingDummy, name: "Atrás", position: Vec2(100, 500)),
        ]
        let sim = Simulation(scenario: scenario, hero: .lyara, face: .light)
        cast(sim, 0, toward: Vec2(500, 500))
        sim.step(dt * 2)
        #expect(sim.units[1].health < DummyTuning.maxHealth)
        #expect(sim.units[2].health == DummyTuning.maxHealth)
        #expect(sim.units[1].slowRemaining > 0)
    }

    @Test func groundZoneLandsWhereAimedAndPulses() {
        let (sim, dummy) = duel(.kallindra, .light, distance: 600)
        cast(sim, 3, toward: Vec2(900, 500))
        sim.step(dt * 2)
        #expect(sim.zones.count == 1)
        #expect(sim.zones[0].position.distance(to: Vec2(900, 500)) < 1)
        sim.step(0.5)
        #expect(sim.units[dummy.rawValue].health == DummyTuning.maxHealth) // ainda no atraso
        sim.step(2)
        #expect(sim.units[dummy.rawValue].health < DummyTuning.maxHealth - 150)
        #expect(sim.zones.isEmpty)
    }

    @Test func healingZoneHealsAllies() {
        var scenario = openArena()
        scenario.allies = [Vec2(700, 500)]
        let sim = Simulation(scenario: scenario, hero: .saria, face: .light)
        sim.units[1].health = 100
        cast(sim, 0, toward: Vec2(700, 500))
        sim.step(1)
        #expect(sim.units[1].health > 180)
    }

    @Test func dashChargeStopsOnFirstEnemyAndStuns() {
        let (sim, dummy) = duel(.korrath, .light, distance: 250)
        cast(sim, 2, toward: Vec2(800, 500))
        sim.step(0.5)
        #expect(sim.units[dummy.rawValue].isStunned)
        #expect(sim.hero.position.x < 560)
        #expect(sim.units[dummy.rawValue].health < DummyTuning.maxHealth)
    }

    @Test func blinkTeleportsInstantly() {
        let (sim, _) = duel(.eryon, .light)
        cast(sim, 2, toward: Vec2(300, 900))
        sim.step(dt)
        #expect(abs(sim.hero.position.y - 920) < 2)
    }

    @Test func stealthHidesFromEnemiesUntilAttacking() {
        var scenario = openArena()
        scenario.dummies = [.init(role: .sentinel, name: "S", position: Vec2(450, 500))]
        let sim = Simulation(scenario: scenario, hero: .nyx, face: .light)
        cast(sim, 1, toward: Vec2(450, 500))
        sim.step(dt)
        let health = sim.hero.health
        #expect(sim.hero.isStealthed)
        sim.step(2.5)
        #expect(sim.hero.health >= health) // a sentinela não enxerga
        sim.submit(.attack(UnitID(rawValue: 1)), for: sim.localHero)
        sim.step(1)
        #expect(!sim.hero.isStealthed)
    }

    @Test func attackSpeedBuffHitsMoreOften() {
        func hits(_ buff: Bool) -> Double {
            let (sim, dummy) = duel(.lyara, .shadow, distance: 100)
            if buff { cast(sim, 1, toward: Vec2(400, 500)) }
            sim.submit(.attack(dummy), for: sim.localHero)
            sim.step(4.5) // dentro dos 5 s do fortalecimento
            return DummyTuning.maxHealth - sim.units[dummy.rawValue].health
        }
        #expect(hits(true) > hits(false) * 1.3)
    }

    @Test func allyHealNovaHealsTeam() {
        var scenario = openArena()
        scenario.allies = [Vec2(450, 500)]
        let sim = Simulation(scenario: scenario, hero: .alaric, face: .light)
        sim.units[1].health = 100
        cast(sim, 3, toward: Vec2(400, 500))
        sim.step(dt * 2)
        #expect(sim.units[1].health > 200)
    }
}
