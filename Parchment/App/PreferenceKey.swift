/// Keys for values stored in `UserDefaults` and read with `@AppStorage`.
enum PreferenceKey {
    static let fontSize = "fontSize"
    /// Body line height as a multiple of the text size.
    static let lineHeight = "lineHeight"
    static let focusMode = "focusMode"
    static let typewriterMode = "typewriterMode"
    /// New letters appear as wet ink that settles. On by default.
    static let inkEffect = "inkEffect"
    /// Wax seals, filigree rules and other decorations. On by default.
    static let ornaments = "ornaments"
    /// Whether the outline shows as a side panel when the window is wide enough. On by default.
    static let showsOutlineSidebar = "showsOutlineSidebar"
    /// Scroll to each change Claude makes in a followed plan.
    static let followClaude = "followClaude"
}
