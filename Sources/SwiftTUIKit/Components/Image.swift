import Foundation

public struct ImageTheme: Sendable {
    public var fallbackColor: @Sendable (String) -> String

    public init(fallbackColor: @escaping @Sendable (String) -> String = { $0 }) {
        self.fallbackColor = fallbackColor
    }
}

public struct ImageOptions: Sendable, Equatable {
    public var maxWidthCells: Int?
    public var maxHeightCells: Int?
    public var filename: String?
    public var imageId: UInt32?

    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, filename: String? = nil, imageId: UInt32? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.filename = filename
        self.imageId = imageId
    }
}

public final class Image: Component, @unchecked Sendable {
    private let base64Data: String
    private let mimeType: String
    private let theme: ImageTheme
    private var options: ImageOptions
    private var dimensions: ImageDimensions
    private var imageId: UInt32?

    private var cachedLines: [String]?
    private var cachedWidth: Int?

    public init(
        base64Data: String,
        mimeType: String,
        theme: ImageTheme = .init(),
        options: ImageOptions = .init(),
        dimensions: ImageDimensions? = nil
    ) {
        self.base64Data = base64Data
        self.mimeType = mimeType
        self.theme = theme
        self.options = options
        self.dimensions = dimensions ?? getImageDimensions(base64Data: base64Data, mimeType: mimeType) ?? ImageDimensions(widthPx: 800, heightPx: 600)
        self.imageId = options.imageId
    }

    public func getImageId() -> UInt32? { imageId }

    public func invalidate() {
        cachedLines = nil
        cachedWidth = nil
    }

    public func render(width: Int) -> [String] {
        if cachedWidth == width, let cachedLines { return cachedLines }

        let maxWidth = min(max(1, width - 2), options.maxWidthCells ?? 60)
        let maxHeight = options.maxHeightCells

        let caps = getCapabilities()
        var lines: [String] = []

        if caps.images != .none {
            let result = renderImage(
                base64Data: base64Data,
                dimensions: dimensions,
                options: ImageRenderOptions(
                    maxWidthCells: maxWidth,
                    maxHeightCells: maxHeight,
                    preserveAspectRatio: true,
                    imageId: imageId
                )
            )

            if let result {
                if let id = result.imageId { imageId = id }

                // Make TUI account for image height: return `rows` lines.
                // First (rows-1) are empty. Last line contains a cursor-up prefix + image sequence.
                if result.rows > 1 {
                    for _ in 0..<(result.rows - 1) { lines.append("") }
                    lines.append("\u{001B}[\(result.rows - 1)A" + result.sequence)
                } else {
                    lines.append(result.sequence)
                }
            } else {
                let fallback = imageFallback(mimeType: mimeType, dimensions: dimensions, filename: options.filename)
                lines = [theme.fallbackColor(fallback)]
            }
        } else {
            let fallback = imageFallback(mimeType: mimeType, dimensions: dimensions, filename: options.filename)
            lines = [theme.fallbackColor(fallback)]
        }

        cachedWidth = width
        cachedLines = lines
        return lines
    }
}

