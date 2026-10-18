// SPDX-License-Identifier: AGPL-3.0-only
import AppKit

private final class ActionBarCanvas:NSView {
    weak var owner:ActionBarView?
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) { owner?.drawBar(dirtyRect) }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}
final class ActionBarView:NSView {
    private let canvas=ActionBarCanvas(frame:.zero)
    var actions:[WheelAction]=[] { didSet { hovered=nil;needsDisplay=true;canvas.needsDisplay=true } }
    var mode:WheelMode = .actions { didSet { needsDisplay=true;canvas.needsDisplay=true } }
    var category="" { didSet { needsDisplay=true;canvas.needsDisplay=true } }
    var hovered:Int? { didSet { if oldValue != hovered { needsDisplay=true;canvas.needsDisplay=true;if hovered != nil { ActionSound.play("hover",volume:0.55) } } } }
    var onDrop:((WheelAction,[URL])->Void)?
    var onExit:(()->Void)?
    var preferredSize:NSSize { NSSize(width:max(292,CGFloat(actions.count)*66+16),height:108) }
    var centerPoint:NSPoint { NSPoint(x:bounds.midX,y:99) }
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true;layer?.cornerRadius=14;layer?.masksToBounds=true
        let glass=NSVisualEffectView(frame:bounds);glass.material = .hudWindow;glass.blendingMode = .behindWindow;glass.state = .active;glass.appearance=NSAppearance(named:.vibrantDark)
        glass.autoresizingMask=[.width,.height];addSubview(glass)
        canvas.frame=bounds;canvas.owner=self;canvas.autoresizingMask=[.width,.height];addSubview(canvas)
        registerForDraggedTypes([.fileURL]);setAccessibilityLabel("Anasing action bar · شريط إجراءات أناسينغ")
    }
    required init?(coder:NSCoder) { fatalError() }
    func buttonRect(_ index:Int)->NSRect {
        let gap:CGFloat=4
        let width=(bounds.width-16-gap*CGFloat(max(0,actions.count-1)))/CGFloat(max(1,actions.count))
        return NSRect(x:8+CGFloat(index)*(width+gap),y:28,width:width,height:56)
    }
    func center(for index:Int)->NSPoint { let r=buttonRect(index);return NSPoint(x:r.midX,y:r.midY) }
    func action(at point:NSPoint)->Int? { actions.indices.first { buttonRect($0).contains(point) } }
    func drawBar(_ dirtyRect:NSRect) {
        NSColor.white.withAlphaComponent(0.045).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:14,yRadius:14).fill()
        NSColor.white.withAlphaComponent(0.2).setStroke();let edge=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:14,yRadius:14);edge.lineWidth=1;edge.stroke()
        text(mode.label,in:NSRect(x:12,y:7,width:bounds.width-24,height:16),size:9,color:.white,alignment:.left)
        for (index,action) in actions.enumerated() {
            let rect=buttonRect(index),selected=hovered==index
            let fill=selected ? 0.23:0.045
            NSColor.white.withAlphaComponent(fill).setFill();NSBezierPath(roundedRect:rect,xRadius:11,yRadius:11).fill()
            if selected { NSColor.white.withAlphaComponent(0.35).setStroke();NSBezierPath(roundedRect:rect.insetBy(dx:0.5,dy:0.5),xRadius:11,yRadius:11).stroke() }
            let foreground=NSColor.white.withAlphaComponent(action.available ? 0.96:0.3)
            if !action.symbol.isEmpty {
                if let icon=NSImage(systemSymbolName:action.symbol,accessibilityDescription:action.displayTitle)?.withSymbolConfiguration(.init(pointSize:15,weight:.medium)) {
                    let tinted=NSImage(size:icon.size,flipped:false) { r in icon.draw(in:r);foreground.setFill();r.fill(using:.sourceIn);return true }
                    tinted.draw(in:NSRect(x:rect.midX-7.5,y:rect.minY+6,width:15,height:15),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                }
                text(action.title,in:NSRect(x:rect.minX+3,y:rect.minY+25,width:rect.width-6,height:13),size:8,color:foreground)
                text(action.arabicTitle,in:NSRect(x:rect.minX+3,y:rect.minY+38,width:rect.width-6,height:16),size:10,color:foreground)
            } else {
                text(action.title,in:NSRect(x:rect.minX+3,y:rect.minY+8,width:rect.width-6,height:19),size:12,color:foreground)
                text(action.arabicTitle,in:NSRect(x:rect.minX+3,y:rect.minY+30,width:rect.width-6,height:18),size:10,color:foreground)
            }
        }
        let selected=hovered.flatMap { actions.indices.contains($0) ? actions[$0]:nil }
        let caption=selected?.available == false ? "Pages needs Apple Pages · يتطلب تطبيق Pages":actions.isEmpty ? "Tap ⌃ for file actions · اضغط ⌃ للإجراءات":"Drop on an option · أفلت على الخيار لتنفيذه"
        text(caption,in:NSRect(x:8,y:91,width:bounds.width-16,height:14),size:9,color:.white.withAlphaComponent(0.6))
    }
    func text(_ string:String,in rect:NSRect,size:CGFloat,color:NSColor,alignment:NSTextAlignment = .center) {
        let paragraph=NSMutableParagraphStyle();paragraph.alignment=alignment;paragraph.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color,.paragraphStyle:paragraph])
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation { update(sender) }
    override func wantsPeriodicDraggingUpdates()->Bool { true }
    func update(_ sender:NSDraggingInfo)->NSDragOperation {
        hovered=action(at:convert(sender.draggingLocation,from:nil))
        guard let index=hovered,actions[index].available else { return [] };return .copy
    }
    override func draggingExited(_ sender:NSDraggingInfo?) { hovered=nil }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let index=action(at:convert(sender.draggingLocation,from:nil)) else { return false }
        return actions[index].available && !fileURLs(from:sender.draggingPasteboard).isEmpty
    }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool { acceptDrop(at:convert(sender.draggingLocation,from:nil),urls:fileURLs(from:sender.draggingPasteboard)) }
    func acceptDrop(at point:NSPoint,urls:[URL])->Bool {
        guard let index=action(at:point),actions[index].available,!urls.isEmpty else { return false }
        ActionSound.play("select",volume:0.95);onDrop?(actions[index],urls);hovered=nil;return true
    }
    override func concludeDragOperation(_ sender:NSDraggingInfo?) { onExit?() }
}
func fileURLs(from board:NSPasteboard)->[URL] { (board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []).filter {$0.isFileURL} }
