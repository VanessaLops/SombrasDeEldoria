/// Itens da loja. Como no gênero: básicos baratos viram componentes de épicos, que viram lendários;
/// comprar uma receita usa os componentes que você já tem e desconta o preço deles.
public enum ItemID: String, Sendable, CaseIterable, Codable {
    // Básicos
    case longSword, aetherTome, rubyCrystal, sapphireCrystal, clothArmor, nullMantle, dagger, boots
    // Épicos
    case serratedBlade, burningOrb, giantsBelt, swiftBoots, guardianBoots, sorcererBoots
    // Lendários
    case eclipseBlade, aetheriaScepter, lorynthAegis, eryndorBow, aetherHeart, flameCrown, shadowFang
}

/// Atributos que um item soma ao campeão.
public struct ItemStats: Sendable, Equatable {
    public var health = 0.0
    public var mana = 0.0
    public var attackDamage = 0.0
    /// Fração somada ao multiplicador das habilidades (0,2 = +20% de dano, escudo e cura).
    public var abilityPower = 0.0
    public var armor = 0.0
    public var magicResist = 0.0
    /// Fração somada à velocidade de ataque.
    public var attackSpeed = 0.0
    public var moveSpeed = 0.0
    /// Fração do dano físico causado que volta como vida.
    public var lifesteal = 0.0
    /// Fração tirada das recargas das habilidades.
    public var haste = 0.0

    static func + (a: ItemStats, b: ItemStats) -> ItemStats {
        ItemStats(
            health: a.health + b.health, mana: a.mana + b.mana, attackDamage: a.attackDamage + b.attackDamage,
            abilityPower: a.abilityPower + b.abilityPower, armor: a.armor + b.armor, magicResist: a.magicResist + b.magicResist,
            attackSpeed: a.attackSpeed + b.attackSpeed, moveSpeed: a.moveSpeed + b.moveSpeed,
            lifesteal: a.lifesteal + b.lifesteal, haste: a.haste + b.haste
        )
    }

    /// Linhas curtas para a loja ("+25 dano de ataque").
    public var lines: [String] {
        var out: [String] = []
        if attackDamage > 0 { out.append("+\(Int(attackDamage)) dano de ataque") }
        if abilityPower > 0 { out.append("+\(Int(abilityPower * 100))% poder de habilidade") }
        if health > 0 { out.append("+\(Int(health)) vida") }
        if mana > 0 { out.append("+\(Int(mana)) mana") }
        if armor > 0 { out.append("+\(Int(armor)) armadura") }
        if magicResist > 0 { out.append("+\(Int(magicResist)) resistência mágica") }
        if attackSpeed > 0 { out.append("+\(Int(attackSpeed * 100))% velocidade de ataque") }
        if moveSpeed > 0 { out.append("+\(Int(moveSpeed)) velocidade de movimento") }
        if lifesteal > 0 { out.append("+\(Int(lifesteal * 100))% roubo de vida") }
        if haste > 0 { out.append("-\(Int(haste * 100))% recarga das habilidades") }
        return out
    }
}

public struct ItemDefinition: Sendable {
    public enum Tier: Int, Sendable, Comparable {
        case basic, epic, legendary
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .basic: "Básico"
            case .epic: "Épico"
            case .legendary: "Lendário"
            }
        }
    }

    public enum Category: String, Sendable, CaseIterable {
        case attack = "Ataque", magic = "Magia", defense = "Defesa", boots = "Botas"
    }

    public let id: ItemID
    public let name: String
    /// Preço total (a receita desconta os componentes que o campeão já tem).
    public let cost: Double
    public let tier: Tier
    public let category: Category
    public let stats: ItemStats
    public let components: [ItemID]
    /// Símbolo do SF Symbols para a interface.
    public let symbol: String

    public var isBoots: Bool { category == .boots }

    public static func definition(_ id: ItemID) -> ItemDefinition { ItemCatalog.items[id]! }
}

public enum ItemCatalog {
    /// Espaços de inventário de cada campeão.
    public static let slots = 6
    /// Fração do preço devolvida ao vender.
    public static let sellBack = 0.7

    public static let items: [ItemID: ItemDefinition] = {
        func item(_ id: ItemID, _ name: String, _ cost: Double, _ tier: ItemDefinition.Tier, _ category: ItemDefinition.Category,
                  _ symbol: String, _ components: [ItemID] = [], _ stats: ItemStats) -> (ItemID, ItemDefinition) {
            (id, ItemDefinition(id: id, name: name, cost: cost, tier: tier, category: category, stats: stats, components: components, symbol: symbol))
        }
        let list: [(ItemID, ItemDefinition)] = [
            item(.longSword, "Espada Longa", 350, .basic, .attack, "line.diagonal", [], ItemStats(attackDamage: 10)),
            item(.aetherTome, "Tomo de Éter", 435, .basic, .magic, "book.closed.fill", [], ItemStats(abilityPower: 0.15)),
            item(.rubyCrystal, "Cristal de Rubi", 400, .basic, .defense, "heart.fill", [], ItemStats(health: 150)),
            item(.sapphireCrystal, "Cristal de Safira", 350, .basic, .magic, "drop.fill", [], ItemStats(mana: 250)),
            item(.clothArmor, "Cota de Malha", 300, .basic, .defense, "shield.fill", [], ItemStats(armor: 15)),
            item(.nullMantle, "Manto Nulo", 450, .basic, .defense, "cloud.fill", [], ItemStats(magicResist: 25)),
            item(.dagger, "Adaga", 300, .basic, .attack, "bolt.fill", [], ItemStats(attackSpeed: 0.12)),
            item(.boots, "Botas", 300, .basic, .boots, "shoeprints.fill", [], ItemStats(moveSpeed: 25)),

            item(.serratedBlade, "Lâmina Serrilhada", 1100, .epic, .attack, "scissors", [.longSword, .longSword], ItemStats(attackDamage: 25, haste: 0.1)),
            item(.burningOrb, "Orbe Ardente", 1200, .epic, .magic, "flame.fill", [.aetherTome], ItemStats(abilityPower: 0.35)),
            item(.giantsBelt, "Cinto do Gigante", 900, .epic, .defense, "figure.strengthtraining.traditional", [.rubyCrystal], ItemStats(health: 350)),
            item(.swiftBoots, "Botas Ligeiras", 900, .epic, .boots, "hare.fill", [.boots, .dagger], ItemStats(attackSpeed: 0.2, moveSpeed: 45)),
            item(.guardianBoots, "Botas Guardiãs", 1100, .epic, .boots, "shield.lefthalf.filled", [.boots, .clothArmor], ItemStats(armor: 20, moveSpeed: 45)),
            item(.sorcererBoots, "Botas do Feiticeiro", 1100, .epic, .boots, "sparkles", [.boots], ItemStats(abilityPower: 0.1, moveSpeed: 45, haste: 0.1)),

            item(.eclipseBlade, "Lâmina do Eclipse", 3000, .legendary, .attack, "moon.fill", [.serratedBlade, .longSword], ItemStats(attackDamage: 60, lifesteal: 0.15, haste: 0.1)),
            item(.eryndorBow, "Arco de Eryndor", 2800, .legendary, .attack, "arrow.up.right", [.dagger, .dagger, .longSword], ItemStats(attackDamage: 40, attackSpeed: 0.4)),
            item(.shadowFang, "Presa das Sombras", 2900, .legendary, .attack, "bolt.horizontal.fill", [.serratedBlade, .dagger], ItemStats(attackDamage: 50, attackSpeed: 0.25, moveSpeed: 20, haste: 0.1)),
            item(.aetheriaScepter, "Cetro de Aetheria", 3000, .legendary, .magic, "wand.and.stars", [.burningOrb, .sapphireCrystal], ItemStats(mana: 300, abilityPower: 0.8)),
            item(.flameCrown, "Coroa das Chamas", 2900, .legendary, .magic, "crown.fill", [.burningOrb, .rubyCrystal], ItemStats(health: 300, abilityPower: 0.6, haste: 0.1)),
            item(.lorynthAegis, "Égide de Lorynth", 2800, .legendary, .defense, "shield.checkered", [.giantsBelt, .clothArmor], ItemStats(health: 400, armor: 50, magicResist: 20)),
            item(.aetherHeart, "Coração de Aether", 2900, .legendary, .defense, "suit.heart.fill", [.giantsBelt, .nullMantle], ItemStats(health: 450, magicResist: 50, haste: 0.15)),
        ]
        return Dictionary(uniqueKeysWithValues: list)
    }()

    /// Ordem de exibição na loja: categoria, depois preço.
    public static let shopOrder: [ItemID] = ItemID.allCases.sorted {
        let a = definition($0), b = definition($1)
        return a.tier != b.tier ? a.tier < b.tier : a.cost < b.cost
    }

    static func definition(_ id: ItemID) -> ItemDefinition { items[id]! }

    /// Soma dos atributos de um inventário.
    public static func stats(of items: [ItemID]) -> ItemStats {
        items.reduce(ItemStats()) { $0 + definition($1).stats }
    }

    /// Build sugerida por papel, na ordem em que os bots (e a loja, como recomendação) compram.
    public static func build(for role: HeroRole) -> [ItemID] {
        switch role {
        case .mage: [.sorcererBoots, .burningOrb, .aetheriaScepter, .flameCrown, .aetherHeart, .lorynthAegis]
        case .marksman: [.swiftBoots, .eryndorBow, .eclipseBlade, .shadowFang, .lorynthAegis, .aetherHeart]
        case .fighter: [.guardianBoots, .serratedBlade, .eclipseBlade, .lorynthAegis, .shadowFang, .aetherHeart]
        case .tank: [.guardianBoots, .giantsBelt, .lorynthAegis, .aetherHeart, .flameCrown, .eclipseBlade]
        case .assassin: [.swiftBoots, .serratedBlade, .shadowFang, .eclipseBlade, .eryndorBow, .aetherHeart]
        case .support: [.sorcererBoots, .giantsBelt, .aetherHeart, .flameCrown, .aetheriaScepter, .lorynthAegis]
        }
    }

    /// Preço para quem já tem `owned`: cada componente presente (procurado em profundidade) desconta o seu valor.
    public static func price(of id: ItemID, owned: [ItemID]) -> (cost: Double, consumed: [Int]) {
        var available = Array(owned.enumerated())
        var consumed: [Int] = []
        func pay(_ id: ItemID) -> Double {
            if let index = available.firstIndex(where: { $0.element == id }) {
                consumed.append(available[index].offset)
                available.remove(at: index)
                return 0
            }
            let item = definition(id)
            let componentsCost = item.components.reduce(0.0) { $0 + definition($1).cost }
            return (item.cost - componentsCost) + item.components.reduce(0.0) { $0 + pay($1) }
        }
        let item = definition(id)
        let own = item.cost - item.components.reduce(0.0) { $0 + definition($1).cost }
        let total = own + item.components.reduce(0.0) { $0 + pay($1) }
        return (total, consumed)
    }
}

/// Economia da partida: renda passiva, recompensas e sequências de abates.
public enum GoldTuning {
    public static let starting = 500.0
    /// Renda passiva de todos os campeões, depois de `passiveFrom` segundos.
    public static let passivePerSecond = 2.0
    public static let passiveFrom = 65.0
    public static let heroKill = 300.0
    /// Ouro de assistência, dividido entre quem ajudou (dano nos últimos `assistWindow` s).
    public static let assist = 150.0
    public static let assistWindow = 10.0
    public static let firstBlood = 100.0
    /// Torre: quem derruba ganha `towerLocal`; todo o time ganha `towerGlobal`.
    public static let towerLocal = 150.0
    public static let towerGlobal = 100.0
    /// Janela para emendar abates (double, triple, quadra, penta).
    public static let multiKillWindow = 10.0
    /// Distância da base em que dá para comprar (morto também compra).
    public static let shopRadius = 700.0
}
