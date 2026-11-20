import AppKit
import SwiftUI

/// Liquid Glass resolves to the real system material on macOS 26 and to a vibrancy approximation
/// below it, so every surface keeps the same shape and hit-testing on macOS 15.
struct TinyGlass {
    enum Base {
        case regular
        case identity
    }

    var base: Base = .regular
    var isInteractive = false
    var tint: Color?

    static let regular = TinyGlass()
    static let identity = TinyGlass(base: .identity)

    func interactive() -> TinyGlass {
        var copy = self
        copy.isInteractive = true
        return copy
    }
}

extension TinyGlass {
    func tint(_ color: Color?) -> TinyGlass {
        var copy = self
        copy.tint = color
        return copy
    }

    @available(macOS 26.0, *)
    var systemGlass: Glass {
        guard base == .regular else { return .identity }
        var glass: Glass = .regular
        if isInteractive { glass = glass.interactive() }
        if let tint { glass = glass.tint(tint) }
        return glass
    }
}

extension View {
    func tinyGlass(_ style: TinyGlass = .regular, in shape: some Shape) -> some View {
        modifier(TinyGlassModifier(style: style, shape: AnyShape(shape)))
    }
}

private struct TinyGlassModifier: ViewModifier {
    let style: TinyGlass
    let shape: AnyShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(style.systemGlass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .clipShape(shape)
        }
    }
}

/// `GlassEffectContainer`'s stand-in: below macOS 26 the children simply stay siblings, which is
/// what the container does before it starts blending them.
struct TinyGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// The AppKit half: a real `NSGlassEffectView` where the system has one, an `NSVisualEffectView`
/// elsewhere. Typed as `NSView` so one representable serves both.
struct GlassEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            return NSGlassEffectView()
        }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
