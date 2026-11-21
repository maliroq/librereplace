import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import LibreReplaceCore

/// Editorial summaries are authored in Catalog/app_presentation.json rather than
/// generated from coverage scores. They do not claim feature parity.
private struct AppPresentationFile: Decodable, Sendable {
    let schemaVersion: Int
    let paidDescriptions: [String: String]
    let alternativeDescriptions: [String: String]
}

enum AppPresentation {
    private static let catalog: AppPresentationFile? = {
        guard let url = Bundle.main.url(forResource: "app_presentation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppPresentationFile.self, from: data),
              decoded.schemaVersion == 1 else { return nil }
        return decoded
    }()

    static func summary(for app: PaidApplication) -> String {
        catalog?.paidDescriptions[app.id] ??
        app.capabilities.prefix(3).map(\.label).joined(separator: " · ")
    }

    static func summary(for alternative: Alternative) -> String {
        catalog?.alternativeDescriptions[alternative.id] ??
        "Free software for selected replacement tasks."
    }

    static func summary(for component: StudioComponent, replacing app: PaidApplication) -> String {
        if let alternative = app.alternatives.first(where: { $0.id == component.id }) {
            return summary(for: alternative)
        }
        switch component.kind {
        case .builtInBridge: return "Built into LibreReplace for local file processing."
        case .macOSNative: return "Use an existing capability of macOS."
        case .externalEngine: return "Local processing engine for supported workflows."
        case .openSourceApp: return "Free component for this replacement setup."
        }
    }
}

// App identity matters more than visual coverage. The fallback is not an invented logo.
// Use an icon only when it
// belongs to this exact product, and never substitute a corporate favicon.
// Optional product-specific artwork is identified by an explicit catalog entry.
private struct BrandArtworkFile: Decodable {
    let schemaVersion: Int
    let apps: [String: BrandArtworkRecord]
}

private struct BrandArtworkRecord: Decodable {
    let iconFile: String?
    let sourcePage: String?
    let artworkStatus: String?
}

private enum BrandArtwork {
    private static let manifest: BrandArtworkFile? = {
        guard let url = Bundle.main.url(forResource: "app_artwork", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BrandArtworkFile.self, from: data),
              decoded.schemaVersion == 2 else { return nil }
        return decoded
    }()

    static func url(for name: String) -> URL? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let entry = manifest?.apps[key],
              entry.artworkStatus == "product-specific",
              let file = entry.iconFile,
              file.range(of: #"^[a-z0-9][a-z0-9-]*\.png$"#, options: .regularExpression) != nil
        else { return nil }
        // Only product-specific files curated in the manifest. Unlike domain
        // favicons, these cannot accidentally become the same company logo
        // for multiple applications. The source can still change upstream.
        return URL(string: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@main/png/\(file)")
    }
}

// Explicitly approved original product PNGs can be stored locally without
// bundling third-party trademarks into LibreReplace's public distribution.
// The approval tool pins each exact filename and SHA-256 to its product name.
private struct ApprovedArtworkItem: Decodable {
    let filename: String
    let sha256: String
}
private struct ApprovedArtworkManifest: Decodable {
    let schemaVersion: Int
    let apps: [String: ApprovedArtworkItem]
}
private enum ApprovedArtwork {
    private static let folder: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibreReplace", isDirectory: true)
            .appendingPathComponent("Approved Artwork", isDirectory: true)
    }()
    private static let manifest: ApprovedArtworkManifest? = {
        let url = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url), data.count <= 32 * 1024,
              let manifest = try? JSONDecoder().decode(ApprovedArtworkManifest.self, from: data),
              manifest.schemaVersion == 1 else { return nil }
        return manifest
    }()
    static func image(for name: String) -> NSImage? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let entry = manifest?.apps[key],
              entry.filename.range(of: #"^[a-z0-9][a-z0-9-]*\.png$"#, options: .regularExpression) != nil,
              entry.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
        let url = folder.appendingPathComponent(entry.filename)
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: url), data.count < 12 * 1024 * 1024 else { return nil }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == entry.sha256 else { return nil }
        return NSImage(data: data)
    }
}

// Five different local application records in the user-supplied November 15
// export carried exactly the same macOS generic app icon. Do not mistake that
// system fallback for Photoshop, Acrobat, Bear, CleanMyMac, or Tower artwork.
private enum InstalledArtworkQuality {
    // Perceptual horizontal-difference hash of that generic icon's PNG.
    // Used alongside the system-default icon (which varies by macOS version).
    private static let macOSGenericSignatures: [UInt64] = [
        0x0f332b45552933cc, 0xcc332955452b330f,
        0x0f332b45550b330e // Exact duplicate across five 2026-11-15 Mac exports
    ]

    static func isDistinctAppIcon(_ icon: NSImage) -> Bool {
        guard let signature = signature(for: icon) else { return false }
        if macOSGenericSignatures.contains(where: { (signature ^ $0).nonzeroBitCount <= 7 }) {
            return false
        }
        if let systemSignature = Self.signature(for: NSWorkspace.shared.icon(for: UTType.applicationBundle)),
           (signature ^ systemSignature).nonzeroBitCount <= 3 { return false }
        return true
    }

    private static func signature(for image: NSImage) -> UInt64? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 9, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 9, height: 8).fill()
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 9, height: 8),
                   from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        func luminance(_ x: Int, _ y: Int) -> CGFloat {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 1 }
            return color.redComponent * 0.299 + color.greenComponent * 0.587 + color.blueComponent * 0.114
        }
        var value: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 where luminance(x, y) > luminance(x + 1, y) {
                value |= UInt64(1) << UInt64(y * 8 + x)
            }
        }
        return value
    }
}

struct AppArtwork: View {
    @EnvironmentObject private var state: AppState
    let name: String
    var bundleIDs: [String] = []
    var size: CGFloat = 48

    // Bundle IDs take precedence over names, and name matches must be exact.
    // Substring/prefix matching can assign an unrelated application's artwork.
    private var installedURL: URL? {
        for id in bundleIDs where !id.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
               url.pathExtension.lowercased() == "app",
               Bundle(url: url)?.bundleIdentifier == id { return url }
        }
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: String] = [
            "onlyoffice desktop editors": "ONLYOFFICE",
            "dbeaver community": "DBeaver",
            "beekeeper studio community edition": "Beekeeper Studio",
            "affine community edition": "AFFiNE",
            "cap (studio mode)": "Cap"
        ]
        let expected = (aliases[key] ?? name).lowercased()
        for installed in state.installed {
            if let id = installed.bundleIdentifier, bundleIDs.contains(id),
               installed.path.pathExtension.lowercased() == "app" {
                return installed.path
            }
            if installed.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expected,
               installed.path.pathExtension.lowercased() == "app" {
                return installed.path
            }
        }
        return nil
    }

    // Never promote a macOS *generic* icon to product artwork. A matched app
    // bundle can be a placeholder/stub with no actual icon resource. Prefer an
    // icon from the bundle's own Info.plist asset instead of an NSWorkspace
    // fallback that can look like a prohibited-sign app icon.
    private var realInstalledIcon: NSImage? {
        guard let url = installedURL,
              let bundle = Bundle(url: url),
              let info = bundle.infoDictionary else { return nil }
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        if let iconFile = info["CFBundleIconFile"] as? String, !iconFile.isEmpty {
            let base = (iconFile as NSString).deletingPathExtension
            for filename in [iconFile, base + ".icns", base + ".png"] {
                let file = resources.appendingPathComponent(filename)
                if let icon = NSImage(contentsOf: file),
                   InstalledArtworkQuality.isDistinctAppIcon(icon) { return icon }
            }
        }
        // Some native apps put their icon in Assets.car. Request the OS-rendered
        // image only when the bundle actually provides an asset catalog.
        let assetCatalog = resources.appendingPathComponent("Assets.car")
        if FileManager.default.fileExists(atPath: assetCatalog.path),
           info["CFBundleIconName"] is String {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return InstalledArtworkQuality.isDistinctAppIcon(icon) ? icon : nil
        }
        return nil
    }

    // Native LibreReplace bridges are *our own tools*, not third-party apps.
    // A distinct readable symbol is more accurate than the generic gray tile
    // and does not invent or misattribute any third-party product artwork.
    private var builtInToolSymbol: String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.hasPrefix("librereplace ") else { return nil }
        if key.contains("pdf") { return "doc.text" }
        if key.contains("image") || key.contains("photo") { return "photo" }
        if key.contains("audio") || key.contains("transcription") { return "waveform" }
        return "wrench.and.screwdriver"
    }

    private var builtInToolArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.05, green: 0.42, blue: 0.77),
                             Color(red: 0.07, green: 0.74, blue: 0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: builtInToolSymbol ?? "wrench.and.screwdriver")
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .padding(size * 0.24)
        }
    }

    var body: some View {
        Group {
            // User-reviewed, hash-pinned artwork outranks the macOS icon cache.
            // NSWorkspace can provide a generic icon even for a matching bundle;
            // it must never override a product image the user explicitly approved.
            if let approvedIcon = ApprovedArtwork.image(for: name) {
                Image(nsImage: approvedIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if builtInToolSymbol != nil {
                builtInToolArtwork
            } else if let realInstalledIcon {
                Image(nsImage: realInstalledIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let iconURL = BrandArtwork.url(for: name) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().interpolation(.high).scaledToFit()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(name) application icon")
    }

    private var placeholder: some View {
        // Product initials make the unavailable-artwork state recognizable
        // without inventing a vendor logo or bundling unlicensed artwork.
        let initials = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
            Text(initials.isEmpty ? "APP" : initials)
                .font(.system(size: size * (initials.count > 2 ? 0.23 : 0.32), weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}
