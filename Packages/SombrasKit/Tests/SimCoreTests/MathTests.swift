import Foundation
import Testing
@testable import SimCore

@Suite("Vec2, joystick e geometria")
struct MathTests {
    @Test func normalizedZeroVectorStaysZero() {
        #expect(Vec2.zero.normalized == .zero)
    }

    @Test func rotateTowardTakesShortestWay() {
        let next = Angle.rotate(3, toward: -3, maxStep: 0.1)
        #expect(next > 3)
    }

    @Test func joystickDeadZoneIsRemapped() {
        #expect(JoystickMath.axis(for: Vec2(5, 0), radius: 64, deadZone: 0.12) == .zero)
        #expect(abs(JoystickMath.axis(for: Vec2(64, 0), radius: 64, deadZone: 0.12).length - 1) < 1e-9)
    }

    @Test func pathAvoidsWalls() throws {
        let scenario = Scenario.trainingGrounds
        let nav = NavGrid(map: scenario.map, cellSize: 40, agentRadius: 18)
        // Dentro da câmara em "U" só se entra pelo oeste.
        let path = try #require(nav.findPath(from: scenario.heroSpawn, to: Vec2(1800, 1280), in: scenario.map))
        var from = scenario.heroSpawn
        for point in path {
            #expect(scenario.map.isSegmentClear(from: from, to: point, radius: 17))
            from = point
        }
    }

    @Test func fogHidesWhatIsBehindWalls() {
        let sim = Simulation()
        #expect(sim.fog.isVisible(sim.hero.position))
        #expect(!sim.isVisibleToLocalTeam(sim.first { $0.name == "Sentinela oculta" }.id))
    }
}
