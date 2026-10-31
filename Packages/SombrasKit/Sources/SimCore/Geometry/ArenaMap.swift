/// Geometria estática de uma arena: limites e obstáculos.
/// O que mora aqui é imutável durante a partida.
public struct ArenaMap: Sendable {
    public let size: Vec2
    public let obstacles: [Obstacle]

    public init(size: Vec2, obstacles: [Obstacle]) {
        self.size = size
        self.obstacles = obstacles
    }

    public func clampToBounds(_ point: Vec2, radius: Double) -> Vec2 {
        Vec2(
            Swift.min(Swift.max(point.x, radius), size.x - radius),
            Swift.min(Swift.max(point.y, radius), size.y - radius)
        )
    }

    public func isInside(_ point: Vec2, margin: Double = 0) -> Bool {
        point.x >= margin && point.y >= margin && point.x <= size.x - margin && point.y <= size.y - margin
    }

    /// Distância (com sinal) até o obstáculo mais próximo. Sem obstáculos: `.infinity`.
    public func clearance(at point: Vec2) -> Double {
        obstacles.reduce(Double.infinity) { Swift.min($0, $1.signedDistance(to: point)) }
    }

    /// Resolve a sobreposição de um disco com os obstáculos e os limites do mapa.
    public func resolve(_ point: Vec2, radius: Double) -> Vec2 {
        var result = point
        // Duas passadas: empurrar para fora de um obstáculo pode encostar em outro.
        for _ in 0..<2 {
            for obstacle in obstacles {
                result = obstacle.pushOut(result, radius: radius)
            }
            result = clampToBounds(result, radius: radius)
        }
        return result
    }

    /// Existe linha de visão entre `a` e `b`?
    ///
    /// Obstáculos que contêm `b` são ignorados: a *face* de uma parede continua visível
    /// (o que se esconde é o que está atrás dela).
    public func hasLineOfSight(from a: Vec2, to b: Vec2) -> Bool {
        for obstacle in obstacles where !obstacle.contains(b) {
            if obstacle.intersects(segmentFrom: a, to: b) { return false }
        }
        return true
    }

    /// Um disco de raio `radius` consegue andar em linha reta de `a` até `b`?
    public func isSegmentClear(from a: Vec2, to b: Vec2, radius: Double) -> Bool {
        guard isInside(a, margin: radius - 0.5), isInside(b, margin: radius - 0.5) else { return false }
        for obstacle in obstacles where obstacle.blocks(segmentFrom: a, to: b, radius: radius) {
            return false
        }
        return true
    }
}
