import AppKit
import OpusBarCore
import UserNotifications

/// The cat a notification shows, drawn the way OpusBar shows it right now: the chosen coat, the
/// state's pose, on the state's colour. macOS always puts the app icon on the left of a banner; this
/// rides along as the attachment thumbnail on the right.
@MainActor
enum NotificationCat {
    static let pixels = 128

    static func attachment(state: SessionState, coat: CatCoat, poses: CatPoses) -> UNNotificationAttachment? {
        let pose = poses.pose(for: state)
        let url = folder.appending(path: "\(coat.rawValue)-\(pose.rawValue)-\(state.rawValue).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let data = render(state: state, coat: coat, pose: pose) else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        }
        // The system copies the file, so the cached one stays for the next notification.
        return try? UNNotificationAttachment(identifier: "cat", url: url, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"])
    }

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "OpusBar").appending(path: "NotificationCats")
    }

    private static func render(state: SessionState, coat: CatCoat, pose: CatPose) -> Data? {
        let frame = pose.frames[0]
        guard let cat = CatSheet.sheet(for: coat).frame(col: frame.col, row: frame.row),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGFloat(pixels)
        context.setFillColor(NSColor(state.tileColor).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: 28, cornerHeight: 28, transform: nil))
        context.fillPath()
        context.interpolationQuality = .none
        let inset = size * 0.125
        context.draw(cat, in: CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
