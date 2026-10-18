// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI
import ImageIO
import PDFKit

enum FeedbackState:String { case queued,running,success,failed,cancelled
    var label:String {
        switch self {
        case .queued:return "Waiting · في الانتظار"
        case .running:return "Working… · جارٍ التنفيذ…"
        case .success:return "Done · تم بنجاح"
        case .failed:return "Couldn’t finish · تعذّر الإكمال"
        case .cancelled:return "Cancelled · تم الإلغاء"
        }
    }
    var busy:Bool { self == .queued || self == .running }
}
final class ActionFeedback:ObservableObject,Identifiable {
    let id=UUID()
    let title:String
    let source:String
    @Published var state:FeedbackState = .queued
    @Published var details=""
    @Published var outputs:[URL]=[]
    @Published var previews:[URL]=[]
    var cancel:(()->Void)?
    init(title:String,source:String) { self.title=title;self.source=source }
    static func previewFiles(_ outputs:[URL])->(files:[URL],count:Int) {
        var candidates:[URL]=[];var count=0
        for url in outputs {
            let directory=(try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false
            if directory,let contents=try? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles]) {
                let ordered=contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                count += ordered.count;candidates += ordered.prefix(3)
            } else { count += 1;candidates.append(url) }
        }
        return (Array(candidates.prefix(3)),count)
    }
}
struct ResultThumbnail:View {
    let url:URL
    @State private var thumbnail:NSImage?
    var body:some View {
        Button { NSWorkspace.shared.open(url) } label: {
            VStack(spacing:5) {
                Group {
                    if let thumbnail { Image(nsImage:thumbnail).resizable().scaledToFit() }
                    else { Image(systemName:"doc").font(.system(size:28)).foregroundStyle(.white.opacity(0.6)) }
                }.frame(width:108,height:68).background(.black.opacity(0.15),in:RoundedRectangle(cornerRadius:8))
                Text(url.lastPathComponent).font(.system(size:9)).lineLimit(1).frame(width:108)
            }
        }.buttonStyle(.plain).help(bilingual("Open preview","فتح المعاينة"))
        .task(id:url) {
            let result=await Task.detached(priority:.utility) { () -> NSImage? in
                if let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:224,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) { return NSImage(cgImage:cg,size:.zero) }
                if url.pathExtension.lowercased()=="pdf",let page=PDFDocument(url:url)?.page(at:0) { return page.thumbnail(of:NSSize(width:224,height:136),for:.mediaBox) }
                return nil
            }.value
            thumbnail=result ?? NSWorkspace.shared.icon(forFile:url.path)
        }
    }
}
struct ActionFeedbackView:View {
    @ObservedObject var model:ActionFeedback
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                if model.state.busy { ProgressView().controlSize(.small).padding(.top,3) }
                else { Image(systemName:model.state == .success ? "checkmark.circle.fill":model.state == .failed ? "exclamationmark.circle":"xmark.circle").font(.system(size:20)).foregroundStyle(model.state == .success ? Color.green.opacity(0.9):.white.opacity(0.75)) }
                VStack(alignment:.leading,spacing:5) {
                    Text(model.title).font(.system(size:14,weight:.semibold)).lineLimit(2)
                    Text(model.state.label).font(.system(size:11)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength:0)
                Button { FeedbackCenter.shared.dismiss(model) } label: { Image(systemName:"xmark").font(.system(size:10,weight:.medium)).frame(width:22,height:22).background(.white.opacity(0.07),in:Circle()) }.buttonStyle(.plain).help("Close · إغلاق")
            }
            if !model.source.isEmpty { Text(model.source).font(.system(size:11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
            if !model.details.isEmpty { Text(model.details).font(.system(size:11)).foregroundStyle(.white.opacity(0.65)).lineLimit(model.state == .failed ? 5:3).textSelection(.enabled) }
            if !model.previews.isEmpty { HStack(alignment:.top,spacing:10) { ForEach(model.previews,id:\.self) { ResultThumbnail(url:$0) } } }
            HStack(spacing:10) {
                if model.state.busy { Button("Cancel · إلغاء") { model.cancel?() }.buttonStyle(.bordered) }
                if let first=model.outputs.first {
                    Button("Open result · فتح الناتج") { NSWorkspace.shared.open(first) }.buttonStyle(.borderedProminent).tint(.white.opacity(0.2))
                    Button("Show folder · إظهار المجلد") { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }.buttonStyle(.bordered)
                }
                Spacer(minLength:0)
            }.font(.system(size:10))
        }.padding(20).frame(width:420,alignment:.leading).foregroundStyle(.white.opacity(0.95)).background(GlassSurface()).preferredColorScheme(.dark)
    }
}
final class FeedbackCenter {
    static let shared=FeedbackCenter()
    var cards:[UUID:(NSPanel,ActionFeedback)]=[:]
    var order:[UUID]=[]
    var last:ActionFeedback?
    func start(title:String,urls:[URL],cancel:(()->Void)?=nil)->ActionFeedback {
        let model=ActionFeedback(title:title,source:urls.isEmpty ? "":urls.count == 1 ? urls[0].lastPathComponent:"\(urls.count) files · ملفات")
        model.cancel=cancel;present(model);return model
    }
    func present(_ model:ActionFeedback) {
        if let (window,_)=cards[model.id] { window.orderFrontRegardless();return }
        let window=NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:180),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        configureGlassWindow(window);window.level = .floating;window.hidesOnDeactivate=false;window.isFloatingPanel=true
        window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        window.contentView=NSHostingView(rootView:ActionFeedbackView(model:model));window.isReleasedWhenClosed=false
        cards[model.id]=(window,model);order.append(model.id);resize(model);window.orderFrontRegardless()
        if order.count>3,let first=order.first,let old=cards[first]?.1 { dismiss(old) }
    }
    func resize(_ model:ActionFeedback) {
        guard let (window,_)=cards[model.id],let view=window.contentView else { return }
        view.layoutSubtreeIfNeeded();window.setContentSize(view.fittingSize)
        if let screen=NSScreen.main {
            let index=order.firstIndex(of:model.id) ?? 0
            let offset=CGFloat(index%2)*36
            window.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-window.frame.width-24-offset,y:screen.visibleFrame.minY+24+offset))
        }
    }
    func running(_ model:ActionFeedback?) { guard let model else { return };model.state = .running;resize(model) }
    func complete(_ model:ActionFeedback?,outputs:[URL],files:[URL],count:Int) {
        guard let model else { return }
        model.state = .success;model.outputs=outputs;model.previews=files
        model.details="\(count) result(s) saved beside the source.\nتم حفظ الناتج بجانب الملف الأصلي."
        last=model;resize(model);ActionSound.play("success",volume:0.5);expire(model,after:35)
    }
    func failed(_ model:ActionFeedback?,message:String) {
        guard let model else { return };model.state = .failed;model.details=message;last=model;resize(model);ActionSound.play("failure",volume:0.5)
    }
    func cancelled(_ model:ActionFeedback?) { guard let model else { return };model.state = .cancelled;model.details="Stopped. Any completed copies remain beside their sources.\nتم الإيقاف. تبقى النسخ المكتملة بجانب ملفاتها الأصلية.";resize(model);expire(model,after:10) }
    func notice(_ message:String,urls:[URL]=[]) {
        let model=start(title:message,urls:urls);model.state = .success;last=model;resize(model);expire(model,after:12)
    }
    func showLast() {
        if let last { present(last) } else { notice("No actions yet · لا توجد إجراءات بعد") }
    }
    func expire(_ model:ActionFeedback,after seconds:Double) {
        DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { [weak self,weak model] in
            guard let model else { return };self?.dismiss(model)
        }
    }
    func dismiss(_ model:ActionFeedback) { cards.removeValue(forKey:model.id)?.0.orderOut(nil);order.removeAll {$0==model.id} }
}
