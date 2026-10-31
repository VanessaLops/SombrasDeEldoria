import Foundation

/// Vetor 2D usado por toda a lógica de jogo.
///
/// `SIMD2<Double>` já traz aritmética vetorial otimizada (`+`, `-`, `*` por escalar);
/// aqui adicionamos apenas as operações geométricas de que a lógica precisa.
public typealias Vec2 = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    public init(angle: Double, length: Double = 1) {
        self.init(cos(angle) * length, sin(angle) * length)
    }

    public var lengthSquared: Double { x * x + y * y }

    public var length: Double { lengthSquared.squareRoot() }

    /// Versor do vetor. O vetor nulo continua nulo, evitando NaN.
    public var normalized: Vec2 {
        let len = length
        return len > 1e-9 ? self / len : .zero
    }

    /// Ângulo em radianos, em (-π, π], medido a partir do eixo +x.
    public var angle: Double { atan2(y, x) }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    public func distance(to other: Vec2) -> Double { (other - self).length }

    /// Ângulo sem sinal entre os dois vetores, em [0, π].
    public func angle(to other: Vec2) -> Double {
        let denominator = length * other.length
        guard denominator > 1e-9 else { return 0 }
        return acos(Swift.min(1, Swift.max(-1, dot(other) / denominator)))
    }

    /// Vetor girado `angle` radianos no sentido anti-horário.
    public func rotated(by angle: Double) -> Vec2 {
        let c = cos(angle)
        let s = sin(angle)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public func clampedLength(to maximum: Double) -> Vec2 {
        let len = length
        return len > maximum ? self * (maximum / len) : self
    }
}

public enum Angle {
    public static func degrees(_ value: Double) -> Double { value * .pi / 180 }

    /// Menor diferença com sinal para ir de `from` até `to`, em (-π, π].
    public static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta <= -.pi {
            delta += 2 * .pi
        }
        return delta
    }

    /// Gira `current` em direção a `target` em no máximo `maxStep` radianos.
    public static func rotate(_ current: Double, toward target: Double, maxStep: Double) -> Double {
        let delta = shortestDelta(from: current, to: target)
        guard abs(delta) > maxStep else { return current + delta }
        return current + (delta < 0 ? -maxStep : maxStep)
    }
}
