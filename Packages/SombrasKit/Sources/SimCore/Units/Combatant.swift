public struct UnitID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: UnitID, rhs: UnitID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "#\(rawValue)" }
}

public enum Team: Sendable, Hashable, CaseIterable {
    /// Guardiões da Luz (base em Aetherheart).
    case light
    /// Sombras do Abismo (base na Torre da Convergência).
    case shadow
    /// Monstros da selva e guardiões de relíquia: não são de ninguém.
    case neutral

    /// Time adversário. Neutros não têm adversário fixo (devolvem a si mesmos).
    public var opponent: Team {
        switch self {
        case .light: .shadow
        case .shadow: .light
        case .neutral: .neutral
        }
    }
}

/// Estilo de luta do herói, escolhido na seleção de campeão e fixo durante a partida.
public enum Face: String, Sendable, Hashable, CaseIterable, Codable {
    case light, shadow

    public var other: Face { self == .light ? .shadow : .light }
    public var displayName: String { self == .light ? "Luz" : "Sombra" }
}

public enum MinionKind: Sendable, Equatable {
    /// Linha de frente, corpo a corpo.
    case guardian
    /// Atira de longe, frágil.
    case weaver
}

public enum MonsterKind: Sendable, Equatable {
    case beast, cub
    /// Guardião de uma Relíquia do Círculo de Eternidade.
    case relic
}

public enum UnitRole: Sendable, Equatable {
    case hero(HeroID)
    /// Boneco parado que só apanha e se recupera sozinho.
    case trainingDummy
    /// Torreta que ataca quem entra no alcance: testa vida do herói e kiting.
    case sentinel
    case minion(MinionKind)
    /// Torre de rota; `tier` 0 = externa, 1 = interna, 2 = de base.
    case tower(tier: Int)
    /// Torre da Convergência: cair encerra a partida.
    case nexus
    case monster(MonsterKind)
}

public enum DamageType: Sendable, Equatable {
    case physical, magic, trueDamage
}

public struct AttackProfile: Sendable, Equatable {
    public var range: Double
    public var damage: Double
    public var damageType: DamageType
    /// Tempo entre o início do golpe e o disparo. Mover-se antes disso cancela o ataque.
    public var windup: Double
    /// Tempo mínimo entre dois inícios de ataque (1 / velocidade de ataque).
    public var cooldown: Double
    public var projectileSpeed: Double

    public init(
        range: Double, damage: Double, damageType: DamageType,
        windup: Double, cooldown: Double, projectileSpeed: Double
    ) {
        self.range = range
        self.damage = damage
        self.damageType = damageType
        self.windup = windup
        self.cooldown = cooldown
        self.projectileSpeed = projectileSpeed
    }

    /// Até este alcance o ataque é golpe (acerta na hora, sem projétil).
    public static let meleeRange = 200.0
    public var isMelee: Bool { range <= Self.meleeRange }
}

/// Investida em andamento: sobrepõe todo o controle até acabar. Com dano, fere cada inimigo do caminho uma vez.
public struct Dash: Sendable, Equatable {
    public var direction: Vec2
    public var remaining: Double
    public var speed: Double
    public var damage = 0.0
    public var cc = CrowdControl.none
    public var stopOnHit = false
    public var hit: [UnitID] = []
}

/// Área de habilidade no chão (ou presa a quem conjurou) que pulsa dano e cura.
public struct Zone: Sendable {
    public let id: Int
    public let source: UnitID
    public let team: Team
    public var position: Vec2
    public let radius: Double
    /// Segundos até o próximo pulso; o primeiro espera o atraso da habilidade.
    public var timer: Double
    public var pulsesLeft: Int
    public let interval: Double
    public let damage: Double
    public let damageType: DamageType
    public let heal: Double
    public let cc: CrowdControl
    public let follow: Bool
    /// Segundos de vida, para o desenho.
    public var age = 0.0
}

/// Estado de uma unidade na simulação. É um valor: copiar é seguro e barato.
public struct Unit: Sendable {
    public let id: UnitID
    public let role: UnitRole
    public let team: Team
    /// Só heróis têm face; nenhum comando a altera.
    public let face: Face?
    public let name: String
    public let radius: Double
    public internal(set) var spawnPoint: Vec2
    public let sightRadius: Double
    /// Armadura e resistência mudam com os itens dos campeões.
    public internal(set) var armor: Double
    public internal(set) var magicResist: Double

    // Posição e orientação. `previousPosition` serve à interpolação visual entre ticks.
    public var position: Vec2
    public var previousPosition: Vec2
    public var facing: Double

    // Atributos
    public var maxHealth: Double
    public var health: Double
    public var maxMana: Double
    public var mana: Double
    public var healthRegen: Double
    public var manaRegen: Double
    public var moveSpeed: Double
    public var attack: AttackProfile?

    // Estado de combate
    public var isAlive = true
    public var respawnRemaining = 0.0
    public var targetID: UnitID?
    /// Segundos restantes do golpe em andamento; `nil` fora de um ataque.
    public var windupRemaining: Double?
    public var cooldownRemaining = 0.0
    public var timeSinceDamage = 100.0

    // Ordens (preenchidas pelo input e pela IA)
    public var inputAxis: Vec2 = .zero
    public var attackHeld = false
    public var moveGoal: Vec2?
    var path: [Vec2] = []
    var repathIn = 0.0

    // Habilidades
    /// Recarga restante de cada habilidade (Q, W, E, R), em segundos.
    public var abilityCooldowns: [Double] = [0, 0, 0, 0]
    public var shield = 0.0
    public var shieldRemaining = 0.0
    public var dash: Dash?

    // Controle de grupo e fortalecimentos
    /// Atordoado: não anda, não ataca, não conjura.
    public var stunRemaining = 0.0
    /// Enraizado: não anda (ainda ataca e conjura o que não for movimento).
    public var rootRemaining = 0.0
    public var slowRemaining = 0.0
    /// Fração da velocidade tirada pela lentidão.
    public var slowAmount = 0.0
    public var buffRemaining = 0.0
    public var attackSpeedMult = 1.0
    public var moveSpeedMult = 1.0
    /// Invisível para os inimigos; acaba ao atacar ou conjurar.
    public var stealthRemaining = 0.0

    /// Velocidade de movimento agora (fortalecimento e lentidão aplicados).
    public var currentMoveSpeed: Double {
        moveSpeed * (buffRemaining > 0 ? moveSpeedMult : 1) * (slowRemaining > 0 ? 1 - slowAmount : 1)
    }
    public var isStunned: Bool { stunRemaining > 0 }
    public var canMove: Bool { stunRemaining <= 0 && rootRemaining <= 0 }
    public var isStealthed: Bool { stealthRemaining > 0 }

    // Fluxo de Éter
    /// Fluxo carregado (vem do golpe final em esbirros e monstros) e quantas doações já fez.
    public var flux = 0.0
    public var donationsMade = 0
    /// Surto de Éter: segundos restantes de recarga acelerada, recebido por doação.
    public var hasteRemaining = 0.0

    // Progresso na partida
    public var level = 1
    /// XP acumulado dentro do nível atual.
    public var xp = 0.0
    /// Multiplicador de dano, escudo e cura das habilidades (cresce com o nível).
    public var power = 1.0
    /// Ouro disponível para gastar na loja.
    public var gold = 0.0
    /// Ouro ganho na partida inteira (placar).
    public var goldEarned = 0.0
    /// Inventário (até `ItemCatalog.slots` itens).
    public internal(set) var items: [ItemID] = []
    public internal(set) var lifesteal = 0.0
    /// Fração tirada das recargas das habilidades (itens).
    public internal(set) var haste = 0.0
    public var assists = 0
    /// Sequência de abates de heróis: quantos emendados e quando foi o último.
    public var multiKill = 0
    public var lastKillTime = -100.0
    /// Heróis que causaram dano neste recentemente (para assistências): quem e quando.
    var recentAttackers: [(id: UnitID, time: Double)] = []
    /// Retorno à base em andamento: segundos restantes; `nil` fora de um retorno.
    public var recallRemaining: Double?
    /// Segundos até poder usar um portal do Véu de novo.
    public var portalCooldown = 0.0

    // Mapa
    /// Rota que o esbirro segue.
    public var lane: LaneProgress?
    /// Grupo do monstro (o acampamento inteiro reage junto) ou rota do esbirro.
    public var camp: String?
    /// Guardião de relíquia: índice da relíquia que protege.
    public var relic: Int?
    /// Estrutura protegida: só pode ser alvo depois que alguma destas unidades morrer.
    public var requiresAnyDead: [UnitID]?

    // Desempenho na partida
    public var kills = 0
    public var deaths = 0
    public var damageDealt = 0.0

    public var healthFraction: Double { maxHealth > 0 ? health / maxHealth : 0 }
    public var manaFraction: Double { maxMana > 0 ? mana / maxMana : 0 }
    public var isHero: Bool {
        if case .hero = role { return true }
        return false
    }
    public var heroID: HeroID? {
        if case .hero(let id) = role { return id }
        return nil
    }
    public var isStructure: Bool {
        switch role {
        case .tower, .nexus: true
        default: false
        }
    }
    public var isMinion: Bool {
        if case .minion = role { return true }
        return false
    }
    public var isMonster: Bool {
        if case .monster = role { return true }
        return false
    }

    init(
        id: UnitID, role: UnitRole, team: Team, face: Face? = nil, name: String, position: Vec2,
        radius: Double, sightRadius: Double, armor: Double, magicResist: Double,
        maxHealth: Double, maxMana: Double, healthRegen: Double, manaRegen: Double,
        moveSpeed: Double, attack: AttackProfile?
    ) {
        self.id = id
        self.role = role
        self.team = team
        self.face = face
        self.name = name
        self.position = position
        previousPosition = position
        spawnPoint = position
        facing = team == .shadow ? .pi : 0
        self.radius = radius
        self.sightRadius = sightRadius
        self.armor = armor
        self.magicResist = magicResist
        self.maxHealth = maxHealth
        health = maxHealth
        self.maxMana = maxMana
        mana = maxMana
        self.healthRegen = healthRegen
        self.manaRegen = manaRegen
        self.moveSpeed = moveSpeed
        self.attack = attack
    }
}

/// Progresso de um esbirro pela rota: lista de pontos e o próximo alvo.
public struct LaneProgress: Sendable {
    public let waypoints: [Vec2]
    public var index: Int
}

public struct Projectile: Sendable {
    public let id: Int
    public let source: UnitID
    /// Alvo perseguido; `nil` em habilidades direcionais (skillshots).
    public let target: UnitID?
    public let team: Team
    public var position: Vec2
    public var previousPosition: Vec2
    public let speed: Double
    public let damage: Double
    public let damageType: DamageType
    /// Só skillshots: direção, alcance restante e raio de acerto.
    public let direction: Vec2?
    public var rangeLeft: Double
    public let hitRadius: Double
    /// Skillshot perfurante: atravessa todos e guarda quem já acertou.
    public var pierce = false
    public var hit: [UnitID] = []
    public var cc = CrowdControl.none

    public var isSkillshot: Bool { target == nil }
}

/// Fatos ocorridos na simulação. A simulação *emite*; cena, HUD e áudio *reagem*.
public enum SimEvent: Sendable, Equatable {
    case attackStarted(attacker: UnitID, target: UnitID)
    case damaged(target: UnitID, source: UnitID, amount: Double, position: Vec2, remainingFraction: Double)
    case killed(target: UnitID, killer: UnitID)
    case respawned(UnitID)
    case moveOrdered(to: Vec2)
    case cast(unit: UnitID, slot: Int, position: Vec2)
    /// Pulso de uma área de habilidade (dano/cura), para o desenho.
    case zonePulse(position: Vec2, radius: Double, team: Team)
    /// Alguém foi atordoado, enraizado ou desacelerado.
    case crowdControlled(UnitID)
    case donated(from: UnitID, to: UnitID, amount: Double, position: Vec2)
    case structureDestroyed(UnitID, team: Team)
    case levelUp(UnitID, level: Int)
    case recallStarted(UnitID)
    case recalled(UnitID, from: Vec2, to: Vec2)
    case teleported(UnitID, from: Vec2, to: Vec2)
    case relicCaptured(relic: Int, team: Team)
    case purchased(UnitID, item: ItemID)
    case sold(UnitID, item: ItemID)
    /// Abates emendados de um herói: 2 = double kill … 5 = pentakill.
    case multiKill(UnitID, count: Int)
    case firstBlood(UnitID)
    case matchEnded(winner: Team)
}

/// Desempenho do herói local na partida.
public struct MatchStats: Sendable, Equatable {
    public var kills = 0
    public var deaths = 0
    public var damageDealt = 0.0
    public var gold = 0.0
    /// Esbirros e monstros abatidos pelo herói local.
    public var creeps = 0
    public var assists = 0

    public init() {}
}
