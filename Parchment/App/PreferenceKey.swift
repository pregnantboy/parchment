/// Keys for values stored in `UserDefaults` and read with `@AppStorage`.
enum PreferenceKey {
    static let fontSize = "fontSize"
    static let focusMode = "focusMode"
    static let typewriterMode = "typewriterMode"
    /// New letters appear as wet ink that settles. On by default.
    static let inkEffect = "inkEffect"
    /// Wax seals, filigree rules, a raised initial and other decorations. On by default.
    static let ornaments = "ornaments"
    /// Whether the outline shows as a side panel when the window is wide enough. On by default.
    static let showsOutlineSidebar = "showsOutlineSidebar"
}
