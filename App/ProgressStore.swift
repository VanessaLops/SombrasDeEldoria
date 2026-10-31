import Foundation
import GameEngine
import Observation
import SimCore

/// Conta do jogador gravada no aparelho (XP, cristais, partidas e faces liberadas).
@MainActor
@Observable
final class ProgressStore {
    private(set) var account: Account
    private let defaults: UserDefaults
    private static let key = "sombras.account.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Dado corrompido nunca deve impedir o jogo de abrir.
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Account.self, from: data) {
            account = saved
        } else {
            account = Account()
        }
    }

    /// Grava o resultado de uma partida e devolve o que foi ganho (para a tela final).
    @discardableResult
    func record(_ outcome: MatchOutcome, hero: HeroID) -> Account.Applied {
        let applied = account.apply(outcome.summary)
        if let face = outcome.unlockedFace { account.unlock(face, for: hero) }
        save()
        return applied
    }

    private func save() {
        if let data = try? JSONEncoder().encode(account) { defaults.set(data, forKey: Self.key) }
    }
}
