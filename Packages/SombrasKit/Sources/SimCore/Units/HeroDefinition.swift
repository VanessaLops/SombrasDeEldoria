/// Os 10 campeões de lançamento (7 do livro + 3 expandidos; ver `docs/PERSONAGENS.md`).
public enum HeroID: String, Sendable, CaseIterable, Codable {
    case alaric, lyara, kaelith, eryon, saria, kaelor, nyssa, nyx, kallindra, korrath
}

public enum HeroRole: String, Sendable, CaseIterable {
    case mage, marksman, fighter, tank, assassin, support
}

/// Quão exigente é a mecânica do campeão: acertar skillshots, posicionar, combar habilidades.
public enum Difficulty: Sendable {
    case easy, medium, hard

    public var label: String {
        switch self {
        case .easy: "Fácil"
        case .medium: "Médio"
        case .hard: "Difícil"
        }
    }
}

/// Controle de grupo aplicado em quem a habilidade acerta (segundos; `slow` é a fração tirada da velocidade).
public struct CrowdControl: Sendable, Equatable {
    public var stun = 0.0
    public var root = 0.0
    public var slow = 0.0
    public var slowDuration = 0.0

    public static let none = CrowdControl()
    public static func stun(_ seconds: Double) -> CrowdControl { CrowdControl(stun: seconds) }
    public static func root(_ seconds: Double) -> CrowdControl { CrowdControl(root: seconds) }
    public static func slow(_ amount: Double, _ seconds: Double) -> CrowdControl { CrowdControl(slow: amount, slowDuration: seconds) }

    public var isNone: Bool { stun <= 0 && root <= 0 && slow <= 0 }

    var label: String {
        var parts: [String] = []
        if stun > 0 { parts.append("atordoa \(stun.formatted1)s") }
        if root > 0 { parts.append("enraíza \(root.formatted1)s") }
        if slow > 0 { parts.append("lentidão de \(Int(slow * 100))% por \(slowDuration.formatted1)s") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }
}

public enum AbilityEffect: Sendable, Equatable {
    /// Projétil em linha na direção da mira: acerta o primeiro inimigo (ou todos, com `pierce`).
    case skillshot(damage: Double, type: DamageType, range: Double, radius: Double, speed: Double, pierce: Bool = false, cc: CrowdControl = .none)
    /// Escudo em si mesmo (e cura imediata, se houver).
    case shield(amount: Double, duration: Double, heal: Double = 0)
    /// Avanço rápido na direção da mira. Com dano, fere cada inimigo do caminho uma vez;
    /// `stopOnHit` para no primeiro (investida).
    case dash(distance: Double, speed: Double, damage: Double = 0, cc: CrowdControl = .none, stopOnHit: Bool = false)
    /// Teleporte instantâneo na direção da mira.
    case blink(distance: Double)
    /// Explosão em volta de si. `heal` cura quem conjura; `allyHeal` cura também os aliados na área.
    case nova(damage: Double, type: DamageType, radius: Double, heal: Double = 0, allyHeal: Double = 0, cc: CrowdControl = .none)
    /// Golpe em leque à frente (`angle` é a abertura total, em radianos).
    case cone(damage: Double, type: DamageType, range: Double, angle: Double, cc: CrowdControl = .none)
    /// Área no chão, lançada até `range` (ou presa ao conjurador com `follow`): espera `delay` e pulsa
    /// `pulses` vezes a cada `interval`, ferindo inimigos e curando aliados (`heal`).
    case zone(damage: Double, type: DamageType, range: Double, radius: Double, delay: Double, pulses: Int, interval: Double,
              heal: Double = 0, cc: CrowdControl = .none, follow: Bool = false)
    /// Fortalece a si mesmo: velocidade de ataque, de movimento e invisibilidade (que acaba ao agir).
    case buff(duration: Double, attackSpeed: Double = 1, moveSpeed: Double = 1, stealth: Bool = false)
}

public struct AbilityDefinition: Sendable, Equatable {
    public enum Key: String, Sendable { case q = "Q", w = "W", e = "E", r = "R" }

    public let key: Key
    public let name: String
    public let manaCost: Double
    public let cooldown: Double
    public let effect: AbilityEffect

    /// Texto curto do que a habilidade faz, gerado dos números reais do kit (nunca se desatualiza).
    public var summary: String {
        switch effect {
        case let .skillshot(damage, type, range, _, _, pierce, cc):
            "Projétil\(pierce ? " perfurante" : "") (alcance \(Int(range))): \(Int(damage)) de dano \(type.label)\(cc.label)."
        case let .shield(amount, duration, heal):
            "Escudo de \(Int(amount)) por \(duration.formatted1)s" + (heal > 0 ? " e cura \(Int(heal))." : ".")
        case let .dash(distance, _, damage, cc, stopOnHit):
            damage > 0
                ? "\(stopOnHit ? "Investida" : "Avanço") de \(Int(distance)): \(Int(damage)) de dano físico\(stopOnHit ? " no primeiro inimigo" : " no caminho")\(cc.label)."
                : "Avanço de \(Int(distance)) na direção escolhida."
        case let .blink(distance):
            "Teleporta \(Int(distance)) na direção escolhida, atravessando unidades."
        case let .nova(damage, type, radius, heal, allyHeal, cc):
            "Explosão em volta (raio \(Int(radius))): \(Int(damage)) de dano \(type.label)\(cc.label)"
                + (allyHeal > 0 ? "; cura \(Int(allyHeal)) você e aliados." : heal > 0 ? "; cura \(Int(heal))." : ".")
        case let .cone(damage, type, range, angle, cc):
            "Golpe em leque (\(Int(angle * 180 / .pi))°, alcance \(Int(range))): \(Int(damage)) de dano \(type.label)\(cc.label)."
        case let .zone(damage, type, range, radius, delay, pulses, interval, heal, cc, follow):
            (follow ? "Aura em volta de você" : "Área no chão (alcance \(Int(range)))") + " de raio \(Int(radius))"
                + (delay > 0 && !follow ? ", após \(delay.formatted1)s" : "")
                + ": " + (pulses > 1 ? "\(pulses)× a cada \(interval.formatted1)s, " : "")
                + (damage > 0 ? "\(Int(damage)) de dano \(type.label)" : "")
                + (heal > 0 ? (damage > 0 ? " e " : "") + "cura \(Int(heal)) aliados" : "") + "\(cc.label)."
        case let .buff(duration, attackSpeed, moveSpeed, stealth):
            "Por \(duration.formatted1)s: " + [
                attackSpeed > 1 ? "+\(Int((attackSpeed - 1) * 100))% velocidade de ataque" : nil,
                moveSpeed > 1 ? "+\(Int((moveSpeed - 1) * 100))% velocidade" : nil,
                stealth ? "invisível (acaba ao atacar)" : nil,
            ].compactMap { $0 }.joined(separator: ", ") + "."
        }
    }

    /// Alcance útil contra um alvo (0 = só em si mesmo). Usado pela mira e pelos bots.
    public var reach: Double {
        switch effect {
        case let .skillshot(_, _, range, _, _, _, _): range
        case let .dash(distance, _, _, _, _): distance
        case let .blink(distance): distance
        case let .nova(_, _, radius, _, _, _): radius
        case let .cone(_, _, range, _, _): range
        case let .zone(_, _, range, radius, _, _, _, _, _, follow): follow ? radius : range + radius * 0.5
        case .shield, .buff: 0
        }
    }

    /// Causa dano em inimigos (para os bots decidirem quando usar).
    public var dealsDamage: Bool {
        switch effect {
        case .skillshot, .nova, .cone: true
        case let .zone(damage, _, _, _, _, _, _, _, _, _): damage > 0
        case let .dash(_, _, damage, _, _): damage > 0
        case .shield, .blink, .buff: false
        }
    }

    /// Serve para chegar perto (ou fugir).
    public var isMobility: Bool {
        switch effect {
        case .dash, .blink: true
        default: false
        }
    }
}

extension DamageType {
    public var label: String {
        switch self {
        case .physical: "físico"
        case .magic: "mágico"
        case .trueDamage: "verdadeiro"
        }
    }
}

extension Double {
    /// Uma casa decimal, sem zeros inúteis ("4", "2.5").
    var formatted1: String {
        let rounded = (self * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

/// Uma face: o estilo de luta (kit e ajustes de atributos) que o jogador escolhe no draft.
public struct FaceDefinition: Sendable {
    public let name: String
    public let style: String
    public let abilities: [AbilityDefinition]
    public let moveSpeedMult: Double
    public let armorBonus: Double
    public let magicResistBonus: Double
    public let healthRegenMult: Double
    public let attackDamageMult: Double
}

/// Dados de um herói. Todo o balanceamento fica aqui e em `Roster`, nunca espalhado pela lógica.
public struct HeroDefinition: Sendable {
    public let id: HeroID
    public let name: String
    public let title: String
    public let role: HeroRole
    /// Texto curto do papel, para a seleção de campeão.
    public let roleLabel: String
    public let difficulty: Difficulty
    /// Como o campeão joga: a mecânica que o jogador precisa dominar.
    public let playstyle: String
    /// Cor do emblema (RGB 0xRRGGBB).
    public let color: UInt32
    /// A outra face é liberada pelo Treino (só o Alaric, por enquanto).
    public let otherFaceUnlockedByTraining: Bool
    public let radius: Double
    public let sightRadius: Double
    public let maxHealth: Double
    public let maxMana: Double
    public let healthRegen: Double
    public let manaRegen: Double
    public let moveSpeed: Double
    public let armor: Double
    public let magicResist: Double
    public let attack: AttackProfile
    public let respawnTime: Double
    public let light: FaceDefinition
    public let shadow: FaceDefinition

    public func face(_ face: Face) -> FaceDefinition { face == .light ? light : shadow }

    public func abilities(_ face: Face) -> [AbilityDefinition] { self.face(face).abilities }

    public static func definition(for id: HeroID) -> HeroDefinition { Roster.heroes[id]! }

    public static let alaric = definition(for: .alaric)
}

/// Face inicial de todo herói; a outra é desbloqueada (ver `Progression`).
public let startingFace: Face = .light
