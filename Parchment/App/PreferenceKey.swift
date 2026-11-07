/// Keys for values stored in `UserDefaults` and read with `@AppStorage`.
enum PreferenceKey {
    static let fontSize = "fontSize"
    static let focusMode = "focusMode"
    static let typewriterMode = "typewriterMode"
    /// Scroll to each change Claude makes in a followed plan.
    static let followClaude = "followClaude"
}
