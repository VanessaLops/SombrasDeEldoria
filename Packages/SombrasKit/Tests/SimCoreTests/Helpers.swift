@testable import SimCore

let dt = Simulation.tickInterval

extension Simulation {
    /// Avança `seconds` sem parar no fim da partida (o `tick` já congela sozinho).
    func step(_ seconds: Double) {
        for _ in 0..<Int((seconds / dt).rounded()) { tick(dt) }
    }

    /// Herói local resistente, posicionado, com a névoa já atualizada para a nova posição.
    func place(at position: Vec2, tough: Bool = true) {
        units[localHero.rawValue].position = position
        units[localHero.rawValue].previousPosition = position
        if tough {
            units[localHero.rawValue].maxHealth = 1_000_000
            units[localHero.rawValue].health = 1_000_000
        }
        step(dt * 6)
    }

    func first(_ test: (Unit) -> Bool) -> Unit {
        units.first(where: test)!
    }

    func tower(_ team: Team, tier: Int, lane: Int) -> Unit {
        units.filter { $0.team == team && $0.role == .tower(tier: tier) }[lane]
    }

    func nexus(_ team: Team) -> Unit {
        first { $0.role == .nexus && $0.team == team }
    }

    var aliveMinions: [Unit] { units.filter { $0.isMinion && $0.isAlive } }
}

/// Arena vazia para testes de regra.
func openArena(width: Double = 3000, height: Double = 1000, hero: Vec2 = Vec2(300, 500)) -> Scenario {
    Scenario(map: ArenaMap(size: Vec2(width, height), obstacles: []), heroSpawn: hero)
}
