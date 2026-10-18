// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI

let glassAccent = Color(white:0.94)

struct GlassMaterial:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance=NSAppearance(named:.vibrantDark)
        return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}
struct GlassSurface:View {
    var body:some View {
        ZStack {
            GlassMaterial()
            LinearGradient(colors:[Color.white.opacity(0.065),Color.black.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing)
            LinearGradient(colors:[.white.opacity(0.08),.clear,.clear],startPoint:.topLeading,endPoint:.bottomTrailing)
        }.clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).strokeBorder(LinearGradient(colors:[.white.opacity(0.34),glassAccent.opacity(0.14),.white.opacity(0.09)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
        .allowsHitTesting(false)
    }
}
func configureGlassWindow(_ window:NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent=true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none
    window.isOpaque=false
    window.backgroundColor = .clear
    window.hasShadow=true
    window.isMovableByWindowBackground=true
    window.appearance=NSAppearance(named:.vibrantDark)
    for kind in [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton] { window.standardWindowButton(kind)?.isHidden=true }
}
