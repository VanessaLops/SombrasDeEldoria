// swift-tools-version: 6.0
import PackageDescription

// Regra de dependência entre módulos (nunca inverter):
//
//   App (SwiftUI)  ──▶  GameEngine (SpriteKit, só iOS)  ──▶  SimCore (Swift puro)
//
// SimCore não importa nenhum framework de UI/render: toda regra de jogo mora ali,
// é determinística (passo fixo de 30 Hz), é testada em segundos com `swift test`
// e será reaproveitada pelo servidor na Fase 5.
let package = Package(
    name: "SombrasKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SimCore", targets: ["SimCore"]),
        .library(name: "GameEngine", targets: ["GameEngine"]),
    ],
    targets: [
        .target(
            name: "SimCore",
            // A simulação roda centenas de unidades a 30 Hz: otimizada até no Debug, senão o jogo
            // fica lento ao rodar pelo Xcode (o resto do app continua com depuração normal).
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .target(name: "GameEngine", dependencies: ["SimCore"]),
        .testTarget(name: "SimCoreTests", dependencies: ["SimCore"]),
    ]
)
