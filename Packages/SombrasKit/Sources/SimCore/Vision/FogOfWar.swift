/// Névoa de guerra de um time: o que ele vê agora e o que já explorou.
///
/// A visão é circular, limitada pelos obstáculos (paredes e árvores bloqueiam).
/// Roda a 10 Hz, não a cada tick: o custo é raio² × obstáculos.
public final class FogOfWar {
    public enum CellState: UInt8, Sendable {
        case hidden, explored, visible
    }

    public let cellSize: Double
    public let cols: Int
    public let rows: Int
    /// Aumenta a cada recálculo; o renderizador só refaz a textura quando muda.
    public private(set) var version = 0
    private var states: [CellState]

    public init(map: ArenaMap, cellSize: Double) {
        self.cellSize = cellSize
        cols = Int((map.size.x / cellSize).rounded(.up))
        rows = Int((map.size.y / cellSize).rounded(.up))
        states = [CellState](repeating: .hidden, count: cols * rows)
    }

    public func state(col: Int, row: Int) -> CellState {
        guard col >= 0, row >= 0, col < cols, row < rows else { return .hidden }
        return states[row * cols + col]
    }

    public func isVisible(_ point: Vec2) -> Bool {
        state(col: Int(point.x / cellSize), row: Int(point.y / cellSize)) == .visible
    }

    public struct Eye: Sendable {
        public var position: Vec2
        public var radius: Double

        public init(position: Vec2, radius: Double) {
            self.position = position
            self.radius = radius
        }
    }

    public func update(eyes: [Eye], map: ArenaMap) {
        // O que era visível vira "explorado"; depois reabrimos o que ainda se vê.
        for index in states.indices where states[index] == .visible {
            states[index] = .explored
        }

        for eye in eyes {
            // Só obstáculos dentro do alcance podem bloquear uma linha que sai do olho.
            let near = map.obstacles.filter { $0.signedDistance(to: eye.position) < eye.radius }
            let reach = Int((eye.radius / cellSize).rounded(.up)) + 1
            let center = (col: Int(eye.position.x / cellSize), row: Int(eye.position.y / cellSize))
            let radiusSquared = eye.radius * eye.radius
            let rowRange = Swift.max(center.row - reach, 0)...Swift.max(Swift.min(center.row + reach, rows - 1), 0)
            let colRange = Swift.max(center.col - reach, 0)...Swift.max(Swift.min(center.col + reach, cols - 1), 0)
            for row in rowRange {
                for col in colRange {
                    let cellCenter = Vec2((Double(col) + 0.5) * cellSize, (Double(row) + 0.5) * cellSize)
                    guard (cellCenter - eye.position).lengthSquared <= radiusSquared else { continue }
                    if !near.isEmpty, !Self.hasLineOfSight(from: eye.position, to: cellCenter, near: near) { continue }
                    states[row * cols + col] = .visible
                }
            }
        }
        version += 1
    }

    /// Mesma regra de `ArenaMap.hasLineOfSight`, restrita aos obstáculos próximos.
    private static func hasLineOfSight(from a: Vec2, to b: Vec2, near: [Obstacle]) -> Bool {
        for obstacle in near where !obstacle.contains(b) {
            if obstacle.intersects(segmentFrom: a, to: b) { return false }
        }
        return true
    }
}
