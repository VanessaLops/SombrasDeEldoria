/// Modos de jogo do lobby.
public enum GameMode: String, Sendable, Codable, CaseIterable {
    case normal, training, ranked
}

/// Resumo de uma partida para calcular a recompensa.
public struct MatchSummary: Sendable, Equatable {
    public let mode: GameMode
    public let won: Bool
    /// `false` = o jogador saiu antes do fim (recompensa pela metade, sem bônus de vitória).
    public let completed: Bool
    public let durationSeconds: Double
    public let creeps: Int

    public init(mode: GameMode, won: Bool, completed: Bool, durationSeconds: Double, creeps: Int) {
        self.mode = mode
        self.won = won
        self.completed = completed
        self.durationSeconds = durationSeconds
        self.creeps = creeps
    }
}

public struct Rewards: Sendable, Equatable {
    public let xp: Int
    public let crystals: Int
}

/// Conta do jogador: XP total, cristais, partidas jogadas e faces liberadas por herói.
/// O nível é derivado do XP. É um valor puro; quem grava é o app.
public struct Account: Sendable, Equatable, Codable {
    public var xp = 0
    public var crystals = 0
    public var matches = 0
    public var wins = 0
    /// Faces além da inicial, por herói.
    public var unlockedFaces: [HeroID: [Face]] = [:]

    public init() {}

    /// Nível mínimo da conta para jogar Rankeada. Normal e Treino ficam liberados desde o início.
    public static let rankedUnlockLevel = 4
    /// Cristais de bônus a cada nível ganho.
    public static let levelUpCrystals = 20
    /// Tempo mínimo (s) para sair no meio e ainda ganhar a recompensa parcial.
    public static let minimumPlayForReward = 30.0

    /// XP total necessário para ALCANÇAR o nível `n` (nível 1 = 0; 2 = 100; 3 = 300; 4 = 600; ...).
    public static func xpToReach(_ level: Int) -> Int { 50 * level * (level - 1) }

    public var level: Int {
        var level = 1
        while Self.xpToReach(level + 1) <= xp { level += 1 }
        return level
    }

    /// Progresso dentro do nível atual: XP ganho no nível e XP que o nível pede.
    public var levelProgress: (into: Int, needed: Int) {
        (xp - Self.xpToReach(level), Self.xpToReach(level + 1) - Self.xpToReach(level))
    }

    public var isRankedUnlocked: Bool { level >= Self.rankedUnlockLevel }

    public func faces(of hero: HeroID) -> [Face] {
        [startingFace] + (unlockedFaces[hero] ?? []).filter { $0 != startingFace }
    }

    public func isFaceUnlocked(_ face: Face, for hero: HeroID) -> Bool {
        faces(of: hero).contains(face)
    }

    /// Libera uma face. Devolve `false` se já estava liberada.
    @discardableResult
    public mutating func unlock(_ face: Face, for hero: HeroID) -> Bool {
        guard !isFaceUnlocked(face, for: hero) else { return false }
        unlockedFaces[hero, default: []].append(face)
        return true
    }

    /// Toda partida rende XP e cristais; vencer rende mais, e sair no meio rende metade.
    public static func rewards(for match: MatchSummary) -> Rewards {
        if match.mode == .training {
            return match.completed ? Rewards(xp: 40, crystals: 10) : Rewards(xp: 15, crystals: 3)
        }
        let won = match.won && match.completed
        let minutes = Double(Swift.min(Int(match.durationSeconds / 60), 20))
        let farm = Double(Swift.min(match.creeps, 60))
        var xp = 40 + minutes * 3 + farm * 0.5 + (won ? 60 : 0)
        var crystals = 10 + (farm / 10).rounded() + (won ? 20 : 0)
        if !match.completed {
            xp *= 0.5
            crystals *= 0.5
        }
        return Rewards(xp: Int(xp.rounded()), crystals: Int(crystals.rounded()))
    }

    public struct Applied: Sendable, Equatable {
        public let rewards: Rewards
        /// Níveis ganhos nesta partida.
        public let levelsGained: Int
        /// Cristais de bônus por subir de nível (já somados à conta).
        public let levelBonus: Int
    }

    /// Soma as recompensas da partida à conta.
    @discardableResult
    public mutating func apply(_ match: MatchSummary) -> Applied {
        let rewards = Self.rewards(for: match)
        let before = level
        xp += rewards.xp
        let gained = level - before
        let bonus = gained * Self.levelUpCrystals
        crystals += rewards.crystals + bonus
        matches += 1
        if match.won && match.completed && match.mode != .training { wins += 1 }
        return Applied(rewards: rewards, levelsGained: gained, levelBonus: bonus)
    }
}
