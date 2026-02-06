import Foundation

#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

public enum ImageProtocol: String, Sendable {
    case kitty
    case iterm2
    case none
}

public struct TerminalCapabilities: Sendable, Equatable {
    public var images: ImageProtocol
    public var trueColor: Bool
    public var hyperlinks: Bool

    public init(images: ImageProtocol, trueColor: Bool, hyperlinks: Bool) {
        self.images = images
        self.trueColor = trueColor
        self.hyperlinks = hyperlinks
    }
}

public struct CellDimensions: Sendable, Equatable {
    public var widthPx: Int
    public var heightPx: Int

    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

public struct ImageDimensions: Sendable, Equatable {
    public var widthPx: Int
    public var heightPx: Int

    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

public struct ImageRenderOptions: Sendable, Equatable {
    public var maxWidthCells: Int?
    public var maxHeightCells: Int?
    public var preserveAspectRatio: Bool?
    public var imageId: UInt32?

    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, preserveAspectRatio: Bool? = nil, imageId: UInt32? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.preserveAspectRatio = preserveAspectRatio
        self.imageId = imageId
    }
}

private final class TerminalImageState: @unchecked Sendable {
    let lock = NSLock()
    var cachedCaps: TerminalCapabilities?
    var cellDims: CellDimensions = .init(widthPx: 9, heightPx: 18)
}

private let terminalImageState = TerminalImageState()

public func getCellDimensions() -> CellDimensions {
    terminalImageState.lock.lock()
    defer { terminalImageState.lock.unlock() }
    return terminalImageState.cellDims
}

public func setCellDimensions(_ dims: CellDimensions) {
    terminalImageState.lock.lock()
    terminalImageState.cellDims = dims
    terminalImageState.lock.unlock()
}

public func resetCapabilitiesCache() {
    terminalImageState.lock.lock()
    terminalImageState.cachedCaps = nil
    terminalImageState.lock.unlock()
}

public func detectCapabilities(env: [String: String] = ProcessInfo.processInfo.environment) -> TerminalCapabilities {
    let termProgram = (env["TERM_PROGRAM"] ?? "").lowercased()
    let term = (env["TERM"] ?? "").lowercased()
    let colorTerm = (env["COLORTERM"] ?? "").lowercased()

    if env["KITTY_WINDOW_ID"] != nil || termProgram == "kitty" {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if termProgram == "ghostty" || term.contains("ghostty") || env["GHOSTTY_RESOURCES_DIR"] != nil {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if env["WEZTERM_PANE"] != nil || termProgram == "wezterm" {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if env["ITERM_SESSION_ID"] != nil || termProgram == "iterm.app" {
        return TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true)
    }

    if termProgram == "vscode" {
        return TerminalCapabilities(images: .none, trueColor: true, hyperlinks: true)
    }

    if termProgram == "alacritty" {
        return TerminalCapabilities(images: .none, trueColor: true, hyperlinks: true)
    }

    let trueColor = (colorTerm == "truecolor" || colorTerm == "24bit")
    return TerminalCapabilities(images: .none, trueColor: trueColor, hyperlinks: true)
}

public func getCapabilities() -> TerminalCapabilities {
    terminalImageState.lock.lock()
    if let c = terminalImageState.cachedCaps {
        terminalImageState.lock.unlock()
        return c
    }
    terminalImageState.lock.unlock()

    let c = detectCapabilities()
    terminalImageState.lock.lock()
    terminalImageState.cachedCaps = c
    terminalImageState.lock.unlock()
    return c
}

private let kittyPrefix = "\u{001B}_G"
private let iterm2Prefix = "\u{001B}]1337;File="

public func isImageLine(_ line: String) -> Bool {
    if line.hasPrefix(kittyPrefix) || line.hasPrefix(iterm2Prefix) { return true }
    return line.contains(kittyPrefix) || line.contains(iterm2Prefix)
}

public func allocateImageId() -> UInt32 {
    UInt32.random(in: 1...UInt32.max - 1)
}

public func encodeKitty(base64Data: String, columns: Int? = nil, rows: Int? = nil, imageId: UInt32? = nil) -> String {
    let chunkSize = 4096
    var params: [String] = ["a=T", "f=100", "q=2"]
    if let columns { params.append("c=\(columns)") }
    if let rows { params.append("r=\(rows)") }
    if let imageId { params.append("i=\(imageId)") }

    if base64Data.count <= chunkSize {
        return "\u{001B}_G" + params.joined(separator: ",") + ";" + base64Data + "\u{001B}\\"
    }

    var chunks: [String] = []
    chunks.reserveCapacity((base64Data.count / chunkSize) + 2)

    var offset = 0
    var isFirst = true
    let chars = Array(base64Data)
    while offset < chars.count {
        let end = min(chars.count, offset + chunkSize)
        let chunk = String(chars[offset..<end])
        let isLast = end >= chars.count

        if isFirst {
            chunks.append("\u{001B}_G" + params.joined(separator: ",") + ",m=1;" + chunk + "\u{001B}\\")
            isFirst = false
        } else if isLast {
            chunks.append("\u{001B}_Gm=0;" + chunk + "\u{001B}\\")
        } else {
            chunks.append("\u{001B}_Gm=1;" + chunk + "\u{001B}\\")
        }

        offset = end
    }

    return chunks.joined()
}

public func deleteKittyImage(_ imageId: UInt32) -> String {
    "\u{001B}_Ga=d,d=I,i=\(imageId)\u{001B}\\"
}

public func deleteAllKittyImages() -> String {
    "\u{001B}_Ga=d,d=A\u{001B}\\"
}

public func encodeITerm2(
    base64Data: String,
    width: String? = nil,
    height: String? = nil,
    name: String? = nil,
    preserveAspectRatio: Bool? = nil,
    inline: Bool = true
) -> String {
    var params: [String] = ["inline=\(inline ? 1 : 0)"]
    if let width { params.append("width=\(width)") }
    if let height { params.append("height=\(height)") }
    if let name {
        if let d = name.data(using: .utf8) {
            params.append("name=\(d.base64EncodedString())")
        }
    }
    if preserveAspectRatio == false {
        params.append("preserveAspectRatio=0")
    }
    return "\u{001B}]1337;File=" + params.joined(separator: ";") + ":" + base64Data + "\u{0007}"
}

public func calculateImageRows(imageDimensions: ImageDimensions, targetWidthCells: Int, cellDimensions: CellDimensions = getCellDimensions()) -> Int {
    let targetWidthPx = targetWidthCells * max(1, cellDimensions.widthPx)
    let scale = Double(targetWidthPx) / Double(max(1, imageDimensions.widthPx))
    let scaledHeightPx = Double(imageDimensions.heightPx) * scale
    let rows = Int(ceil(scaledHeightPx / Double(max(1, cellDimensions.heightPx))))
    return max(1, rows)
}

public func getImageDimensions(base64Data: String, mimeType: String) -> ImageDimensions? {
    guard let data = Data(base64Encoded: base64Data) else { return nil }

    #if canImport(ImageIO)
    let cf = data as CFData
    guard let src = CGImageSourceCreateWithData(cf, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
    let w = props[kCGImagePropertyPixelWidth] as? NSNumber
    let h = props[kCGImagePropertyPixelHeight] as? NSNumber
    if let w, let h {
        return ImageDimensions(widthPx: w.intValue, heightPx: h.intValue)
    }
    return nil
    #else
    _ = mimeType
    return nil
    #endif
}

public func imageFallback(mimeType: String, dimensions: ImageDimensions, filename: String?) -> String {
    let name = filename.map { "\($0) " } ?? ""
    return "[image \(name)\(mimeType) \(dimensions.widthPx)x\(dimensions.heightPx)]"
}

public struct RenderedImage: Sendable, Equatable {
    public var sequence: String
    public var rows: Int
    public var imageId: UInt32?

    public init(sequence: String, rows: Int, imageId: UInt32?) {
        self.sequence = sequence
        self.rows = rows
        self.imageId = imageId
    }
}

public func renderImage(
    base64Data: String,
    dimensions: ImageDimensions,
    options: ImageRenderOptions = .init()
) -> RenderedImage? {
    let caps = getCapabilities()
    guard caps.images != .none else { return nil }

    let cellDims = getCellDimensions()

    let maxW = max(1, options.maxWidthCells ?? 60)
    let maxH = max(1, options.maxHeightCells ?? Int.max)
    let preserve = options.preserveAspectRatio ?? true

    var targetW = maxW
    var rows = calculateImageRows(imageDimensions: dimensions, targetWidthCells: targetW, cellDimensions: cellDims)
    if rows > maxH, preserve {
        // Clamp by height by adjusting width while preserving aspect ratio.
        let targetHeightPx = Double(maxH * max(1, cellDims.heightPx))
        let scale = targetHeightPx / Double(max(1, dimensions.heightPx))
        let targetWidthPx = Double(dimensions.widthPx) * scale
        targetW = max(1, Int(floor(targetWidthPx / Double(max(1, cellDims.widthPx)))))
        rows = calculateImageRows(imageDimensions: dimensions, targetWidthCells: targetW, cellDimensions: cellDims)
    }
    rows = min(rows, maxH)

    switch caps.images {
    case .kitty:
        let id = options.imageId ?? allocateImageId()
        let seq = encodeKitty(base64Data: base64Data, columns: targetW, rows: rows, imageId: id)
        return RenderedImage(sequence: seq, rows: rows, imageId: id)
    case .iterm2:
        // iTerm2 uses cells for width/height when plain numbers are supplied.
        let seq = encodeITerm2(
            base64Data: base64Data,
            width: String(targetW),
            height: String(rows),
            name: nil,
            preserveAspectRatio: preserve,
            inline: true
        )
        return RenderedImage(sequence: seq, rows: rows, imageId: nil)
    case .none:
        return nil
    }
}

