// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI
import PDFKit

extension AppDelegate {
    func editorFixtures(at root:URL) throws -> [String:URL] {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let image=NSImage(size:NSSize(width:640,height:400),flipped:false) { rect in
            NSColor.systemTeal.setFill();rect.fill();NSColor.systemOrange.setFill();NSBezierPath(ovalIn:rect.insetBy(dx:140,dy:90)).fill();return true
        }
        let source=root.appendingPathComponent("fixture.png")
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:source)
        let pdf=root.appendingPathComponent("document.pdf"),document=PDFDocument()
        for color in [NSColor.systemTeal,NSColor.systemOrange,NSColor.systemPurple] {
            let pageImage=NSImage(size:NSSize(width:300,height:400),flipped:false) { rect in color.setFill();rect.fill();return true }
            document.insert(PDFPage(image:pageImage)!,at:document.pageCount)
        }
        guard document.write(to:pdf) else { throw NSError(domain:"Anasing",code:1) }
        let video=root.appendingPathComponent("clip.mp4")
        let ffmpeg=Bundle.main.resourceURL!.appendingPathComponent("tools/bin/ffmpeg")
        let process=Process();process.executableURL=FileManager.default.isExecutableFile(atPath:ffmpeg.path) ? ffmpeg:URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
        process.arguments=["-hide_banner","-loglevel","error","-y","-f","lavfi","-i","testsrc2=size=320x240:rate=15:duration=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",video.path]
        try process.run();process.waitUntilExit();precondition(process.terminationStatus==0)
        return ["image":source,"pdf":pdf,"video":video]
    }
    func editorAction(_ id:String)->WheelAction { let entry=Catalog.toolDefinitions[id]!;return WheelAction(id:id,title:entry.0,symbol:entry.1) }
    func renderEditors(to path:String) {
        let destination=URL(fileURLWithPath:path)
        do {
            let fixtures=try editorFixtures(at:destination)
            for id in ["cropImage","redactImage","annotateImage","frameImage","editImage","metadata","compress","trimVideo","redactVideo","snapshot","speed","organizePDF","channels","normalizeAudio","collage"] {
                let type=id=="organizePDF" ? "pdf":["trimVideo","redactVideo","snapshot","speed","channels","normalizeAudio"].contains(id) ? "video":"image"
                let model=EditorModel(action:editorAction(id),source:fixtures[type]!)
                if id=="annotateImage" { model.values["text"]="Hello · مرحباً" }
                let hosting=NSHostingView(rootView:OperationEditor(model:model) { _ in })
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:586,height:500),styleMask:[.titled],backing:.buffered,defer:false)
                configureGlassWindow(window);window.contentView=hosting;window.setContentSize(hosting.fittingSize);hosting.layoutSubtreeIfNeeded()
                window.setFrameOrigin(NSPoint(x:-10000,y:-10000));window.orderFrontRegardless()
                RunLoop.main.run(until:Date().addingTimeInterval(0.3))
                if let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) { hosting.cacheDisplay(in:hosting.bounds,to:rep);if let png=rep.representation(using:.png,properties:[:]) { try png.write(to:destination.appendingPathComponent(id+".png")) } }
                window.orderOut(nil)
            }
        } catch { fputs("Editor render failed: \(error)\n",stderr);exit(1) }
    }
    func editorTest() {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Anasing-editors-"+UUID().uuidString)
        do {
            let fixtures=try editorFixtures(at:root)
            let image=EditorModel(action:editorAction("editImage"),source:fixtures["image"]!)
            precondition(image.fields.allSatisfy { if case .slider=$0.control { return true };return false })
            image.numericBinding("brightness").wrappedValue=0.5;image.numericBinding("rotation").wrappedValue=90
            precondition(image.parameters["brightness"] as? Double==0.5 && image.parameters["rotation"] as? Double==90)
            let annotation=EditorModel(action:editorAction("annotateImage"),source:fixtures["image"]!)
            precondition(annotation.validation != nil);annotation.update("text","Hello");annotation.update("color","#2785FF");precondition(annotation.validation==nil && annotation.parameters["text"] as? String=="Hello")
            let pdf=EditorModel(action:editorAction("organizePDF"),source:fixtures["pdf"]!)
            precondition(pdf.pageOrder==[1,2,3]);pdf.togglePage(2);pdf.movePage(3,by:-1);pdf.update("rotation","90")
            precondition(pdf.parameters["pages"] as? String=="3,1" && pdf.parameters["rotation"] as? Double==90)
            pdf.pageOrder=[];precondition(pdf.validation != nil);pdf.reset();precondition(pdf.pageOrder==[1,2,3])
            pdf.pageOrder=[3,1];pdf.update("rotation","90")
            let trim=EditorModel(action:editorAction("trimVideo"),source:fixtures["video"]!)
            precondition(trim.duration>1.9 && trim.duration<2.2 && trim.validation==nil)
            trim.rangeBinding("start").wrappedValue=100;precondition(trim.number("start")<trim.number("end"))
            trim.rangeBinding("start").wrappedValue=0.4;trim.rangeBinding("end").wrappedValue=0.9
            precondition(trim.parameters["start"] as? Double==0.4 && trim.parameters["end"] as? Double==0.9)
            let snapshot=EditorModel(action:editorAction("snapshot"),source:fixtures["video"]!);snapshot.snapshots=[1.25,0.5]
            precondition(snapshot.parameters["times"] as? String=="0.5,1.25")
            for id in ["compress","frameImage","speed","snapshot","splitVideo","normalizeAudio","channels","collage"] {
                let model=EditorModel(action:editorAction(id),source:fixtures[id=="compress" || id=="collage" || id=="frameImage" ? "image":"video"]!)
                precondition(model.fields.allSatisfy { if case .text=$0.control { return false };return true })
            }
            runner.run(action:editorAction("editImage"),urls:[fixtures["image"]!],parameters:image.parameters) { outputs,error in
                guard error==nil,let output=outputs?.first,let data=try? Data(contentsOf:output),let bitmap=NSBitmapImageRep(data:data),bitmap.pixelsWide==400,bitmap.pixelsHigh==640 else { fputs("Editor image output failed: \(error ?? "wrong dimensions")\n",stderr);exit(1) }
                self.runner.run(action:self.editorAction("organizePDF"),urls:[fixtures["pdf"]!],parameters:pdf.parameters) { outputs,error in
                    guard error==nil,let output=outputs?.first,let document=PDFDocument(url:output),document.pageCount==2,document.page(at:0)?.rotation==90 else { fputs("Editor PDF output failed\n",stderr);exit(1) }
                    self.runner.run(action:self.editorAction("trimVideo"),urls:[fixtures["video"]!],parameters:trim.parameters) { outputs,error in
                        defer { try? FileManager.default.removeItem(at:root) }
                        guard error==nil,let output=outputs?.first else { fputs("Editor timeline output failed\n",stderr);exit(1) }
                        let check=EditorModel(action:self.editorAction("trimVideo"),source:output)
                        precondition(check.duration>=0.45 && check.duration<=0.65)
                        print("ANASING_TYPED_EDITORS_AND_OUTPUTS_PASSED");NSApp.terminate(nil)
                    }
                }
            }
        } catch { fputs("Editor checks failed: \(error)\n",stderr);exit(1) }
    }
}
