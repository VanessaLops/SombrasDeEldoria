import SimCore
import SwiftUI

/// Lobby: perfil, cristais e o botão Jogar. Em menos de 3 toques o jogador está numa partida.
struct LobbyView: View {
    let account: Account
    let onPlay: (GameMode) -> Void

    @State private var picking = false
    @State private var notice: String?

    private struct ModeCard: Identifiable {
        let id: GameMode
        let name: String
        let tag: String
        let description: String
    }

    private let modes = [
        ModeCard(id: .normal, name: "Normal 5v5", tag: "Aetheria",
                 description: "Você e 4 aliados contra 5 inimigos. Domine 2 Relíquias para abrir a Convergência e derrube a Torre da Convergência inimiga."),
        ModeCard(id: .training, name: "Treino", tag: "Arena de Treino",
                 description: "Movimento, habilidades, mira e doação de Fluxo. Abata \(DummyTuning.trainingGoal) alvos: com Alaric, libera a Face da Sombra."),
        ModeCard(id: .ranked, name: "Rankeada", tag: "Contra jogadores",
                 description: "Partidas online valendo ranque."),
    ]

    var body: some View {
        let progress = account.levelProgress
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: 0x1B2A4A))
                        Circle().strokeBorder(Theme.gold, lineWidth: 2)
                        Text("\(account.level)").font(.title2.weight(.heavy)).foregroundStyle(Theme.gold)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invocador · Nível \(account.level)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                        ProgressView(value: Double(progress.into), total: Double(max(progress.needed, 1)))
                            .tint(Theme.gold)
                            .frame(width: 130)
                        Text("\(progress.into) / \(progress.needed) XP").font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
                .padding(8)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelEdge))
                Spacer()
                Label("\(account.crystals) cristais", systemImage: "diamond.fill")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Theme.flux)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.panelEdge))
            }

            Spacer()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sombras de Eldoria")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .foregroundStyle(Theme.gold)
                    Text("O DESPERTAR DAS SOMBRAS").font(.caption).tracking(3).foregroundStyle(Theme.dim)
                    Text("\(account.matches) partidas · \(account.wins) vitórias")
                        .font(.caption).foregroundStyle(Theme.dim).padding(.top, 10)
                    Text("Cada campeão tem duas almas: escolha a Luz ou a Sombra antes da partida.\nDoe Fluxo aos aliados e reúna as Relíquias para a Convergência.")
                        .font(.footnote).foregroundStyle(Theme.text.opacity(0.8)).padding(.top, 4)
                }
                Spacer()
                Button("JOGAR") { picking = true }
                    .buttonStyle(GoldButtonStyle())
                    .font(.largeTitle)
                    .frame(width: 200)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Circle().fill(Color(hex: 0x2A3F7A).opacity(0.25)).frame(width: 420).offset(y: -40)
                Circle().fill(Color(hex: 0x5A7BD8).opacity(0.22)).frame(width: 240).offset(y: 10)
            }
        }
        .overlay {
            if picking { modeSheet }
        }
    }

    private var modeSheet: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 12) {
                Text("Escolha o modo").font(.headline.weight(.heavy)).foregroundStyle(Theme.gold)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(modes) { mode in
                        Button { choose(mode.id) } label: { card(mode) }
                            .buttonStyle(.plain)
                    }
                }
                if let notice {
                    Text(notice).font(.caption).foregroundStyle(Theme.gold)
                }
                Button("Fechar") { close() }.font(.footnote).foregroundStyle(Theme.dim)
            }
            .padding(16)
            .frame(maxWidth: 760)
            .background(Color(hex: 0x0E1A33), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.gold, lineWidth: 2))
            .padding(24)
        }
    }

    private func card(_ mode: ModeCard) -> some View {
        let locked = mode.id == .ranked
        return VStack(alignment: .leading, spacing: 4) {
            Text(mode.tag.uppercased()).font(.caption2).tracking(2).foregroundStyle(Theme.shadow)
            Text(mode.name).font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
            Text(mode.description).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            if locked {
                Text(account.isRankedUnlocked ? "ONLINE EM BREVE" : "NÍVEL \(Account.rankedUnlockLevel) PARA LIBERAR")
                    .font(.caption2.weight(.heavy)).foregroundStyle(Theme.gold).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(hex: 0x14234A), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelEdge, lineWidth: 2))
        .opacity(locked ? 0.6 : 1)
    }

    private func choose(_ mode: GameMode) {
        guard mode != .ranked else {
            notice = account.isRankedUnlocked
                ? "A Rankeada precisa do servidor online (Fase 5) e chega em breve."
                : "A Rankeada abre no nível \(Account.rankedUnlockLevel). Jogue Normal e Treino para subir de nível."
            return
        }
        close()
        onPlay(mode)
    }

    private func close() {
        picking = false
        notice = nil
    }
}
