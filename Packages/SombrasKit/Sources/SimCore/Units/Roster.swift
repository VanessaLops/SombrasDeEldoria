// Os 10 campeões de lançamento. Todo número de balanceamento dos heróis mora aqui.
//
// Cada campeão tem um kit próprio em cada face, com a mecânica que o livro sugere: a Luz sustenta e
// controla (escudos, cura, raízes, atordoamento), a Sombra agride (dano, mobilidade, invisibilidade).
// As teclas seguem o padrão do gênero: Q = habilidade principal, W = defesa/utilidade, E = mobilidade,
// R = ultimate.

public enum Roster {
    public static let order: [HeroID] = [
        .alaric, .lyara, .kaelith, .eryon, .saria, .kaelor, .nyssa, .nyx, .kallindra, .korrath,
    ]

    public static let heroes: [HeroID: HeroDefinition] = {
        var all: [HeroID: HeroDefinition] = [:]
        for spec in specs { all[spec.id] = build(spec) }
        return all
    }()

    // MARK: Faces

    static func faceMods(_ face: Face, abilities: [AbilityDefinition]) -> FaceDefinition {
        switch face {
        case .light:
            FaceDefinition(
                name: "Luz", style: "Sustentação: escudos, cura e controle de espaço", abilities: abilities,
                moveSpeedMult: 1, armorBonus: 6, magicResistBonus: 6, healthRegenMult: 1.5, attackDamageMult: 1
            )
        case .shadow:
            FaceDefinition(
                name: "Sombra", style: "Agressão: dano, mobilidade e emboscada", abilities: abilities,
                moveSpeedMult: 1.08, armorBonus: 0, magicResistBonus: 0, healthRegenMult: 1, attackDamageMult: 1.1
            )
        }
    }

    // MARK: Construção

    static func ranged(_ range: Double, _ damage: Double, _ type: DamageType, _ cooldown: Double, _ speed: Double) -> AttackProfile {
        AttackProfile(range: range, damage: damage, damageType: type, windup: 0.2, cooldown: cooldown, projectileSpeed: speed)
    }

    static func melee(_ range: Double, _ damage: Double, _ cooldown: Double) -> AttackProfile {
        AttackProfile(range: range, damage: damage, damageType: .physical, windup: 0.18, cooldown: cooldown, projectileSpeed: 1600)
    }

    static func deg(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Uma habilidade: nome, mana, recarga e efeito. A tecla vem da posição no kit.
    typealias Spell = (name: String, mana: Double, cooldown: Double, effect: AbilityEffect)

    static func kit(_ spells: [Spell]) -> [AbilityDefinition] {
        let keys: [AbilityDefinition.Key] = [.q, .w, .e, .r]
        return spells.enumerated().map { index, spell in
            AbilityDefinition(key: keys[index], name: spell.name, manaCost: spell.mana, cooldown: spell.cooldown, effect: spell.effect)
        }
    }

    struct Spec {
        let id: HeroID
        let name: String
        let title: String
        let role: HeroRole
        let roleLabel: String
        let difficulty: Difficulty
        let playstyle: String
        let color: UInt32
        var unlockByTraining = false
        let radius: Double
        let maxHealth: Double
        let maxMana: Double
        let healthRegen: Double
        let manaRegen: Double
        let moveSpeed: Double
        let armor: Double
        let magicResist: Double
        let attack: AttackProfile
        let light: [Spell]
        let shadow: [Spell]
    }

    static func build(_ spec: Spec) -> HeroDefinition {
        HeroDefinition(
            id: spec.id, name: spec.name, title: spec.title, role: spec.role, roleLabel: spec.roleLabel,
            difficulty: spec.difficulty, playstyle: spec.playstyle, color: spec.color,
            otherFaceUnlockedByTraining: spec.unlockByTraining, radius: spec.radius, sightRadius: 900,
            maxHealth: spec.maxHealth, maxMana: spec.maxMana, healthRegen: spec.healthRegen, manaRegen: spec.manaRegen,
            moveSpeed: spec.moveSpeed, armor: spec.armor, magicResist: spec.magicResist, attack: spec.attack,
            respawnTime: 6,
            light: faceMods(.light, abilities: kit(spec.light)),
            shadow: faceMods(.shadow, abilities: kit(spec.shadow))
        )
    }

    // MARK: Elenco

    static let specs: [Spec] = [
        // Tecelão de Éter: lâminas cristalinas, barreiras e fios de luz que cortam sombras.
        Spec(
            id: .alaric, name: "Alaric", title: "Tecelão de Éter", role: .mage, roleLabel: "Mago · Controle", difficulty: .medium,
            playstyle: "Acerte o Feixe (Q) de longe, proteja-se com o Véu (W) e teleporte com o Passo (E). O R muda tudo: a Aurora cura o time, o Despertar cobre uma área de sombras.",
            color: 0x5B8CFF, unlockByTraining: true, radius: 18, maxHealth: 560, maxMana: 350, healthRegen: 6, manaRegen: 9,
            moveSpeed: 270, armor: 22, magicResist: 30, attack: ranged(430, 58, .magic, 0.85, 1100),
            light: [
                ("Feixe de Luz", 40, 4, .skillshot(damage: 60, type: .magic, range: 900, radius: 24, speed: 1600, pierce: true)),
                ("Véu de Luz", 50, 9, .shield(amount: 220, duration: 4)),
                ("Passo de Luz", 40, 9, .blink(distance: 340)),
                ("Aurora", 100, 34, .nova(damage: 170, type: .magic, radius: 480, allyHeal: 160, cc: .slow(0.35, 2))),
            ],
            shadow: [
                ("Lâmina de Éter", 45, 5, .skillshot(damage: 85, type: .magic, range: 800, radius: 28, speed: 1400, cc: .stun(0.8))),
                ("Barreira de Éter", 50, 9, .shield(amount: 150, duration: 3)),
                ("Passo Etéreo", 40, 7, .blink(distance: 400)),
                ("Despertar das Sombras", 100, 30, .zone(damage: 120, type: .magic, range: 650, radius: 320, delay: 0.6, pulses: 3, interval: 0.5, cc: .slow(0.4, 1))),
            ]
        ),
        // Guerreira formidável e leal: entra primeiro e segura a linha.
        Spec(
            id: .lyara, name: "Lyara", title: "Guerreira da Aurora", role: .fighter, roleLabel: "Guerreira · Frontal", difficulty: .easy,
            playstyle: "Corpo a corpo direto: entre com a Investida (E), que atordoa o primeiro inimigo, corte em leque (Q) e segure o dano com o escudo (W).",
            color: 0xFF8A5B, radius: 20, maxHealth: 640, maxMana: 250, healthRegen: 8, manaRegen: 6,
            moveSpeed: 280, armor: 32, magicResist: 28, attack: melee(125, 62, 0.8),
            light: [
                ("Golpe da Aurora", 30, 4, .cone(damage: 80, type: .physical, range: 240, angle: deg(110), cc: .slow(0.3, 1.5))),
                ("Escudo do Juramento", 40, 10, .shield(amount: 280, duration: 4, heal: 60)),
                ("Investida Leal", 35, 9, .dash(distance: 360, speed: 1400, damage: 60, cc: .stun(0.7), stopOnHit: true)),
                ("Muralha Radiante", 80, 36, .nova(damage: 160, type: .physical, radius: 420, allyHeal: 130, cc: .stun(0.6))),
            ],
            shadow: [
                ("Corte Sombrio", 30, 3.5, .cone(damage: 105, type: .physical, range: 240, angle: deg(100))),
                ("Couraça da Noite", 40, 12, .buff(duration: 5, attackSpeed: 1.5, moveSpeed: 1.1)),
                ("Salto Rubro", 35, 8, .dash(distance: 420, speed: 1600, damage: 75)),
                ("Fúria do Eclipse", 80, 32, .zone(damage: 75, type: .physical, range: 0, radius: 270, delay: 0, pulses: 5, interval: 0.4, follow: true)),
            ]
        ),
        // Caçadora do Norte de Arkanis: arco, visões e sussurros.
        Spec(
            id: .kaelith, name: "Kaelith", title: "Herdeira das Sombras", role: .marksman, roleLabel: "Atiradora · Arco", difficulty: .medium,
            playstyle: "Atiradora: mantenha distância, desacelere com a flecha (Q) e use o Passo (E) para sair do perigo. O R pune quem fica parado.",
            color: 0x8BD36B, radius: 17, maxHealth: 500, maxMana: 300, healthRegen: 5, manaRegen: 8,
            moveSpeed: 275, armor: 20, magicResist: 26, attack: ranged(520, 54, .physical, 0.7, 1500),
            light: [
                ("Flecha do Alvorecer", 40, 5, .skillshot(damage: 70, type: .physical, range: 1000, radius: 22, speed: 1900, cc: .slow(0.4, 1.5))),
                ("Visão Protetora", 45, 11, .shield(amount: 160, duration: 3, heal: 40)),
                ("Passo de Caçadora", 35, 8, .dash(distance: 300, speed: 1500)),
                ("Chuva de Estrelas", 100, 36, .zone(damage: 75, type: .physical, range: 900, radius: 320, delay: 0.5, pulses: 4, interval: 0.5, cc: .slow(0.3, 1))),
            ],
            shadow: [
                ("Flecha Sussurrante", 45, 4.5, .skillshot(damage: 90, type: .physical, range: 950, radius: 22, speed: 1900, pierce: true)),
                ("Manto de Sombras", 45, 12, .buff(duration: 5, attackSpeed: 1.6)),
                ("Salto do Lobo", 35, 8, .blink(distance: 320)),
                ("Tempestade Silenciosa", 100, 34, .skillshot(damage: 260, type: .physical, range: 1500, radius: 50, speed: 1700, pierce: true)),
            ]
        ),
        // Portador do Fluxo: tempo e espaço, instáveis.
        Spec(
            id: .eryon, name: "Eryon", title: "Portador do Fluxo", role: .assassin, roleLabel: "Assassino · Mobilidade", difficulty: .hard,
            playstyle: "Prenda o alvo com o Fio do Tempo (Q), teleporte para perto (E) e finalize com o R antes da resposta.",
            color: 0x4DD2D2, radius: 17, maxHealth: 540, maxMana: 280, healthRegen: 6, manaRegen: 8,
            moveSpeed: 295, armor: 24, magicResist: 26, attack: melee(120, 66, 0.75),
            light: [
                ("Fio do Tempo", 35, 6, .skillshot(damage: 65, type: .magic, range: 750, radius: 26, speed: 1600, cc: .root(1.2))),
                ("Dobra Protetora", 40, 9, .shield(amount: 170, duration: 2.5)),
                ("Salto Espacial", 30, 7, .blink(distance: 420)),
                ("Pulso do Fluxo", 90, 32, .nova(damage: 190, type: .magic, radius: 360, cc: .stun(1.1))),
            ],
            shadow: [
                ("Fissura Temporal", 35, 3.5, .cone(damage: 100, type: .physical, range: 300, angle: deg(70))),
                ("Eco Sombrio", 40, 10, .buff(duration: 3, attackSpeed: 1.3, moveSpeed: 1.4)),
                ("Rasgo do Espaço", 30, 6, .dash(distance: 460, speed: 1800, damage: 90)),
                ("Colapso do Fluxo", 90, 30, .zone(damage: 320, type: .magic, range: 500, radius: 300, delay: 1, pulses: 1, interval: 0, cc: .stun(1))),
            ]
        ),
        // Alquimista do Rio de Prata: poções, cura e ácidos.
        Spec(
            id: .saria, name: "Saria", title: "Alquimista do Rio de Prata", role: .support, roleLabel: "Suporte · Alquimista", difficulty: .hard,
            playstyle: "Arremesse o frasco (Q) onde estão aliados e inimigos: cura uns e queima os outros. A Chuva (R) sustenta o time inteiro numa luta longa.",
            color: 0xC58CFF, radius: 17, maxHealth: 520, maxMana: 420, healthRegen: 6, manaRegen: 12,
            moveSpeed: 270, armor: 20, magicResist: 32, attack: ranged(420, 44, .magic, 0.9, 1000),
            light: [
                ("Frasco de Cura", 45, 5, .zone(damage: 45, type: .magic, range: 800, radius: 230, delay: 0.4, pulses: 1, interval: 0, heal: 110)),
                ("Elixir Protetor", 50, 10, .shield(amount: 260, duration: 4.5, heal: 50)),
                ("Passo Alquímico", 35, 9, .dash(distance: 280, speed: 1400)),
                ("Chuva Revitalizante", 100, 34, .zone(damage: 30, type: .magic, range: 0, radius: 540, delay: 0, pulses: 5, interval: 0.8, heal: 70, follow: true)),
            ],
            shadow: [
                ("Ácido Corrosivo", 40, 4, .skillshot(damage: 70, type: .magic, range: 850, radius: 30, speed: 1300, cc: .slow(0.45, 2))),
                ("Névoa Tóxica", 50, 10, .zone(damage: 35, type: .magic, range: 0, radius: 280, delay: 0, pulses: 6, interval: 0.5, follow: true)),
                ("Fuga Efervescente", 35, 10, .buff(duration: 2.5, moveSpeed: 1.55)),
                ("Explosão Alquímica", 100, 32, .zone(damage: 230, type: .magic, range: 800, radius: 340, delay: 0.8, pulses: 1, interval: 0, cc: .stun(0.9))),
            ]
        ),
        // Arqueiro solitário, protetor das florestas.
        Spec(
            id: .kaelor, name: "Kaelor", title: "o Arqueiro", role: .marksman, roleLabel: "Atirador · Longo alcance", difficulty: .easy,
            playstyle: "Atirador de longo alcance: fique atrás da linha de frente, ataque e role (E) para escapar. O Disparo do Guardião (R) atravessa o mapa.",
            color: 0x6BBF8F, radius: 17, maxHealth: 480, maxMana: 290, healthRegen: 5, manaRegen: 8,
            moveSpeed: 270, armor: 18, magicResist: 24, attack: ranged(600, 58, .physical, 0.85, 1700),
            light: [
                ("Tiro Certeiro", 40, 4.5, .skillshot(damage: 75, type: .physical, range: 1100, radius: 20, speed: 2300)),
                ("Capa da Floresta", 45, 11, .shield(amount: 150, duration: 3)),
                ("Rolamento Ágil", 30, 7, .dash(distance: 270, speed: 1500)),
                ("Disparo do Guardião", 100, 38, .skillshot(damage: 240, type: .physical, range: 2400, radius: 45, speed: 2000, cc: .stun(1.2))),
            ],
            shadow: [
                ("Flecha Perfurante", 45, 5, .skillshot(damage: 95, type: .physical, range: 1050, radius: 20, speed: 2300, pierce: true)),
                ("Camuflagem", 50, 14, .buff(duration: 3.5, moveSpeed: 1.25, stealth: true)),
                ("Recuo Letal", 30, 7, .dash(distance: 320, speed: 1600)),
                ("Saraivada Final", 100, 34, .cone(damage: 230, type: .physical, range: 750, angle: deg(55))),
            ]
        ),
        // Mística druida das montanhas: raízes, tempestades, proteção contra sombras.
        Spec(
            id: .nyssa, name: "Nyssa", title: "a Druida", role: .support, roleLabel: "Suporte · Controle", difficulty: .medium,
            playstyle: "Segure o espaço com as Raízes (Q), proteja com a Casca (W) e decida a luta com a Tempestade (R).",
            color: 0x5BD68A, radius: 18, maxHealth: 540, maxMana: 400, healthRegen: 7, manaRegen: 11,
            moveSpeed: 268, armor: 22, magicResist: 34, attack: ranged(440, 42, .magic, 0.9, 1000),
            light: [
                ("Raízes Vivas", 45, 7, .skillshot(damage: 55, type: .magic, range: 850, radius: 34, speed: 1200, cc: .root(1.5))),
                ("Casca Protetora", 45, 10, .shield(amount: 270, duration: 4.5, heal: 60)),
                ("Passo da Folha", 35, 9, .dash(distance: 280, speed: 1400)),
                ("Tempestade da Montanha", 100, 36, .zone(damage: 60, type: .magic, range: 0, radius: 520, delay: 0, pulses: 4, interval: 0.7, heal: 55, cc: .slow(0.35, 1), follow: true)),
            ],
            shadow: [
                ("Espinhos Sombrios", 45, 6, .zone(damage: 50, type: .magic, range: 800, radius: 210, delay: 0.5, pulses: 3, interval: 0.5, cc: .slow(0.5, 1))),
                ("Hera Sombria", 45, 10, .cone(damage: 70, type: .magic, range: 420, angle: deg(60), cc: .root(1.1))),
                ("Passo da Raiz", 35, 9, .blink(distance: 300)),
                ("Trovão do Abismo", 100, 34, .nova(damage: 180, type: .magic, radius: 500, cc: .stun(1.2))),
            ]
        ),
        // Guia de manto negro, olhos como estrelas: dissolve-se em névoa.
        Spec(
            id: .nyx, name: "Nyx", title: "a Sombra que Caminha", role: .assassin, roleLabel: "Assassina · Furtividade", difficulty: .hard,
            playstyle: "Fique invisível (W), apareça atrás do alvo isolado e saia antes de ser cercada. Pouca vida: escolha bem a luta.",
            color: 0x9B6BFF, radius: 16, maxHealth: 510, maxMana: 260, healthRegen: 5, manaRegen: 8,
            moveSpeed: 300, armor: 20, magicResist: 24, attack: melee(120, 70, 0.8),
            light: [
                ("Lâmina de Névoa", 35, 5, .skillshot(damage: 75, type: .magic, range: 700, radius: 26, speed: 1600, cc: .slow(0.4, 1.5))),
                ("Manto Estelar", 45, 14, .buff(duration: 3, moveSpeed: 1.3, stealth: true)),
                ("Passo de Estrela", 30, 8, .blink(distance: 400)),
                ("Eclipse Silencioso", 90, 30, .nova(damage: 200, type: .magic, radius: 380, cc: .stun(0.8))),
            ],
            shadow: [
                ("Adaga Sombria", 35, 4, .skillshot(damage: 100, type: .physical, range: 600, radius: 22, speed: 1800)),
                ("Véu Negro", 45, 13, .buff(duration: 4, attackSpeed: 1.3, moveSpeed: 1.15, stealth: true)),
                ("Dissolver", 30, 6, .dash(distance: 460, speed: 1800, damage: 80)),
                ("Noite Eterna", 90, 30, .zone(damage: 120, type: .physical, range: 0, radius: 340, delay: 0, pulses: 3, interval: 0.5, follow: true)),
            ]
        ),
        // Alta-Maga do Conselho das Chamas, olhos dourados.
        Spec(
            id: .kallindra, name: "Kallindra", title: "Alta-Maga", role: .mage, roleLabel: "Maga · Dano em área", difficulty: .medium,
            playstyle: "Maga de fogo: acerte a Chama (Q), queime a área (W) e jogue a Pira/Inferno (R) quando o grupo inimigo estiver junto.",
            color: 0xFFB84D, radius: 18, maxHealth: 500, maxMana: 400, healthRegen: 5, manaRegen: 10,
            moveSpeed: 262, armor: 18, magicResist: 30, attack: ranged(460, 60, .magic, 0.9, 1100),
            light: [
                ("Chama Dourada", 40, 4, .skillshot(damage: 75, type: .magic, range: 850, radius: 30, speed: 1400)),
                ("Escudo de Brasas", 50, 9, .shield(amount: 230, duration: 4)),
                ("Passo Flamejante", 40, 9, .blink(distance: 320)),
                ("Pira Solar", 100, 34, .zone(damage: 110, type: .magic, range: 850, radius: 380, delay: 0.7, pulses: 3, interval: 0.5, cc: .slow(0.3, 1))),
            ],
            shadow: [
                ("Bola de Chamas", 45, 4.5, .skillshot(damage: 100, type: .magic, range: 800, radius: 36, speed: 1300, cc: .slow(0.25, 1))),
                ("Brasa Negra", 50, 10, .zone(damage: 45, type: .magic, range: 700, radius: 230, delay: 0.3, pulses: 4, interval: 0.5)),
                ("Salto Incandescente", 40, 8, .dash(distance: 360, speed: 1500, damage: 60)),
                ("Inferno Dourado", 100, 32, .zone(damage: 340, type: .magic, range: 900, radius: 420, delay: 1, pulses: 1, interval: 0)),
            ]
        ),
        // General dos exércitos de sombras, guardião da Torre da Convergência.
        Spec(
            id: .korrath, name: "Korrath", title: "General das Sombras", role: .tank, roleLabel: "Tanque · Iniciador", difficulty: .easy,
            playstyle: "Tanque iniciador: avance primeiro com a Carga (E), atordoe com o Golpe (Q) e absorva o dano com a armadura (W).",
            color: 0xD94F6A, radius: 24, maxHealth: 780, maxMana: 220, healthRegen: 10, manaRegen: 6,
            moveSpeed: 262, armor: 40, magicResist: 36, attack: melee(130, 56, 0.95),
            light: [
                ("Golpe de Convergência", 30, 6, .cone(damage: 60, type: .physical, range: 240, angle: deg(100), cc: .stun(0.7))),
                ("Armadura do General", 40, 10, .shield(amount: 400, duration: 4.5)),
                ("Avanço Implacável", 35, 10, .dash(distance: 320, speed: 1300, damage: 50, cc: .stun(1), stopOnHit: true)),
                ("Juramento de Ferro", 80, 36, .nova(damage: 140, type: .physical, radius: 520, allyHeal: 120, cc: .stun(1))),
            ],
            shadow: [
                ("Machadada Sombria", 30, 4, .cone(damage: 90, type: .physical, range: 250, angle: deg(110), cc: .slow(0.4, 1.5))),
                ("Pele de Obsidiana", 40, 12, .buff(duration: 4, attackSpeed: 1.3, moveSpeed: 1.2)),
                ("Carga Sombria", 35, 9, .dash(distance: 360, speed: 1400, damage: 70, cc: .slow(0.5, 1.5))),
                ("Ruína da Convergência", 80, 34, .zone(damage: 85, type: .physical, range: 0, radius: 430, delay: 0, pulses: 4, interval: 0.5, cc: .slow(0.4, 1), follow: true)),
            ]
        ),
    ]
}
