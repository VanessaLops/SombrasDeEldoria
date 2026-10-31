// Todo número de balanceamento que não é de herói mora aqui, nunca espalhado pela lógica.

/// Parâmetros de inimigos de treino.
public enum DummyTuning {
    public static let radius = 24.0
    public static let maxHealth = 900.0
    public static let armor = 20.0
    /// Segundos sem apanhar até começar a se recuperar.
    public static let recoveryDelay = 3.0
    public static let recoveryPerSecond = 300.0
    public static let respawnTime = 6.0
    public static let goldReward = 25.0
    /// Abates necessários no Treino para concluí-lo (e liberar a outra face do Alaric).
    public static let trainingGoal = 3

    public static let sentinelAttack = AttackProfile(
        range: 330, damage: 34, damageType: .physical,
        windup: 0.35, cooldown: 1.5, projectileSpeed: 700
    )
}

/// Fluxo de Éter e doações entre aliados (ver `docs/DIFERENCIAL.md`, decisões D4 e D7).
public enum FluxTuning {
    public static let max = 300.0
    /// Fluxo ganho ao dar o golpe final num esbirro, monstro ou boneco.
    public static let perKill = 60.0
    public static let maxDonations = 2
    /// Fração do Fluxo carregado enviada em cada doação: a primeira é baixa.
    public static let firstShare = 0.25
    public static let secondShare = 0.5
    /// Bônus da 2ª doação para quem foi bem na partida (+10%).
    public static let performanceBonus = 0.1
    /// "Foi bem": mais abates que mortes e dano mínimo causado.
    public static let goodDamage = 300.0
    /// Excesso de mana vira Surto: segundos por ponto de Fluxo, teto e fator de recarga.
    public static let hastePerFlux = 0.04
    public static let hasteMax = 8.0
    public static let hasteCooldownFactor = 1.4
}

public struct MinionStats: Sendable {
    public let radius: Double
    public let maxHealth: Double
    public let armor: Double
    public let magicResist: Double
    public let moveSpeed: Double
    public let gold: Double
    public let xp: Double
    public let attack: AttackProfile
}

public enum MinionTuning {
    /// Distância em que um esbirro larga a rota para atacar.
    public static let aggro = 450.0
    /// Distância máxima do alvo antes de desistir e voltar à rota.
    public static let leash = 700.0
    public static let sightRadius = 380.0
    /// Esbirros são o que derruba torres: dano multiplicado contra estruturas.
    public static let structureDamageMult = 2.0

    public static let guardian = MinionStats(
        radius: 16, maxHealth: 430, armor: 10, magicResist: 0, moveSpeed: 210, gold: 20, xp: 28,
        attack: AttackProfile(range: 40, damage: 22, damageType: .physical, windup: 0.15, cooldown: 1, projectileSpeed: 1400)
    )
    public static let weaver = MinionStats(
        radius: 14, maxHealth: 300, armor: 0, magicResist: 0, moveSpeed: 210, gold: 20, xp: 24,
        attack: AttackProfile(range: 280, damage: 26, damageType: .magic, windup: 0.2, cooldown: 1.1, projectileSpeed: 900)
    )

    public static func stats(_ kind: MinionKind) -> MinionStats {
        kind == .guardian ? guardian : weaver
    }
}

/// Ondas: primeira aos 8 s e depois a cada 30 s, em cada rota, para os dois times.
public enum WaveTuning {
    public static let first = 8.0
    public static let interval = 30.0
    /// Guardiões na frente, depois Tecelões.
    public static let composition: [MinionKind] = [.guardian, .guardian, .guardian, .weaver, .weaver]
    public static let spacing = 55.0
    /// Onda reforçada numa rota cuja torre de base inimiga já caiu.
    public static let empoweredHealth = 1.5
    public static let empoweredDamage = 1.5
    /// Maré do fim de jogo: depois que a Convergência se abre para todos, cada minuto deixa as ondas
    /// mais fortes (vida e dano), para nenhuma partida se arrastar.
    public static let lateGrowthPerMinute = 0.08
}

public enum TowerTuning {
    public static let radius = 34.0
    public static let maxHealth = 2000.0
    public static let armor = 60.0
    public static let magicResist = 60.0
    public static let sightRadius = 800.0
    public static let gold = 150.0
    public static let xp = 120.0
    public static let attack = AttackProfile(
        range: 620, damage: 150, damageType: .physical, windup: 0.2, cooldown: 1.1, projectileSpeed: 1500
    )
}

public enum NexusTuning {
    public static let radius = 70.0
    public static let maxHealth = 3500.0
    public static let armor = 40.0
    public static let magicResist = 40.0
    public static let sightRadius = 700.0
}

public struct MonsterStats: Sendable {
    public let radius: Double
    public let maxHealth: Double
    public let armor: Double
    public let magicResist: Double
    public let moveSpeed: Double
    public let gold: Double
    public let xp: Double
    public let respawn: Double
    public let attack: AttackProfile
}

public enum MonsterTuning {
    /// Distância de casa em que o monstro desiste da perseguição.
    public static let leash = 800.0
    /// Fração da vida recuperada por segundo ao voltar para casa.
    public static let healPerSecond = 0.25

    private static func melee(_ range: Double, _ damage: Double, _ cooldown: Double) -> AttackProfile {
        AttackProfile(range: range, damage: damage, damageType: .physical, windup: 0.15, cooldown: cooldown, projectileSpeed: 1400)
    }

    public static let beast = MonsterStats(
        radius: 26, maxHealth: 800, armor: 20, magicResist: 10, moveSpeed: 240, gold: 70, xp: 60, respawn: 60,
        attack: melee(70, 30, 1.2)
    )
    public static let cub = MonsterStats(
        radius: 18, maxHealth: 350, armor: 10, magicResist: 0, moveSpeed: 260, gold: 30, xp: 25, respawn: 60,
        attack: melee(60, 16, 1.1)
    )
    /// Guardião de Relíquia: objetivo neutro, mais forte, renasce devagar.
    public static let relic = MonsterStats(
        radius: 34, maxHealth: 2200, armor: 30, magicResist: 30, moveSpeed: 230, gold: 120, xp: 150, respawn: 90,
        attack: melee(90, 60, 1.2)
    )

    public static func stats(_ kind: MonsterKind) -> MonsterStats {
        switch kind {
        case .beast: beast
        case .cub: cub
        case .relic: relic
        }
    }
}

/// Crescimento do herói na partida: XP para subir e ganho de atributos por nível.
public enum LevelTuning {
    public static let max = 15
    /// XP para ir do nível `level` ao seguinte.
    public static func xpToNext(_ level: Int) -> Double { 100 + 45 * Double(level - 1) }
    /// Raio em que heróis do time ganham XP quando algo inimigo morre.
    public static let shareRange = 1300.0
    /// Com mais de um herói por perto, o XP é dividido, mas o grupo leva este bônus no total.
    public static let groupBonus = 1.3
    public static let heroKillXP = 120.0
    public static let heroKillXPPerLevel = 25.0
    /// Ganhos por nível, como fração do valor base.
    public static let health = 0.09
    public static let mana = 0.05
    public static let attackDamage = 0.07
    /// Dano, escudo e cura das habilidades.
    public static let abilityPower = 0.08
    /// Segundos de espera extra por nível ao morrer.
    public static let respawnPerLevel = 2.0
}

public enum HeroRewards {
    /// Ouro para quem dá o golpe final num herói.
    public static let killGold = 300.0
}

/// Retorno à base: canalização interrompida por movimento, ação ou dano.
public enum RecallTuning {
    public static let duration = 4.0
}

/// Fonte de cada base: cura quem é do time e fere invasores.
public enum FountainTuning {
    /// A fonte fica no canto, atrás do Nexus, e não o alcança (quem derruba o Nexus não é queimado).
    public static let radius = 300.0
    /// Fração da vida e da mana máximas recuperada por segundo.
    public static let healPerSecond = 0.14
    /// Dano verdadeiro por segundo em heróis inimigos dentro da fonte.
    public static let enemyDamagePerSecond = 400.0
}

/// Relíquias do Círculo de Eternidade e a Convergência (ver `docs/DIFERENCIAL.md`, seção 4).
public enum RelicTuning {
    /// Relíquias dominadas ao mesmo tempo para abrir o Nexus inimigo.
    public static let needed = 2
    /// Depois deste tempo a Convergência se abre para os dois times, para nenhuma partida travar.
    public static let fallbackTime = 12.0 * 60
    /// Bots só disputam relíquias a partir deste tempo.
    public static let botsFrom = 4.0 * 60
    public static let regenBonus = 0.5
    public static let heroDamageBonus = 0.1
    public static let structureDamageBonus = 0.25
}

/// Portais do Véu: entrar num leva ao outro.
public enum PortalTuning {
    public static let radius = 70.0
    public static let cooldown = 12.0
    public static let exitOffset = 130.0
}

/// Comportamento dos bots: cadência de decisão e limites de risco.
public enum BotTuning {
    public static let thinkInterval = 0.25
    /// Vida (fração) abaixo da qual o bot volta para a base.
    public static let retreatHealth = 0.3
    /// Distância em que o bot nota um herói inimigo.
    public static let fightRange = 750.0
    /// Distância em que o bot procura esbirros e estruturas para bater.
    public static let farmRange = 650.0
    /// Fluxo mínimo para doar a um aliado com pouca mana.
    public static let donateAt = 90.0
    /// Distância em que um bot larga a rota para ajudar um aliado que luta por uma relíquia.
    public static let relicHelpRange = 1500.0
    /// Aliados por perto para bater na torre sem esbirros tankando (empurrada em grupo).
    public static let groupPush = 2
}
