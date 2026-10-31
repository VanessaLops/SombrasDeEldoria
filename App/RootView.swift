import GameEngine
import SimCore
import SwiftUI

/// Fluxo do jogo: lobby → seleção de campeão → partida → lobby.
struct RootView: View {
    let progress: ProgressStore

    private enum Screen: Equatable {
        case lobby
        case select(GameMode)
        case match(MatchSetup)
    }

    @State private var screen: Screen = .lobby

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()
            switch screen {
            case .lobby:
                LobbyView(account: progress.account) { mode in screen = .select(mode) }
                    .transition(.opacity)
            case .select(let mode):
                ChampionSelectView(mode: mode, account: progress.account) { setup in
                    screen = .match(setup)
                } onBack: {
                    screen = .lobby
                }
                .transition(.opacity)
            case .match(let setup):
                MatchView(setup: setup, progress: progress) { screen = .lobby }
                    .id(setup)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        #if DEBUG
        .onAppear {
            // Atalho de teste: `-autostart normal|training` abre direto numa partida com o Alaric;
            // `-autopilot` deixa o Alaric jogando sozinho (para assistir no Simulador); `-select` abre a seleção.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-select") { screen = .select(.normal) }
            if let index = arguments.firstIndex(of: "-autostart"), arguments.indices.contains(index + 1),
               let mode = GameMode(rawValue: arguments[index + 1]) {
                screen = .match(MatchSetup(mode: mode, hero: .alaric, face: .light, seed: 7, autopilot: arguments.contains("-autopilot")))
            }
        }
        #endif
    }
}
