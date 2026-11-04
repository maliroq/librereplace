import Foundation

/// Conservative UX default, not an assertion that every service built around
/// an open-source client is free. Only curated standalone/no-cost editions
/// are allowed to auto-fill $0 software recurring costs.
public enum ReplacementCostPolicy {
    private static let freeStandaloneIDs: Set<String> = [
        "audacity",
        "bruno",
        "cyberduck",
        "darktable",
        "dbeaver",
        "dusty",
        "espanso",
        "freeplane",
        "fsnotes",
        "gimp",
        "github-desktop",
        "grandperspective",
        "hammerspoon",
        "ice",
        "inkscape",
        "kdenlive",
        "keepassxc",
        "krita",
        "libreoffice",
        "libreoffice-draw",
        "loop",
        "lulu",
        "maccy",
        "obs-studio",
        "onlyoffice",
        "opendisk",
        "openscreen-mit",
        "openscreen-studio",
        "rawtherapee",
        "rectangle",
        "scribus",
        "shotcut",
        "skim",
        "snapzy",
        "stats",
        "super-productivity",
        "thunderbird",
        "utm",
        "vscodium",
        "zed",
        "zettlr",
    ]

    public static func isFreeStandalone(_ alternative: Alternative) -> Bool {
        alternative.licenseKind == .openSource && freeStandaloneIDs.contains(alternative.id)
    }
}
