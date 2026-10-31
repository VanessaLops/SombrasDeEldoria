/// Gerador pseudoaleatório determinístico (SplitMix64): mesma semente, mesma partida.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct HeroPick: Sendable, Equatable {
    public let hero: HeroID
    public let face: Face

    public init(hero: HeroID, face: Face) {
        self.hero = hero
        self.face = face
    }
}

/// Posto de um herói no mapa: uma rota (índice) ou a selva.
public enum Post: Sendable, Equatable {
    case lane(Int)
    case jungle

    public var label: String {
        switch self {
        case .lane(0): "Rota de Eryndor"
        case .lane(1): "Véu (meio)"
        case .lane(2): "Planícies Cinzentas"
        case .lane(let n): "Rota \(n + 1)"
        case .jungle: "Selva"
        }
    }
}

/// Times de uma partida contra bots.
public struct Lineup: Sendable, Equatable {
    public let allies: [HeroPick]
    public let enemies: [HeroPick]

    public init(allies: [HeroPick], enemies: [HeroPick]) {
        self.allies = allies
        self.enemies = enemies
    }

    /// Os 10 campeões divididos entre os dois lados (o do jogador fica no time dele), cada bot com uma
    /// face sorteada. A mesma semente dá sempre os mesmos times.
    public static func random(player: HeroID, seed: UInt64) -> Lineup {
        var random = SeededRandom(seed: seed)
        let pool = Roster.order.filter { $0 != player }.shuffled(using: &random)
        let pick = { (hero: HeroID, random: inout SeededRandom) in
            HeroPick(hero: hero, face: Bool.random(using: &random) ? .light : .shadow)
        }
        var allies: [HeroPick] = []
        var enemies: [HeroPick] = []
        for hero in pool.prefix(4) { allies.append(pick(hero, &random)) }
        for hero in pool.dropFirst(4).prefix(5) { enemies.append(pick(hero, &random)) }
        return Lineup(allies: allies, enemies: enemies)
    }

    /// Postos de um time completo: rota de Eryndor, Véu (meio), duas nas Planícies e a selva.
    public static let teamPosts: [Post] = [.lane(0), .lane(1), .lane(2), .lane(2), .jungle]

    /// O jogador fica com o Véu (meio); os bots aliados ocupam o resto.
    public static let playerPost: Post = .lane(1)

    /// Postos livres de um time, tirando o do jogador (se ele joga).
    public static func freePosts(withPlayer: Bool) -> [Post] {
        var posts = teamPosts
        if withPlayer, let index = posts.firstIndex(of: playerPost) { posts.remove(at: index) }
        return posts
    }

    /// Preferência de posto por papel, da mais forte para a mais fraca.
    static func preference(_ role: HeroRole) -> [Post] {
        switch role {
        case .mage: [.lane(1), .lane(0), .lane(2), .jungle]
        case .marksman, .support: [.lane(2), .lane(1), .lane(0), .jungle]
        case .fighter: [.lane(0), .jungle, .lane(1), .lane(2)]
        case .tank: [.lane(0), .lane(2), .jungle, .lane(1)]
        case .assassin: [.jungle, .lane(1), .lane(0), .lane(2)]
        }
    }

    /// Distribui os postos pelos heróis, respeitando a preferência de cada papel (determinístico).
    public static func assignPosts(_ heroes: [HeroID], posts: [Post]) -> [Post] {
        var free = posts
        var result: [Post?] = Array(repeating: nil, count: heroes.count)
        for rank in 0..<4 {
            for (i, hero) in heroes.enumerated() where result[i] == nil {
                let wanted = preference(HeroDefinition.definition(for: hero).role)[rank]
                if let at = free.firstIndex(of: wanted) { result[i] = free.remove(at: at) }
            }
        }
        return result.map { post in
            if let post { return post }
            return free.isEmpty ? .lane(1) : free.removeFirst()
        }
    }
}
