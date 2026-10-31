import Foundation

/// Grade de navegação + A* de 8 direções com suavização do caminho.
///
/// Uma célula é andável se um disco de `agentRadius` centrado nela não encosta em
/// nenhum obstáculo. Todas as unidades usam o mesmo raio de planejamento (o do herói),
/// o que mantém a grade única e barata.
public struct NavGrid: Sendable {
    public let cellSize: Double
    public let cols: Int
    public let rows: Int
    public let agentRadius: Double
    private let walkable: [Bool]

    public init(map: ArenaMap, cellSize: Double, agentRadius: Double) {
        precondition(cellSize > 0 && agentRadius > 0)
        self.cellSize = cellSize
        self.agentRadius = agentRadius
        cols = Int((map.size.x / cellSize).rounded(.up))
        rows = Int((map.size.y / cellSize).rounded(.up))
        var cells = [Bool](repeating: false, count: cols * rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let center = Vec2((Double(col) + 0.5) * cellSize, (Double(row) + 0.5) * cellSize)
                cells[row * cols + col] = map.isInside(center, margin: agentRadius)
                    && map.clearance(at: center) >= agentRadius
            }
        }
        walkable = cells
    }

    public func cell(for point: Vec2) -> (col: Int, row: Int) {
        (
            Swift.min(Swift.max(Int(point.x / cellSize), 0), cols - 1),
            Swift.min(Swift.max(Int(point.y / cellSize), 0), rows - 1)
        )
    }

    public func center(col: Int, row: Int) -> Vec2 {
        Vec2((Double(col) + 0.5) * cellSize, (Double(row) + 0.5) * cellSize)
    }

    public func isWalkable(col: Int, row: Int) -> Bool {
        col >= 0 && row >= 0 && col < cols && row < rows && walkable[row * cols + col]
    }

    // MARK: Busca de caminho

    /// Caminho de `start` até `goal` (sem incluir `start`), ou `nil` se não houver.
    /// Se `goal` está dentro de um obstáculo, vai até o ponto andável mais próximo.
    public func findPath(from start: Vec2, to goal: Vec2, in map: ArenaMap) -> [Vec2]? {
        if map.isSegmentClear(from: start, to: goal, radius: agentRadius) {
            return [goal]
        }
        guard
            let startCell = nearestWalkable(to: cell(for: start)),
            let goalCell = nearestWalkable(to: cell(for: goal))
        else { return nil }

        let cells = astar(from: startCell, to: goalCell)
        guard let cells else { return nil }

        // Pontos: início real, centros das células, destino real (se alcançável).
        var points = [start] + cells.dropFirst().map { center(col: $0.col, row: $0.row) }
        if map.isSegmentClear(from: points.last ?? start, to: goal, radius: agentRadius) {
            points.append(goal)
        }
        return smooth(points, in: map)
    }

    /// "String pulling": pula para o ponto mais distante que ainda tem passagem livre.
    private func smooth(_ points: [Vec2], in map: ArenaMap) -> [Vec2] {
        guard points.count > 2 else { return Array(points.dropFirst()) }
        var result: [Vec2] = []
        var anchor = 0
        while anchor < points.count - 1 {
            var next = points.count - 1
            while next > anchor + 1,
                  !map.isSegmentClear(from: points[anchor], to: points[next], radius: agentRadius) {
                next -= 1
            }
            result.append(points[next])
            anchor = next
        }
        return result
    }

    private struct Cell: Hashable {
        let col: Int
        let row: Int
    }

    private func nearestWalkable(to origin: (col: Int, row: Int)) -> Cell? {
        if isWalkable(col: origin.col, row: origin.row) { return Cell(col: origin.col, row: origin.row) }
        let maxRing = Swift.max(cols, rows)
        for ring in 1..<maxRing {
            var best: (cell: Cell, distance: Int)?
            for dRow in -ring...ring {
                for dCol in -ring...ring where Swift.max(abs(dRow), abs(dCol)) == ring {
                    let col = origin.col + dCol
                    let row = origin.row + dRow
                    guard isWalkable(col: col, row: row) else { continue }
                    let distance = dRow * dRow + dCol * dCol
                    if best == nil || distance < best!.distance {
                        best = (Cell(col: col, row: row), distance)
                    }
                }
            }
            if let best { return best.cell }
        }
        return nil
    }

    private static let neighbors: [(dCol: Int, dRow: Int, cost: Double)] = [
        (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
        (1, 1, 1.41421356), (1, -1, 1.41421356), (-1, 1, 1.41421356), (-1, -1, 1.41421356),
    ]

    private func astar(from start: Cell, to goal: Cell) -> [Cell]? {
        func heuristic(_ cell: Cell) -> Double {
            let dx = Double(abs(cell.col - goal.col))
            let dy = Double(abs(cell.row - goal.row))
            // Distância octil: consistente com os custos 1 e √2.
            return (dx + dy) + (1.41421356 - 2) * Swift.min(dx, dy)
        }

        var open = MinHeap<Cell>()
        var cost: [Cell: Double] = [start: 0]
        var cameFrom: [Cell: Cell] = [:]
        var closed: Set<Cell> = []
        open.push(start, priority: heuristic(start))

        while let current = open.pop() {
            if current == goal {
                var path = [current]
                var node = current
                while let previous = cameFrom[node] {
                    path.append(previous)
                    node = previous
                }
                return path.reversed()
            }
            guard closed.insert(current).inserted else { continue }
            let currentCost = cost[current] ?? 0

            for step in Self.neighbors {
                let next = Cell(col: current.col + step.dCol, row: current.row + step.dRow)
                guard isWalkable(col: next.col, row: next.row), !closed.contains(next) else { continue }
                // Sem cortar quina: na diagonal, as duas células laterais precisam estar livres.
                if step.dCol != 0, step.dRow != 0,
                   !isWalkable(col: current.col + step.dCol, row: current.row)
                    || !isWalkable(col: current.col, row: current.row + step.dRow) {
                    continue
                }
                let newCost = currentCost + step.cost
                if newCost < (cost[next] ?? .infinity) {
                    cost[next] = newCost
                    cameFrom[next] = current
                    open.push(next, priority: newCost + heuristic(next))
                }
            }
        }
        return nil
    }
}

/// Fila de prioridade mínima (heap binário). Entradas repetidas são toleradas:
/// o A* descarta as obsoletas ao tirá-las.
struct MinHeap<Element> {
    private var storage: [(priority: Double, element: Element)] = []

    var isEmpty: Bool { storage.isEmpty }

    mutating func push(_ element: Element, priority: Double) {
        storage.append((priority, element))
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].priority < storage[parent].priority else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let top = storage.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < storage.count, storage[left].priority < storage[smallest].priority { smallest = left }
            if right < storage.count, storage[right].priority < storage[smallest].priority { smallest = right }
            if smallest == parent { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
        return top.element
    }
}
