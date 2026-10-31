import GameEngine
import SimCore
import SwiftUI

/// Seleção de campeão: herói, face (Luz ou Sombra, fixa durante a partida) e kit.
struct ChampionSelectView: View {
    let mode: GameMode
    let account: Account
    let onConfirm: (MatchSetup) -> Void
    let onBack: () -> Void

    @State private var hero: HeroID = .alaric
    @State private var face: Face = .light
    @State private var notice: String?

    var body: some View {
        let definition = HeroDefinition.definition(for: hero)
        // Se a face escolhida não está liberada para o herói novo, volta para a inicial.
        let activeFace = account.isFaceUnlocked(face, for: hero) ? face : startingFace

        VStack(spacing: 8) {
            HStack {
                Button("‹ Voltar", action: onBack).foregroundStyle(Theme.dim)
                Spacer()
                Text("Escolha seu campeão").font(.headline.weight(.heavy)).foregroundStyle(Theme.gold)
                Spacer()
                Text(mode == .training ? "Treino" : "Normal 5v5").font(.caption).foregroundStyle(Theme.dim).frame(minWidth: 70, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Roster.order, id: \.self) { id in
                            Button {
                                hero = id
                                notice = nil
                            } label: {
                                VStack(spacing: 3) {
                                    HeroBadge(hero: id, face: id == hero ? activeFace : nil, size: 44)
                                    Text(HeroDefinition.definition(for: id).name).font(.caption2.weight(.bold)).foregroundStyle(Theme.text)
                                    Capsule().fill(Theme.difficulty(HeroDefinition.definition(for: id).difficulty)).frame(height: 3)
                                }
                                .padding(4)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(id == hero ? Theme.gold : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 216)
                .scrollIndicators(.hidden)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            HeroBadge(hero: hero, face: activeFace, size: 76)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(definition.name).font(.title.weight(.heavy)).foregroundStyle(Theme.text)
                                Text(definition.title).font(.caption).foregroundStyle(Theme.dim)
                                Text(definition.roleLabel).font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
                                Text("Mecânica: \(definition.difficulty.label)").font(.caption.weight(.heavy))
                                    .foregroundStyle(Theme.difficulty(definition.difficulty))
                            }
                            Spacer()
                            HStack(spacing: 14) {
                                stat("Vida", definition.maxHealth)
                                stat("Mana", definition.maxMana)
                                stat("Alcance", definition.attack.range)
                                stat("Veloc.", definition.moveSpeed)
                            }
                        }
                        Text(definition.playstyle).font(.footnote).foregroundStyle(Theme.text)

                        HStack(spacing: 8) {
                            ForEach(Face.allCases, id: \.self) { candidate in
                                faceChip(candidate, definition: definition, active: activeFace == candidate)
                            }
                        }
                        if let notice {
                            Text(notice).font(.caption).foregroundStyle(Theme.gold)
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 8) {
                            ForEach(definition.abilities(activeFace), id: \.key) { ability in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(ability.key.rawValue)
                                        .font(.caption.weight(.heavy))
                                        .frame(width: 26, height: 26)
                                        .background(Color(hex: 0x1B2A4A), in: Circle())
                                        .overlay(Circle().strokeBorder(Color(hex: 0xBDEEFF), lineWidth: 2))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ability.name).font(.caption.weight(.bold)).foregroundStyle(Theme.text)
                                        Text("\(ability.summary) \(Int(ability.manaCost)) mana, \(ability.cooldown.formatted())s.")
                                            .font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelEdge))
            }

            Button("CONFIRMAR · \(definition.name)") {
                onConfirm(MatchSetup(mode: mode, hero: hero, face: activeFace))
            }
            .buttonStyle(GoldButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(value))").font(.headline.weight(.heavy)).foregroundStyle(Theme.text)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func faceChip(_ candidate: Face, definition: HeroDefinition, active: Bool) -> some View {
        let open = account.isFaceUnlocked(candidate, for: hero)
        return Button {
            if open {
                face = candidate
                notice = nil
            } else {
                notice = definition.otherFaceUnlockedByTraining
                    ? "Conclua o Treino com \(definition.name) para liberar a Face da \(candidate.displayName)."
                    : "A Face da \(candidate.displayName) de \(definition.name) será liberada em outro modo (em breve)."
            }
        } label: {
            HStack(spacing: 8) {
                HeroBadge(hero: hero, face: candidate, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Face da \(candidate.displayName)\(open ? "" : "  🔒")").font(.footnote.weight(.heavy)).foregroundStyle(Theme.text)
                    Text(definition.face(candidate).style).font(.caption2).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(hex: 0x14234A), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Theme.gold : Theme.panelEdge, lineWidth: 2))
            .opacity(open ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }
}
