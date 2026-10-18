// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI

func showError(_ message:String) {
    NSApp.activate(ignoringOtherApps:true)
    let alert=NSAlert();alert.addButton(withTitle:"OK · موافق");alert.messageText="Anasing couldn’t finish · تعذّر إكمال الإجراء";alert.informativeText=message;alert.runModal()
}
struct FloatFilesView:View {
    let urls:[URL]
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Keep it close · ملفاتك بالقرب منك").font(.system(size:16,weight:.semibold))
            ForEach(urls,id:\.self) { url in
                HStack { Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:30,height:30);Text(url.lastPathComponent).font(.system(size:12)).lineLimit(1);Spacer();Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(.secondary) }.padding(8).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                .onDrag { NSItemProvider(object:url as NSURL) }.onTapGesture(count:2) { NSWorkspace.shared.open(url) }
            }
            Text("Drag to another app · اسحب لتطبيق آخر\nDouble-click to open · انقر مرتين للفتح").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width:280).foregroundStyle(.white.opacity(0.94)).background(GlassSurface()).preferredColorScheme(.dark)
    }
}
final class FileActions {
    var floats:[NSWindow]=[]
    func perform(_ action:String,urls:[URL]) {
        switch action {
        case "copy": NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects(urls as [NSURL]);toast("Files copied · تم نسخ الملفات")
        case "copyPath": NSPasteboard.general.clearContents();NSPasteboard.general.setString(urls.map(\.path).joined(separator:"\n"),forType:.string);toast("Paths copied · تم نسخ المسارات")
        case "airDrop":
            guard let service=NSSharingService(named:.sendViaAirDrop),service.canPerform(withItems:urls) else { showError("AirDrop is unavailable on this Mac. Enable Wi-Fi and Bluetooth, then try again.");return }
            NSApp.activate(ignoringOtherApps:true);service.perform(withItems:urls);toast("AirDrop opened · تم فتح إيردروب")
        case "terminal":
            guard let first=urls.first,let terminal=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Terminal") else { return }
            var isDirectory:ObjCBool=false;FileManager.default.fileExists(atPath:first.path,isDirectory:&isDirectory)
            let folder=isDirectory.boolValue ? first:first.deletingLastPathComponent()
            NSWorkspace.shared.open([folder],withApplicationAt:terminal,configuration:NSWorkspace.OpenConfiguration()) { _,error in DispatchQueue.main.async { if let error { showError(error.localizedDescription) } else { toast("Terminal opened · تم فتح الطرفية") } } }
        case "float":
            let window=NSPanel(contentRect:NSRect(x:0,y:0,width:316,height:200),styleMask:[.titled,.closable,.utilityWindow],backing:.buffered,defer:false)
            window.title="Anasing · Float";window.isReleasedWhenClosed=false;configureGlassWindow(window);window.level = .floating;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            window.standardWindowButton(.closeButton)?.isHidden=false
            window.contentView=NSHostingView(rootView:FloatFilesView(urls:urls));window.center();window.makeKeyAndOrderFront(nil);floats.append(window)
        case "move": move(urls)
        default: break
        }
    }
    func move(_ urls:[URL]) {
        NSApp.activate(ignoringOtherApps:true)
        let picker=NSOpenPanel();picker.canChooseFiles=false;picker.canChooseDirectories=true;picker.prompt="Move here · نقل إلى هنا";picker.message="Choose where to move the original files. Existing files will not be replaced."
        guard picker.runModal() == .OK,let folder=picker.url else { return }
        do { try FileMoveTransaction.move(urls,to:folder);toast("Moved \(urls.count) file(s) · تم نقل الملفات") }
        catch { showError(error.localizedDescription) }
    }

}

enum FileMoveTransaction {
    static func move(_ urls:[URL],to folder:URL) throws {
        var moves:[(URL,URL)]=[];var destinations=Set<String>()
        for source in urls {
            let target=folder.appendingPathComponent(source.lastPathComponent)
            let canonical=source.resolvingSymlinksInPath().path;let dest=target.resolvingSymlinksInPath().path
            guard !FileManager.default.fileExists(atPath:target.path),!destinations.contains(dest) else { throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:"A file named ‘\(source.lastPathComponent)’ already exists at the destination. Nothing was moved."]) }
            guard !dest.hasPrefix(canonical+"/") else { throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:"A folder cannot be moved inside itself."]) }
            guard !urls.contains(where:{$0 != source && source.path.hasPrefix($0.path+"/")}) else { throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose the parent folder or its children, rather than both."]) }
            destinations.insert(dest);moves.append((source,target))
        }
        var finished:[(URL,URL)]=[]
        do { for (source,target) in moves { try FileManager.default.moveItem(at:source,to:target);finished.append((source,target)) } }
        catch {
            var rollbackErrors:[String]=[]
            for (source,target) in finished.reversed() { do { try FileManager.default.moveItem(at:target,to:source) } catch { rollbackErrors.append(target.path) } }
            if !rollbackErrors.isEmpty { throw NSError(domain:"Anasing",code:2,userInfo:[NSLocalizedDescriptionKey:"Some files moved before an error. These remain at their destination:\n"+rollbackErrors.joined(separator:"\n")]) }
            throw error
        }
    }
}

func toast(_ message:String,outputs:[URL]=[]) {
    FeedbackCenter.shared.notice(message,urls:outputs)
}
final class ConversionJob {
    let id=UUID()
    let lock=NSLock()
    var process:Process?
    var cancelled=false
    func cancel() { lock.lock();cancelled=true;let active=process;lock.unlock();if active?.isRunning == true { active?.terminate() } }
}
final class JobRunner {
    let queue=DispatchQueue(label:"app.anasing.conversion",qos:.userInitiated)
    var activityChanged:((Int)->Void)?
    func finished(_ id:UUID) { jobs.removeValue(forKey:id);activityChanged?(jobs.count) }
    var jobs:[UUID:ConversionJob]=[:]
    func cancelAll() { jobs.values.forEach { $0.cancel() } }
    func run(action:WheelAction,urls:[URL],parameters:[String:Any],completion:(([URL]?,String?)->Void)?=nil) {
        let job=ConversionJob();jobs[job.id]=job
        activityChanged?(jobs.count)
        let feedback:ActionFeedback?
        if completion == nil {
            let model=FeedbackCenter.shared.start(title:action.displayTitle,urls:urls)
            model.cancel={ [weak model] in job.cancel();FeedbackCenter.shared.cancelled(model) }
            feedback=model
        } else { feedback=nil }
        let root=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let bundledPackages=Bundle.main.resourceURL!.appendingPathComponent("runtime/lib/python3.9/site-packages")
        let hasBundledPackages=FileManager.default.fileExists(atPath:bundledPackages.path)
        let portablePython=Bundle.main.resourceURL!.appendingPathComponent("python/bin/python3")
        let portable=FileManager.default.isExecutableFile(atPath:portablePython.path)
        let python=portable ? portablePython:hasBundledPackages ? URL(fileURLWithPath:"/usr/bin/python3"):root.appendingPathComponent(".venv/bin/python3")
        let engine=Bundle.main.resourceURL!.appendingPathComponent("engine/anasing_engine.py")
        let request:[String:Any]=["action":action.id,"sources":urls.map(\.path),"parameters":parameters]
        queue.async {
            var result:[String:Any]=[:]
            do {
                guard FileManager.default.isExecutableFile(atPath:python.path) else { throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:"The local conversion runtime is missing. Run scripts/setup.sh in the Anasing project."]) }
                let process=Process();process.executableURL=python;process.arguments=portable ? ["-B","-I",engine.path]:[engine.path]
                var env=ProcessInfo.processInfo.environment;env["PYTHONUNBUFFERED"]="1"
                if portable {
                    env.removeValue(forKey:"PYTHONPATH");env.removeValue(forKey:"PYTHONHOME");env.removeValue(forKey:"__PYVENV_LAUNCHER__")
                    env["ANASING_BUNDLE_RESOURCES"]=Bundle.main.resourceURL!.path
                    env["PYTHONDONTWRITEBYTECODE"]="1";env["PYTHONNOUSERSITE"]="1"
                } else if hasBundledPackages { env["PYTHONPATH"]=bundledPackages.path;env["PYTHONNOUSERSITE"]="1" }
                process.environment=env
                let input=Pipe(),output=Pipe();process.standardInput=input;process.standardOutput=output
                let errors=FileManager.default.temporaryDirectory.appendingPathComponent("Anasing-\(job.id).log")
                FileManager.default.createFile(atPath:errors.path,contents:nil)
                let log=try FileHandle(forWritingTo:errors);process.standardError=log
                defer { try? log.close();try? FileManager.default.removeItem(at:errors) }
                job.lock.lock()
                if job.cancelled {
                    job.lock.unlock()
                    DispatchQueue.main.async { self.finished(job.id);FeedbackCenter.shared.cancelled(feedback) }
                    return
                }
                job.process=process
                do { try process.run();job.lock.unlock() } catch { job.lock.unlock();throw error }
                DispatchQueue.main.async { FeedbackCenter.shared.running(feedback) }
                let data=try JSONSerialization.data(withJSONObject:request)
                input.fileHandleForWriting.write(data);try? input.fileHandleForWriting.close()
                let response=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
                result=(try? JSONSerialization.jsonObject(with:response)) as? [String:Any] ?? [:]
                if result.isEmpty { let details=(try? String(contentsOf:errors,encoding:.utf8)) ?? "";throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:details.isEmpty ? "The conversion process stopped unexpectedly.":String(details.suffix(2000))]) }
            } catch { result=["ok":false,"error":error.localizedDescription] }
            let outputURLs=(result["outputs"] as? [String] ?? []).map { URL(fileURLWithPath:$0) }
            let preview=ActionFeedback.previewFiles(outputURLs)
            DispatchQueue.main.async {
                self.finished(job.id)
                if job.cancelled { FeedbackCenter.shared.cancelled(feedback);return }
                if result["ok"] as? Bool == true {
                    let outputs=(result["outputs"] as? [String] ?? []).map { URL(fileURLWithPath:$0) }
                    if let completion { completion(outputs,nil) }
                    else {
                        FeedbackCenter.shared.complete(feedback,outputs:outputs,files:preview.files,count:preview.count)
                        if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                    }
                } else {
                    let message=result["error"] as? String ?? "Conversion failed"
                    if let completion { completion(nil,message) } else { FeedbackCenter.shared.failed(feedback,message:message) }
                }
            }
        }
    }
}
