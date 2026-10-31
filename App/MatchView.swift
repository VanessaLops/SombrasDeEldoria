import GameEngine
import SimCore
import SpriteKit
import SwiftUI

/// Hospeda o `SKView` diretamente: o `SpriteView` do SwiftUI não liga multitoque,
/// e o jogo precisa de joystick e habilidades ao mesmo tempo.
struct GameView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }
}

/// Partida: a cena do SpriteKit com o HUD do SwiftUI por cima.
struct MatchView: View {
    let progress: ProgressStore
    let onExit: () -> Void

    @State private var session: MatchSession
    @State private var showKit = true
    @State private var rewards: Account.Applied?
    @State private var unlockedFace: Face?
    @Environment(\.scenePhase) private var scenePhase

    init(setup: MatchSetup, progress: ProgressStore, onExit: @escaping () -> Void) {
        self.progress = progress
        self.onExit = onExit
        _session = State(initialValue: MatchSession(setup: setup))
    }

    var body: some View {
        let hud = session.hud
        ZStack {
            GameView(scene: session.scene).ignoresSafeArea()

            VStack(spacing: 4) {
                scoreBar(hud)
                feed
                Spacer()
            }
            .padding(.top, 6)
            .allowsHitTesting(false)

            VStack {
                Spacer()
                heroPanel(hud)
            }
            .padding(.bottom, 8)
            .allowsHitTesting(false)

            topButtons

            if showKit { kitPanel }

            if !hud.isAlive, session.winner == nil {
                Text("Reaparecendo em \(Int(hud.respawnIn.rounded(.up)))s")
                    .font(.title2.weight(.heavy))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }

            if session.isPaused, session.winner == nil { pauseMenu }
            if let winner = session.winner { endScreen(winner, hud: hud) }
        }
        .foregroundStyle(Theme.text)
        .onChange(of: session.outcome) { _, outcome in
            guard let outcome, rewards == nil else { return }
            rewards = progress.record(outcome, hero: session.setup.hero)
            unlockedFace = outcome.unlockedFace
        }
        .onChange(of: scenePhase) { _, phase in session.setAppActive(phase == .active) }
        .task {
            try? await Task.sleep(for: .seconds(14))
            showKit = false
        }
    }

    // MARK: Topo

    private func scoreBar(_ hud: MatchHUD) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                if session.setup.mode != .training {
                    Text("\(hud.lightKills)").foregroundStyle(Theme.light)
                    Text("×").foregroundStyle(Theme.dim)
                    Text("\(hud.shadowKills)").foregroundStyle(Theme.shadow)
                    Text("·").foregroundStyle(Theme.dim)
                }
                Text(Self.clock(hud.time))
                Text("·").foregroundStyle(Theme.dim)
                Text("\(hud.kills)/\(hud.deaths)  ⚔︎ \(hud.creeps)  ◆ \(hud.gold)")
            }
            .font(.subheadline.weight(.heavy).monospacedDigit())
            if session.setup.mode == .training {
                Text(trainingLine(hud)).font(.caption2.weight(.bold)).foregroundStyle(Theme.gold)
            } else {
                relicLine(hud)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func relicLine(_ hud: MatchHUD) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(session.relicNames.enumerated()), id: \.offset) { index, name in
                let owner = hud.relicOwners.indices.contains(index) ? hud.relicOwners[index] : nil
                HStack(spacing: 3) {
                    Image(systemName: "seal.fill").foregroundStyle(Theme.team(owner))
                    Text(name.split(separator: " ").last.map(String.init) ?? name)
                }
            }
            Text(hud.hasConvergence ? "CONVERGÊNCIA" : "Nexus selado")
                .foregroundStyle(hud.hasConvergence ? Theme.gold : Theme.dim)
            if hud.enemyHasConvergence {
                Text("· Inimigos com Convergência!").foregroundStyle(Theme.enemy)
            }
        }
        .font(.caption2.weight(.bold))
    }

    private func trainingLine(_ hud: MatchHUD) -> String {
        if let unlockedFace {
            return "Face da \(unlockedFace.displayName) desbloqueada para \(session.definition.name)!"
        }
        if let rewards {
            return "Treino concluído! +\(rewards.rewards.xp) XP · +\(rewards.rewards.crystals) cristais"
        }
        let extra = session.definition.otherFaceUnlockedByTraining ? " para liberar a outra face" : ""
        return "Treino: abates \(min(hud.trainingKills, DummyTuning.trainingGoal))/\(DummyTuning.trainingGoal)\(extra) · toque no aliado para doar Fluxo"
    }

    private var feed: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(session.feed) { line in
                Text(line.text)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color(line.tone))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
    }

    private func color(_ tone: FeedLine.Tone) -> Color {
        switch tone {
        case .ally: Theme.ally
        case .enemy: Theme.enemy
        case .neutral: Theme.text
        case .gold: Theme.gold
        }
    }

    private var topButtons: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()
                circleButton("questionmark", label: "Ver habilidades") { showKit.toggle() }
                circleButton("pause.fill", label: "Pausar") { session.pause() }
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Herói

    private func heroPanel(_ hud: MatchHUD) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                HeroBadge(hero: session.setup.hero, face: session.setup.face, size: 34)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(hud.level)").font(.caption2.weight(.heavy))
                            .padding(3).background(Theme.gold, in: Circle()).foregroundStyle(.black)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.definition.name).font(.footnote.weight(.heavy))
                    Text("Face da \(session.setup.face.displayName)\(session.post.map { " · \($0.label)" } ?? "")")
                        .font(.caption2).foregroundStyle(Theme.dim)
                }
            }
            bar(hud.health / hud.maxHealth, Theme.hp, "\(Int(min(hud.health, hud.maxHealth).rounded())) / \(Int(hud.maxHealth.rounded()))")
            bar(hud.mana / hud.maxMana, Theme.mana, "\(Int(hud.mana)) / \(Int(hud.maxMana.rounded()))")
            bar(hud.flux / FluxTuning.max, Theme.flux,
                "Fluxo \(Int(hud.flux)) · doações \(hud.donationsLeft)/\(FluxTuning.maxDonations)" + (hud.hasteRemaining > 0 ? " · Surto \(Int(hud.hasteRemaining.rounded(.up)))s" : ""))
            bar(hud.xpFraction, Theme.gold, "Nível \(hud.level)", height: 6)
        }
    }

    private func bar(_ value: Double, _ color: Color, _ label: String, height: CGFloat = 14) -> some View {
        ZStack {
            GeometryReader { proxy in
                Rectangle().fill(.black.opacity(0.55))
                Rectangle().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
            if height > 8 { Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: 200, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Painéis

    private var kitPanel: some View {
        let definition = session.definition
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                HeroBadge(hero: definition.id, face: session.setup.face, size: 40)
                VStack(alignment: .leading) {
                    Text("\(definition.name) · \(definition.roleLabel)").font(.footnote.weight(.heavy))
                    Text("Mecânica \(definition.difficulty.label) · Face da \(session.setup.face.displayName)")
                        .font(.caption2.weight(.heavy)).foregroundStyle(Theme.difficulty(definition.difficulty))
                }
            }
            Text(definition.playstyle).font(.caption)
            ForEach(session.abilities, id: \.key) { ability in
                Text("\(Text(ability.key.rawValue).foregroundStyle(Theme.gold).bold()) \(Text(ability.name).bold()) · \(Text(ability.summary).foregroundStyle(Theme.dim))")
                    .font(.caption2)
            }
            if session.setup.mode != .training {
                Text("Objetivo: domine 2 Relíquias (ou espere 12 min) para abrir a Torre da Convergência inimiga. Portais do Véu ligam as relíquias do rio. Botão Base volta para a fonte.")
                    .font(.caption2).foregroundStyle(Theme.flux)
            }
            Text("Toque para fechar · botão ? reabre").font(.caption2).foregroundStyle(Theme.dim)
        }
        .padding(10)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Theme.navy.opacity(0.93), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.gold, lineWidth: 2))
        .onTapGesture { showKit = false }
    }

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("PAUSA").font(.largeTitle.weight(.black)).foregroundStyle(Theme.gold)
                Button("Continuar") { session.resume() }.buttonStyle(GoldButtonStyle()).frame(width: 240)
                Button("Sair da partida") { leave() }
                    .font(.headline).foregroundStyle(Theme.enemy)
                Text(session.setup.mode == .training || session.hud.time >= Account.minimumPlayForReward
                     ? "Sair no meio rende metade da recompensa."
                     : "Saindo antes de \(Int(Account.minimumPlayForReward))s você não ganha recompensa.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }

    private func endScreen(_ winner: Team, hud: MatchHUD) -> some View {
        let won = winner == .light
        return ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(won ? "VITÓRIA" : "DERROTA")
                    .font(.system(size: 48, weight: .black)).tracking(4)
                    .foregroundStyle(won ? Theme.gold : Theme.enemy)
                Text(won ? "A Torre da Convergência inimiga caiu." : "Sua Torre da Convergência foi destruída.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                HStack(spacing: 22) {
                    endStat("Placar", "\(hud.lightKills) × \(hud.shadowKills)")
                    endStat("Abates/Mortes", "\(hud.kills)/\(hud.deaths)")
                    endStat("Esbirros", "\(hud.creeps)")
                    endStat("Ouro", "\(hud.gold)")
                    endStat("Nível", "\(hud.level)")
                    endStat("Duração", Self.clock(hud.time))
                }
                if let rewards {
                    Text("+\(rewards.rewards.xp) XP · +\(rewards.rewards.crystals) cristais"
                         + (rewards.levelsGained > 0 ? "  ·  NÍVEL SUBIU! (+\(rewards.levelBonus) cristais)" : ""))
                        .font(.subheadline.weight(.heavy)).foregroundStyle(Theme.flux)
                }
                Button("Voltar ao lobby", action: onExit).buttonStyle(GoldButtonStyle()).frame(width: 260)
            }
        }
    }

    private func endStat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func leave() {
        if let outcome = session.leaveEarly(), rewards == nil {
            rewards = progress.record(outcome, hero: session.setup.hero)
        }
        onExit()
    }

    private static func clock(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
