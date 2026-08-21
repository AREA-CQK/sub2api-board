import AppKit
import Darwin
import SwiftUI
import WidgetKit

@main
@MainActor
struct RenderWidgetScreenshots {
    private struct Screenshot {
        let name: String
        let family: WidgetFamily
        let size: CGSize
    }

    static func main() throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/screenshots")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let screenshots = [
            Screenshot(name: "widget-small", family: .systemSmall, size: CGSize(width: 169, height: 169)),
            Screenshot(name: "widget-medium", family: .systemMedium, size: CGSize(width: 360, height: 169)),
            Screenshot(name: "widget-large", family: .systemLarge, size: CGSize(width: 360, height: 378))
        ]

        for screenshot in screenshots {
            let view = BoardWidgetView(
                entry: BoardEntry(date: Date(), snapshot: .preview, error: nil),
                familyOverride: screenshot.family
            )
            .padding(16)
            .frame(width: screenshot.size.width, height: screenshot.size.height)
            .background(BoardTheme.canvas)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(
                to: outputDirectory.appendingPathComponent("\(screenshot.name).png"),
                options: Data.WritingOptions.atomic
            )
        }
        exit(EXIT_SUCCESS)
    }
}
