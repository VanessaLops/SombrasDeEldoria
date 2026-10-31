import Foundation

public struct Circle2: Sendable, Equatable {
    public var center: Vec2
    public var radius: Double

    public init(center: Vec2, radius: Double) {
        self.center = center
        self.radius = radius
    }
}

public struct Rect2: Sendable, Equatable {
    public var min: Vec2
    public var max: Vec2

    public init(min: Vec2, max: Vec2) {
        self.min = min
        self.max = max
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(min: Vec2(x, y), max: Vec2(x + width, y + height))
    }

    public var center: Vec2 { (min + max) / 2 }
    public var halfSize: Vec2 { (max - min) / 2 }
}

/// Obstáculo estático do mapa. Bloqueia movimento **e** visão.
public enum Obstacle: Sendable, Equatable {
    case circle(Circle2)
    case rect(Rect2)

    /// Distância com sinal até a borda: negativa dentro, positiva fora.
    public func signedDistance(to point: Vec2) -> Double {
        switch self {
        case .circle(let circle):
            return point.distance(to: circle.center) - circle.radius
        case .rect(let rect):
            let q = Vec2(abs(point.x - rect.center.x), abs(point.y - rect.center.y)) - rect.halfSize
            let outside = Vec2(Swift.max(q.x, 0), Swift.max(q.y, 0)).length
            let inside = Swift.min(Swift.max(q.x, q.y), 0)
            return outside + inside
        }
    }

    public func contains(_ point: Vec2) -> Bool {
        signedDistance(to: point) < 0
    }

    /// Empurra um disco de raio `radius` para fora do obstáculo, pelo menor caminho.
    public func pushOut(_ point: Vec2, radius: Double) -> Vec2 {
        switch self {
        case .circle(let circle):
            let reach = circle.radius + radius
            let offset = point - circle.center
            guard offset.lengthSquared < reach * reach else { return point }
            let direction = offset.lengthSquared > 1e-12 ? offset.normalized : Vec2(1, 0)
            return circle.center + direction * reach
        case .rect(let rect):
            let nearest = Vec2(
                Swift.min(Swift.max(point.x, rect.min.x), rect.max.x),
                Swift.min(Swift.max(point.y, rect.min.y), rect.max.y)
            )
            let offset = point - nearest
            if offset.lengthSquared > 1e-12 {
                // Fora do retângulo: empurra na direção do ponto mais próximo.
                guard offset.length < radius else { return point }
                return nearest + offset.normalized * radius
            }
            // Dentro do retângulo: sai pela face mais próxima.
            let candidates: [Vec2] = [
                Vec2(rect.min.x - radius, point.y),
                Vec2(rect.max.x + radius, point.y),
                Vec2(point.x, rect.min.y - radius),
                Vec2(point.x, rect.max.y + radius),
            ]
            return candidates.min { $0.distance(to: point) < $1.distance(to: point) } ?? point
        }
    }

    /// O segmento `a→b` atravessa o obstáculo? (linha de visão)
    public func intersects(segmentFrom a: Vec2, to b: Vec2) -> Bool {
        switch self {
        case .circle(let circle):
            return Geometry.distance(from: circle.center, toSegment: a, b) < circle.radius
        case .rect(let rect):
            return Geometry.segment(a, b, intersects: rect)
        }
    }

    /// Um disco de raio `radius` percorrendo `a→b` encosta no obstáculo?
    public func blocks(segmentFrom a: Vec2, to b: Vec2, radius: Double) -> Bool {
        switch self {
        case .circle(let circle):
            return Geometry.distance(from: circle.center, toSegment: a, b) < circle.radius + radius
        case .rect(let rect):
            // Retângulo inflado: levemente conservador nos cantos, o que é seguro.
            let grown = Rect2(
                min: rect.min - Vec2(radius, radius),
                max: rect.max + Vec2(radius, radius)
            )
            return Geometry.segment(a, b, intersects: grown)
        }
    }
}

public enum Geometry {
    public static func distance(from point: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let lengthSquared = ab.lengthSquared
        guard lengthSquared > 1e-12 else { return point.distance(to: a) }
        let t = Swift.min(Swift.max((point - a).dot(ab) / lengthSquared, 0), 1)
        return point.distance(to: a + ab * t)
    }

    /// Teste de "slabs": o segmento cruza o retângulo?
    public static func segment(_ a: Vec2, _ b: Vec2, intersects rect: Rect2) -> Bool {
        var tMin = 0.0
        var tMax = 1.0
        let delta = b - a
        for axis in 0..<2 {
            let origin = a[axis]
            let direction = delta[axis]
            let low = rect.min[axis]
            let high = rect.max[axis]
            if abs(direction) < 1e-12 {
                if origin < low || origin > high { return false }
            } else {
                var t1 = (low - origin) / direction
                var t2 = (high - origin) / direction
                if t1 > t2 { swap(&t1, &t2) }
                tMin = Swift.max(tMin, t1)
                tMax = Swift.min(tMax, t2)
                if tMin > tMax { return false }
            }
        }
        return true
    }
}
