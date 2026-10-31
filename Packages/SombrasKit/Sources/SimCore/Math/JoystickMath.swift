/// Matemática do joystick virtual, separada da UI para ser testável.
public enum JoystickMath {
    /// Converte o deslocamento do dedo em um eixo de magnitude [0, 1].
    ///
    /// A zona morta é *remapeada* (e não apenas cortada): toques leves não fazem
    /// o personagem tremer, e a velocidade máxima continua sendo alcançável.
    public static func axis(for offset: Vec2, radius: Double, deadZone: Double) -> Vec2 {
        precondition(radius > 0, "Raio do joystick precisa ser positivo")
        precondition((0..<1).contains(deadZone), "Zona morta precisa estar em [0, 1)")
        let magnitude = min(offset.length / radius, 1)
        guard magnitude > deadZone else { return .zero }
        let scaled = (magnitude - deadZone) / (1 - deadZone)
        return offset.normalized * scaled
    }
}
