import OpusBarCore
import SwiftUI

/// The pixel cat for one state. Animates only while on screen, and never with Reduce Motion.
struct CatView: View {
    let state: SessionState?
    var points: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.catAnimates) private var catAnimates

    var body: some View {
        let animation = CatAnimation.for(state)
        if animation.isAnimated && catAnimates && !reduceMotion {
            TimelineView(.animation(minimumInterval: animation.interval)) { context in
                frame(animation, index: Int(context.date.timeIntervalSinceReferenceDate / animation.interval))
            }
        } else {
            frame(animation, index: 0)
        }
    }

    @ViewBuilder
    private func frame(_ animation: CatAnimation, index: Int) -> some View {
        let f = animation.frames[index % animation.frames.count]
        if let image = CatSheet.shared.frame(col: f.col, row: f.row) {
            Image(decorative: image, scale: CGFloat(CatSheet.framePixels) / points)
                .interpolation(.none)
                .frame(width: points, height: points)
        } else {
            Color.clear.frame(width: points, height: points)
        }
    }
}

/// Brand tile colors per state (mockups: blue working, pink thinking, yellow needs you, green done, red error).
extension SessionState {
    var tileColor: Color {
        switch self {
        case .idle: Color(red: 0.878, green: 0.859, blue: 0.808)
        case .thinking: Color(red: 0.922, green: 0.757, blue: 1.0)
        case .working: Color(red: 0.169, green: 0.627, blue: 1.0)
        case .needsAttention: Color(red: 0.961, green: 0.886, blue: 0.067)
        case .done: Color(red: 0.557, green: 0.831, blue: 0.384)
        case .error: Color(red: 1.0, green: 0.439, blue: 0.365)
        }
    }

    var badgeColor: NSColor { NSColor(tileColor) }
}
