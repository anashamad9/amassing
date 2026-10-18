// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI
import CoreGraphics
import PDFKit

struct ModifierLatch {
    var previous:NSEvent.ModifierFlags=[]
    var mode:WheelMode?
    var cancelled=false
    mutating func update(flags:NSEvent.ModifierFlags,dragging:Bool)->WheelMode? {
        defer { previous=flags }
        guard dragging else { mode=nil;cancelled=false;return nil }
        guard !cancelled else { return nil }
        let pressed=flags.subtracting(previous)
        let candidate=mode == nil ? flags:pressed
        if candidate.contains(.control) { mode = .actions }
        else if candidate.contains(.command) { mode = .tools }
        else if candidate.contains(.shift) { mode = .conversions }
        return mode
    }
    mutating func cancel() { mode=nil;cancelled=true }
}
final class AppDelegate:NSObject,NSApplicationDelegate {
    var panel:NSPanel!
    var bar:ActionBarView!
    var status:NSStatusItem!
    var loginItem:NSMenuItem?
    var loginApprovalItem:NSMenuItem?
    var timer:Timer?
    var barAnchor:NSPoint?
    var releaseAt:Date?
    var paused=false
    var previewUntil:Date?
    var idleDragVersion=NSPasteboard(name:.drag).changeCount
    var currentVersion:Int?
    var latch=ModifierLatch()
    var activeURLs:[URL]=[]
    let runner=JobRunner()
    let files=FileActions()
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:108),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .popUpMenu;panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        bar=ActionBarView(frame:NSRect(x:0,y:0,width:420,height:108));panel.contentView=bar
        bar.onDrop={ [weak self] action,urls in
            self?.latch.cancel();self?.hide()
            DispatchQueue.main.async { self?.perform(action,urls:urls) }
        }
        bar.onExit={ [weak self] in self?.hide() }
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"circle.hexagongrid",accessibilityDescription:"Anasing")
        status.button?.toolTip="Anasing · Drag, then tap ⇧ Convert · ⌘ Tools · ⌃ Actions"
        runner.activityChanged={ [weak self] count in
            self?.status.button?.image=NSImage(systemSymbolName:count>0 ? "arrow.triangle.2.circlepath":"circle.hexagongrid",accessibilityDescription:"Anasing")
            self?.status.button?.toolTip=count>0 ? "Anasing · \(count) action(s) in progress · use the menu to cancel":"Anasing · Drag, then tap ⇧ Convert · ⌘ Tools · ⌃ Actions"
        }
        let menu=NSMenu()
        menu.addItem(withTitle:"Drag a file, then tap a key · اسحب ملفاً ثم اضغط مفتاحاً",action:nil,keyEquivalent:"")
        menu.addItem(withTitle:"⇧ تحويل    ⌘ أدوات    ⌃ إجراءات",action:nil,keyEquivalent:"")
        menu.addItem(.separator())
        let previews=NSMenu()
        for category in FileCategory.allCases where category != .other {
            let item=NSMenuItem(title:bilingual(category.rawValue.capitalized,category.arabicName),action:#selector(previewActions(_:)),keyEquivalent:"");item.representedObject=category.rawValue;item.target=self;previews.addItem(item)
        }
        let item=NSMenuItem(title:"Preview actions · معاينة الخيارات",action:nil,keyEquivalent:"");item.submenu=previews;menu.addItem(item)
        menu.addItem(withTitle:"Allow folder access… · السماح بالوصول للمجلد",action:#selector(allowFolderAccess),keyEquivalent:"")
        menu.addItem(withTitle:"Last result · آخر نتيجة",action:#selector(showLastResult),keyEquivalent:"")
        let soundItem=menu.addItem(withTitle:"Sound effects · المؤثرات الصوتية",action:#selector(toggleSounds(_:)),keyEquivalent:"")
        soundItem.state=UserDefaults.standard.bool(forKey:"muteSounds") ? .off:.on
        loginItem=menu.addItem(withTitle:"Launch at login · التشغيل عند تسجيل الدخول",action:#selector(toggleLoginLaunch),keyEquivalent:"")
        loginApprovalItem=menu.addItem(withTitle:"Approve startup in Settings… · السماح من الإعدادات",action:#selector(openLoginSettings),keyEquivalent:"")
        refreshLoginMenu();menu.delegate=self
        menu.addItem(withTitle:"Cancel running actions · إلغاء الإجراءات",action:#selector(cancelActions),keyEquivalent:"")
        menu.addItem(withTitle:"Pause Anasing · إيقاف مؤقت",action:#selector(togglePause(_:)),keyEquivalent:"")
        menu.addItem(.separator());menu.addItem(withTitle:"Quit Anasing · إنهاء",action:#selector(quit),keyEquivalent:"q")
        menu.items.forEach { $0.target=self };status.menu=menu
        timer=Timer(timeInterval:0.02,repeats:true) { [weak self] _ in self?.poll() };RunLoop.main.add(timer!,forMode:.common)
        let args=ProcessInfo.processInfo.arguments
        if args.contains("--enable-login") {
            do { try LoginLaunch.enable();UserDefaults.standard.set(true,forKey:"configuredLaunchAtLogin") }
            catch { fputs("Login registration failed: \(error.localizedDescription)\n",stderr);exit(1) }
            print("ANASING_LOGIN_STATUS="+LoginLaunch.stateName);NSApp.terminate(nil)
        }
        if args.contains("--login-status") { print("ANASING_LOGIN_STATUS="+LoginLaunch.stateName);NSApp.terminate(nil) }
        if !args.contains(where:{$0.hasPrefix("--")}) { LoginLaunch.enableOnFirstLaunch();refreshLoginMenu() }
        if args.contains("--smoke-test") {
            smokeTest();print("ANASING_CATALOG_AND_GESTURE_TESTS_PASSED");NSApp.terminate(nil)
        }
        if args.contains("--file-access-test") { fileAccessChecks();NSApp.terminate(nil) }
        if let index=args.firstIndex(of:"--folder-pipeline-test"),args.count>index+1 { folderPipelineTest(at:URL(fileURLWithPath:args[index+1])) }
        if args.contains("--editor-test") { editorTest() }
        if args.contains("--pipeline-test") { pipelineTest() }
        if args.contains("--pdf-feedback-test") { pdfFeedbackTest() }
        if let index=args.firstIndex(of:"--render-feedback"),args.count>index+1 { renderFeedback(to:args[index+1]);NSApp.terminate(nil) }
        if let index=args.firstIndex(of:"--render-editors"),args.count>index+1 { renderEditors(to:args[index+1]);NSApp.terminate(nil) }
        if let index=(args.firstIndex(of:"--render-bar") ?? args.firstIndex(of:"--render-wheel")),args.count>index+1 { renderBars(to:args[index+1]);NSApp.terminate(nil) }
    }
    func poll() {
        guard !paused,NSApp.modalWindow == nil else { return }
        if let until=previewUntil {
            if Date()<until { return }
            previewUntil=nil;hide()
        }
        let held=NSEvent.pressedMouseButtons & 1 != 0
        let flags=NSEvent.modifierFlags
        let board=NSPasteboard(name:.drag)
        if held {
            releaseAt=nil
            guard board.changeCount != idleDragVersion else { _=latch.update(flags:flags,dragging:false);return }
            if currentVersion != board.changeCount {
                activeURLs=fileURLs(from:board);currentVersion=board.changeCount
                _=latch.update(flags:flags,dragging:false)
            }
            guard !activeURLs.isEmpty else { return }
            if CGEventSource.keyState(.combinedSessionState,key:53) { latch.cancel();hide();return }
            let oldMode=latch.mode
            if let mode=latch.update(flags:flags,dragging:true),oldMode != mode || !panel.isVisible {
                bar.mode=mode;bar.actions=Catalog.actions(mode:mode,urls:activeURLs)
                bar.category=activeURLs.count>1 ? "\(activeURLs.count) files":FileCategory.identify(activeURLs[0]).rawValue
                show(at:barAnchor ?? NSEvent.mouseLocation)
            }
        } else {
            _=latch.update(flags:flags,dragging:false);currentVersion=nil;activeURLs=[];idleDragVersion=board.changeCount
            if panel.isVisible {
                if releaseAt == nil { releaseAt=Date() }
                if Date().timeIntervalSince(releaseAt!)>0.2 { hide() }
            }
        }
    }
    func show(at point:NSPoint) {
        let anchor=barAnchor ?? point;barAnchor=anchor
        let screen=NSScreen.screens.first {$0.frame.contains(anchor)} ?? NSScreen.main
        let visible=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let size=NSSize(width:min(bar.preferredSize.width,visible.width-16),height:bar.preferredSize.height)
        let x=min(max(anchor.x-size.width/2,visible.minX+8),visible.maxX-size.width-8)
        let above=anchor.y+18
        let y=above+size.height<=visible.maxY-8 ? above:max(visible.minY+8,anchor.y-size.height-18)
        panel.setFrame(NSRect(origin:NSPoint(x:x,y:y),size:size),display:true)
        bar.frame=NSRect(origin:.zero,size:size);panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil);bar.hovered=nil;releaseAt=nil;barAnchor=nil }
    @objc func previewActions(_ sender:NSMenuItem) {
        let category=FileCategory(rawValue:sender.representedObject as? String ?? "image") ?? .image
        let sample=sampleURL(category)
        let point=NSEvent.mouseLocation
        bar.mode = .conversions;bar.actions=Catalog.actions(mode:.conversions,urls:[sample]);bar.category=category.rawValue
        previewUntil=Date().addingTimeInterval(6);show(at:point)
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
            guard let self,self.previewUntil != nil else { return }
            self.bar.mode = .tools;self.bar.actions=Catalog.actions(mode:.tools,urls:[sample]);self.show(at:self.barAnchor ?? point)
        }
    }
    @objc func togglePause(_ sender:NSMenuItem) { paused.toggle();sender.title=paused ? "Resume Anasing · متابعة":"Pause Anasing · إيقاف مؤقت";latch.cancel();hide() }
    @objc func showLastResult() { FeedbackCenter.shared.showLast() }
    @objc func toggleSounds(_ sender:NSMenuItem) {
        let muted = !UserDefaults.standard.bool(forKey:"muteSounds")
        UserDefaults.standard.set(muted,forKey:"muteSounds");sender.state=muted ? .off:.on
        if !muted { ActionSound.play("select") }
    }
    @objc func cancelActions() { runner.cancelAll() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { timer?.invalidate();runner.cancelAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { true }
    func perform(_ action:WheelAction,urls:[URL]) {
        let scope=SecurityScopeLease(urls);defer { withExtendedLifetime(scope) {} }
        guard action.available else { showError(action.explanation);return }
        if Catalog.universal.contains(where:{$0.id==action.id}) { files.perform(action.id,urls:urls);return }
        guard FileAccess.shared.prepare(urls,writeBeside:true) else { return }
        guard let parameters=editParameters(action:action,urls:urls) else { return }
        runner.run(action:action,urls:urls,parameters:parameters)
    }
    func sampleURL(_ category:FileCategory)->URL {
        let extensions:[FileCategory:String]=[.image:"jpg",.video:"mp4",.audio:"mp3",.pdf:"pdf",.document:"docx",.slides:"pptx",.spreadsheet:"xlsx",.epub:"epub",.subtitle:"srt",.archive:"zip",.other:"bin"]
        return URL(fileURLWithPath:"/tmp/anasing-example."+extensions[category]!)
    }
    func smokeTest() {
        for category in FileCategory.allCases {
            let url=sampleURL(category)
            precondition(FileCategory.identify(url)==category,"Classification \(category)")
            for mode in WheelMode.allCases {
                bar.mode=mode;bar.actions=Catalog.actions(mode:mode,urls:[url])
                bar.frame=NSRect(origin:.zero,size:bar.preferredSize)
                for index in bar.actions.indices { precondition(bar.action(at:bar.center(for:index))==index,"Hit testing \(category) \(mode)") }
                precondition(bar.action(at:bar.centerPoint)==nil)
                precondition(bar.action(at:.zero)==nil)
            }
        }
        var gesture=ModifierLatch()
        precondition(gesture.update(flags:.shift,dragging:false)==nil)
        precondition(gesture.update(flags:.shift,dragging:true) == .conversions)
        precondition(gesture.update(flags:[],dragging:true) == .conversions,"Release must latch")
        precondition(gesture.update(flags:.command,dragging:true) == .tools)
        precondition(gesture.update(flags:[],dragging:true) == .tools)
        precondition(gesture.update(flags:.control,dragging:true) == .actions)
        gesture.cancel();precondition(gesture.update(flags:.shift,dragging:true)==nil)
        precondition(gesture.update(flags:[],dragging:false)==nil)
        precondition(gesture.update(flags:.shift,dragging:true) == .conversions)
        let mixed=[sampleURL(.image),sampleURL(.audio)]
        precondition(Catalog.actions(mode:.conversions,urls:mixed).isEmpty)
        precondition(Catalog.actions(mode:.actions,urls:mixed).count==6)
        precondition(Catalog.actions(mode:.tools,urls:[sampleURL(.image),sampleURL(.image)]).contains {$0.id=="collage"})
        bar.mode = .actions;bar.actions=Catalog.universal;bar.frame=NSRect(origin:.zero,size:bar.preferredSize)
        var received:String?
        let previousDrop=bar.onDrop
        bar.onDrop={ action,urls in received=action.id }
        for index in bar.actions.indices { received=nil;precondition(bar.acceptDrop(at:bar.center(for:index),urls:[sampleURL(.image)]));precondition(received==bar.actions[index].id) }
        precondition(!bar.acceptDrop(at:bar.centerPoint,urls:[sampleURL(.image)]))
        precondition(!bar.acceptDrop(at:bar.center(for:0),urls:[]))
        bar.actions=[.format("pages")];precondition(!bar.acceptDrop(at:bar.center(for:0),urls:[sampleURL(.document)]))
        bar.onDrop=previousDrop
        testMoves()
        let board=NSPasteboard.withUniqueName();board.writeObjects([sampleURL(.image) as NSURL]);precondition(fileURLs(from:board).count==1);board.releaseGlobally()
        precondition(!panel.isVisible)
        for action in Catalog.universal + Catalog.toolDefinitions.map({ WheelAction(id:$0.key,title:$0.value.0,symbol:$0.value.1) }) {
            precondition(!action.arabicTitle.isEmpty && action.displayTitle.contains(" · "))
        }
        for name in ["hover","select","success","failure"] {
            let url=Bundle.main.resourceURL!.appendingPathComponent("sounds/"+name+".wav")
            precondition((NSSound(contentsOf:url,byReference:true)?.duration ?? 0)>0)
        }
    }
    func testMoves() {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Anasing-move-test-"+UUID().uuidString)
        do {
            defer { try? FileManager.default.removeItem(at:root) }
            let source=root.appendingPathComponent("source"),target=root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
            let a=source.appendingPathComponent("a.txt"),b=source.appendingPathComponent("b.txt")
            try Data("A".utf8).write(to:a);try Data("B".utf8).write(to:b)
            try Data("existing".utf8).write(to:target.appendingPathComponent("b.txt"))
            do { try FileMoveTransaction.move([a,b],to:target);preconditionFailure("Collision accepted") } catch { precondition(FileManager.default.fileExists(atPath:a.path)) }
            try FileMoveTransaction.move([a],to:target)
            precondition(!FileManager.default.fileExists(atPath:a.path))
            let movedData=try Data(contentsOf:target.appendingPathComponent("a.txt"));precondition(movedData == Data("A".utf8))
        } catch { preconditionFailure("Move test failed: \(error)") }
    }
    func pipelineTest() {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Anasing-native-pipeline-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let source=directory.appendingPathComponent("test.svg")
            let data=Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"80\"><rect width=\"100\" height=\"80\" fill=\"orange\"/></svg>".utf8)
            try data.write(to:source)
            runner.run(action:.format("png"),urls:[source],parameters:[:]) { outputs,error in
                defer { try? FileManager.default.removeItem(at:directory) }
                guard error == nil,let output=outputs?.first,let outputData=try? Data(contentsOf:output),let image=NSBitmapImageRep(data:outputData),image.pixelsWide==200,image.pixelsHigh==160,(try? Data(contentsOf:source))==data else {
                    fputs("Native pipeline failed: \(error ?? "invalid result")\n",stderr);exit(1)
                }
                print("ANASING_NATIVE_ENGINE_PIPELINE_PASSED");NSApp.terminate(nil)
            }
        } catch { fputs("\(error)\n",stderr);exit(1) }
    }
    func pdfFeedbackTest() {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Anasing-PDF-feedback-"+UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let source=directory.appendingPathComponent("two-pages.pdf")
            let document=PDFDocument()
            for color in [NSColor.systemOrange,NSColor.systemTeal] {
                let image=NSImage(size:NSSize(width:120,height:90),flipped:false) { rect in color.setFill();rect.fill();return true }
                document.insert(PDFPage(image:image)!,at:document.pageCount)
            }
            guard document.write(to:source) else { fatalError("Could not create test PDF") }
            let original=try Data(contentsOf:source)
            runner.run(action:.format("png"),urls:[source],parameters:[:]) { outputs,error in
                defer { try? FileManager.default.removeItem(at:directory) }
                guard error == nil,let outputs,let output=outputs.first else { fputs("PDF conversion failed: \(error ?? "no output")\n",stderr);exit(1) }
                let preview=ActionFeedback.previewFiles(outputs)
                precondition(preview.count==2 && preview.files.count==2)
                precondition(preview.files.allSatisfy { $0.pathExtension=="png" && NSImage(contentsOf:$0) != nil })
                precondition(output.deletingLastPathComponent().resolvingSymlinksInPath()==directory.resolvingSymlinksInPath())
                precondition((try? Data(contentsOf:source))==original)
                let model=ActionFeedback(title:WheelAction.format("png").displayTitle,source:source.lastPathComponent)
                FeedbackCenter.shared.complete(model,outputs:outputs,files:preview.files,count:preview.count)
                precondition(model.state == .success && model.previews.count==2 && !model.outputs.isEmpty)
                print("ANASING_PDF_TO_IMAGES_AND_FEEDBACK_PASSED");NSApp.terminate(nil)
            }
        } catch { fputs("\(error)\n",stderr);exit(1) }
    }
    func renderFeedback(to path:String) {
        let destination=URL(fileURLWithPath:path)
        try? FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let sample=destination.appendingPathComponent("page-001.png")
        let im=NSImage(size:NSSize(width:200,height:150),flipped:false) { rect in NSColor.systemOrange.setFill();rect.fill();return true }
        if let data=im.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) { try? png.write(to:sample) }
        let sample2=destination.appendingPathComponent("page-002.png")
        let im2=NSImage(size:NSSize(width:200,height:150),flipped:false) { rect in NSColor.systemTeal.setFill();rect.fill();return true }
        if let data=im2.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) { try? png.write(to:sample2) }
        for state in [FeedbackState.running,.success,.failed] {
            let model=ActionFeedback(title:WheelAction.format("png").displayTitle,source:"Document.pdf")
            model.state=state
            if state == .success { model.outputs=[destination];model.previews=[sample,sample2];model.details="2 images saved beside Document.pdf\nتم حفظ صورتين بجانب الملف الأصلي." }
            if state == .failed { model.details="The source file could not be opened.\nتعذّر فتح الملف الأصلي." }
            let hosting=NSHostingView(rootView:ActionFeedbackView(model:model))
            let window=NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:200),styleMask:[.borderless],backing:.buffered,defer:false)
            configureGlassWindow(window);window.contentView=hosting;window.setContentSize(hosting.fittingSize);hosting.layoutSubtreeIfNeeded()
            window.setFrameOrigin(NSPoint(x:-10000,y:-10000));window.orderFrontRegardless()
            RunLoop.main.run(until:Date().addingTimeInterval(0.25))
            if let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) { hosting.cacheDisplay(in:hosting.bounds,to:rep);if let data=rep.representation(using:.png,properties:[:]) { try? data.write(to:destination.appendingPathComponent(state.rawValue+".png")) } }
            window.orderOut(nil)
        }
    }
    func renderBars(to path:String) {
        try? FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
        for category in FileCategory.allCases where category != .other {
            for mode in WheelMode.allCases {
                bar.mode=mode;bar.category=category.rawValue;bar.actions=Catalog.actions(mode:mode,urls:[sampleURL(category)]);bar.hovered=bar.actions.isEmpty ? nil:0
                bar.frame=NSRect(origin:.zero,size:bar.preferredSize)
                let rep=bar.bitmapImageRepForCachingDisplay(in:bar.bounds)!
                bar.cacheDisplay(in:bar.bounds,to:rep)
                if let png=rep.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:path).appendingPathComponent(category.rawValue+"-"+mode.rawValue+".png")) }
            }
        }
    }
}
@main struct AnasingApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body:some Scene { Settings { EmptyView() } }
}
