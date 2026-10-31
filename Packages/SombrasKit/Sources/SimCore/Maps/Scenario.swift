/// Uma rota, do lado da Luz para o lado da Sombra.
public struct Lane: Sendable {
    public let name: String
    public let waypoints: [Vec2]

    /// Os pontos na ordem em que o time anda (a Sombra percorre a rota ao contrário).
    public func waypoints(for team: Team) -> [Vec2] {
        team == .shadow ? waypoints.reversed() : waypoints
    }
}

/// Relíquia do Círculo de Eternidade: um guardião neutro num altar.
public enum RelicKind: Sendable, CaseIterable {
    case light, shadow, life, death

    /// Bônus para o time que domina a relíquia.
    public var bonus: String {
        switch self {
        case .light: "+\(Int(RelicTuning.regenBonus * 100))% regeneração de vida"
        case .life: "+\(Int(RelicTuning.regenBonus * 100))% regeneração de mana"
        case .shadow: "+\(Int(RelicTuning.heroDamageBonus * 100))% dano dos heróis"
        case .death: "+\(Int(RelicTuning.structureDamageBonus * 100))% dano em estruturas"
        }
    }
}

public struct Scenario: Sendable {
    public struct DummySpawn: Sendable {
        public let role: UnitRole
        public let name: String
        public let position: Vec2
    }

    public struct StructureSpawn: Sendable {
        public enum Kind: Sendable { case tower, nexus }
        public let kind: Kind
        public let team: Team
        /// Índice da rota (torres); -1 para o Nexus.
        public let lane: Int
        /// 0 = torre externa (mais perto do inimigo), 1 = interna, 2 = de base.
        public let tier: Int
        public let position: Vec2
    }

    public struct CampSpawn: Sendable {
        public let name: String
        public let position: Vec2
        public let monsters: [(kind: MonsterKind, offset: Vec2)]
    }

    public struct RelicSpawn: Sendable {
        public let kind: RelicKind
        public let name: String
        public let position: Vec2
    }

    public struct PortalPair: Sendable {
        public let a: Vec2
        public let b: Vec2
    }

    public let map: ArenaMap
    public let heroSpawn: Vec2
    /// Base (fonte e renascimento) do time da Sombra; sem ela, não há heróis inimigos.
    public var enemySpawn: Vec2?
    public var dummies: [DummySpawn] = []
    /// Heróis aliados parados (sem IA), para treinar a doação de Fluxo.
    public var allies: [Vec2] = []
    public var lanes: [Lane] = []
    public var structures: [StructureSpawn] = []
    public var camps: [CampSpawn] = []
    public var relics: [RelicSpawn] = []
    public var portals: [PortalPair] = []
    /// As bases têm fonte (cura aliados, fere invasores).
    public var fountains = false

    public init(map: ArenaMap, heroSpawn: Vec2) {
        self.map = map
        self.heroSpawn = heroSpawn
    }

    static func pillar(_ x: Double, _ y: Double, _ radius: Double) -> Obstacle {
        .circle(Circle2(center: Vec2(x, y), radius: radius))
    }

    static func wall(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Obstacle {
        .rect(Rect2(x: x, y: y, width: w, height: h))
    }

    // MARK: Arena de treino

    /// Arena de treino: um recorte de Aetheria com paredes e pilares de cristal para exercitar movimento,
    /// desvio de obstáculos e névoa de guerra, com bonecos, sentinelas e um aliado parado para doar Fluxo.
    public static let trainingGrounds: Scenario = {
        let obstacles: [Obstacle] = [
            // Muralha em L perto da base: obriga a contornar.
            wall(760, 300, 80, 700),
            wall(760, 920, 520, 80),
            // Câmara em "U" no centro (abertura para o oeste): teste de pathfinding.
            wall(1500, 1000, 600, 70),
            wall(1500, 1500, 600, 70),
            wall(2030, 1000, 70, 570),
            // Parede alta que esconde o fundo leste (névoa).
            wall(2400, 400, 80, 800),
            // Pilares de cristal
            pillar(500, 650, 38), pillar(560, 1250, 46), pillar(1100, 1500, 42),
            pillar(1300, 500, 36), pillar(1250, 1900, 50), pillar(1900, 700, 40),
            pillar(2250, 1300, 44), pillar(2700, 1700, 52), pillar(2750, 600, 40),
            pillar(800, 2000, 44), pillar(1700, 2050, 38), pillar(2400, 2050, 46),
        ]

        var scenario = Scenario(map: ArenaMap(size: Vec2(3200, 2400), obstacles: obstacles), heroSpawn: Vec2(320, 420))
        scenario.allies = [Vec2(420, 520)]
        scenario.dummies = [
            .init(role: .trainingDummy, name: "Boneco de treino", position: Vec2(1150, 650)),
            .init(role: .trainingDummy, name: "Boneco de treino", position: Vec2(1000, 1300)),
            .init(role: .sentinel, name: "Sentinela", position: Vec2(1650, 780)),
            // Dentro da câmara em "U": só se vê de perto.
            .init(role: .trainingDummy, name: "Boneco da câmara", position: Vec2(1800, 1280)),
            // Atrás da parede leste: escondido pela névoa.
            .init(role: .sentinel, name: "Sentinela oculta", position: Vec2(2780, 900)),
            .init(role: .trainingDummy, name: "Boneco distante", position: Vec2(2800, 2000)),
        ]
        return scenario
    }()

    // MARK: Aetheria

    /// Ponto a `fraction` (0...1) do comprimento de uma linha poligonal.
    public static func point(along points: [Vec2], fraction: Double) -> Vec2 {
        var total = 0.0
        for i in 1..<points.count { total += points[i - 1].distance(to: points[i]) }
        var remaining = Swift.min(Swift.max(fraction, 0), 1) * total
        for i in 1..<points.count {
            let segment = points[i - 1].distance(to: points[i])
            if remaining <= segment {
                let t = segment > 0 ? remaining / segment : 0
                return points[i - 1] + (points[i] - points[i - 1]) * t
            }
            remaining -= segment
        }
        return points[points.count - 1]
    }

    /// Distância relativa na rota (a partir da base da Luz) das torres: externa, interna e de base.
    static let towerFractions = [0.4, 0.24, 0.1]

    /// Aetheria, o mapa do modo Normal 5v5: aberto, com três rotas, duas bases, selva e relíquias.
    ///
    /// É simétrico pela diagonal (x, y) → (y, x): a base da Luz fica embaixo à esquerda (Aetherheart)
    /// e a da Sombra em cima à direita (Torre da Convergência).
    public static let aetheria: Scenario = {
        func swap(_ v: Vec2) -> Vec2 { Vec2(v.y, v.x) }

        let lanes = [
            Lane(name: "Rota de Eryndor", waypoints: [
                Vec2(520, 5000), Vec2(520, 3500), Vec2(520, 1800), Vec2(900, 900),
                Vec2(1800, 520), Vec2(3500, 520), Vec2(5000, 520),
            ]),
            Lane(name: "Véu", waypoints: [
                Vec2(700, 5300), Vec2(1500, 4500), Vec2(3000, 3000), Vec2(4500, 1500), Vec2(5300, 700),
            ]),
            Lane(name: "Planícies Cinzentas", waypoints: [
                Vec2(1000, 5480), Vec2(2500, 5480), Vec2(4200, 5480), Vec2(5100, 5100),
                Vec2(5480, 4200), Vec2(5480, 2500), Vec2(5480, 1000),
            ]),
        ]

        var structures: [StructureSpawn] = [
            StructureSpawn(kind: .nexus, team: .light, lane: -1, tier: 0, position: Vec2(450, 5550)),
            StructureSpawn(kind: .nexus, team: .shadow, lane: -1, tier: 0, position: swap(Vec2(450, 5550))),
        ]
        for (laneIndex, lane) in lanes.enumerated() {
            for (tier, fraction) in towerFractions.enumerated() {
                structures.append(StructureSpawn(
                    kind: .tower, team: .light, lane: laneIndex, tier: tier,
                    position: point(along: lane.waypoints, fraction: fraction)
                ))
                structures.append(StructureSpawn(
                    kind: .tower, team: .shadow, lane: laneIndex, tier: tier,
                    position: point(along: lane.waypoints, fraction: 1 - fraction)
                ))
            }
        }

        // Metade "de baixo" da selva (x < y); a outra metade é o espelho.
        let halfPillars: [(Double, Double, Double)] = [
            (1100, 3000, 70), (1900, 3200, 90), (2800, 3700, 100), (1000, 4100, 80),
            (2600, 5100, 70), (3900, 5000, 90), (1700, 2100, 90), (3000, 4300, 80),
        ]
        let halfWalls: [(Double, Double, Double, Double)] = [(1200, 3500, 60, 260), (2800, 4700, 300, 60)]
        var obstacles: [Obstacle] = []
        for (x, y, r) in halfPillars { obstacles += [pillar(x, y, r), pillar(y, x, r)] }
        for (x, y, w, h) in halfWalls { obstacles += [wall(x, y, w, h), wall(y, x, h, w)] }

        let halfCamps: [(String, Double, Double)] = [
            ("Ruínas do Oeste", 1500, 3300), ("Clareira Cinzenta", 2300, 2600),
            ("Fosso da Base", 2300, 4800), ("Toca do Sul", 3300, 4400),
        ]
        func camp(_ name: String, _ x: Double, _ y: Double) -> CampSpawn {
            CampSpawn(name: name, position: Vec2(x, y), monsters: [
                (.beast, Vec2(0, 0)), (.cub, Vec2(-60, 40)), (.cub, Vec2(60, 40)),
            ])
        }

        // Bases no canto, atrás de cada Nexus: a fonte cura quem chega e não alcança o Nexus.
        var scenario = Scenario(map: ArenaMap(size: Vec2(6000, 6000), obstacles: obstacles), heroSpawn: Vec2(180, 5820))
        scenario.enemySpawn = swap(Vec2(180, 5820))
        scenario.fountains = true
        scenario.lanes = lanes
        scenario.structures = structures
        scenario.camps = halfCamps.flatMap { [camp($0.0, $0.1, $0.2), camp("\($0.0) (espelho)", $0.2, $0.1)] }
        // Duas relíquias no rio (sobre a diagonal, à mesma distância das duas bases), disputadas,
        // e uma no lado de cada time. Duas dão a Convergência: a do seu lado sozinha não basta.
        scenario.relics = [
            RelicSpawn(kind: .light, name: "Templo da Aurora", position: Vec2(1500, 1500)),
            RelicSpawn(kind: .death, name: "Catacumbas de Tharlin", position: Vec2(4300, 4300)),
            RelicSpawn(kind: .life, name: "Bosque de Eldara", position: Vec2(1100, 2400)),
            RelicSpawn(kind: .shadow, name: "Abismo de Nihil", position: swap(Vec2(1100, 2400))),
        ]
        // Atalho do Véu entre as duas relíquias do rio.
        scenario.portals = [PortalPair(a: Vec2(2000, 2000), b: Vec2(4000, 4000))]
        return scenario
    }()
}
