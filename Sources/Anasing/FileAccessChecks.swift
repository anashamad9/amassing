// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import PDFKit

extension AppDelegate {
    func fileAccessChecks() {
        let manager=FileManager.default
        let root=manager.temporaryDirectory.appendingPathComponent("Anasing-access-checks-"+UUID().uuidString)
        do {
            try manager.createDirectory(at:root,withIntermediateDirectories:true)
            defer { try? manager.removeItem(at:root) }
            let a=root.appendingPathComponent("A"),b=root.appendingPathComponent("B")
            try manager.createDirectory(at:a,withIntermediateDirectories:true);try manager.createDirectory(at:b,withIntermediateDirectories:true)
            let first=a.appendingPathComponent("same.txt"),second=b.appendingPathComponent("same.txt")
            try Data("original A".utf8).write(to:first);try Data("original B".utf8).write(to:second)
            try FileAccess.check(first,writeBeside:true)
            precondition(FileAccess.contains(folder:a,url:first) && !FileAccess.contains(folder:a,url:b))
            precondition(!FileAccess.contains(folder:a,url:root.appendingPathComponent("A-other/file")))
            precondition(FileAccess.isPermissionError(NSError(domain:NSPOSIXErrorDomain,code:Int(EPERM))))
            precondition(FileAccess.isPermissionError(NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError)))
            precondition(!FileAccess.isPermissionError(NSError(domain:NSCocoaErrorDomain,code:NSFileNoSuchFileError)))
            let suite="app.anasing.permission-tests."+UUID().uuidString
            let defaults=UserDefaults(suiteName:suite)!
            defer { defaults.removePersistentDomain(forName:suite) }
            do { let store=FileAccess(defaults:defaults);try store.remember(a);try store.remember(a) }
            precondition((defaults.array(forKey:"approvedFolderBookmarks") as? [Data])?.count==1)
            do { _=FileAccess(defaults:defaults) }
            var stagedRoot:URL!
            do {
                let workspace=try StagedOperation(sources:[first,second]);stagedRoot=workspace.root
                precondition(workspace.stagedSources[0] != workspace.stagedSources[1])
                for source in workspace.stagedSources { precondition(source.path.hasPrefix(workspace.root.path+"/")) }
                let outputs=workspace.stagedSources.map { $0.deletingLastPathComponent().appendingPathComponent("same — Edited.txt") }
                try Data("new A".utf8).write(to:outputs[0]);try Data("new B".utf8).write(to:outputs[1])
                let existing=a.appendingPathComponent("same — Edited.txt");try Data("existing".utf8).write(to:existing)
                let published=try workspace.publish(outputs).get()
                precondition(published[0]==a.appendingPathComponent("same — Edited 2.txt") && published[1]==b.appendingPathComponent("same — Edited.txt"))
                precondition((try? Data(contentsOf:existing))==Data("existing".utf8))
                precondition((try? Data(contentsOf:first))==Data("original A".utf8))
                let folder=workspace.stagedSources[0].deletingLastPathComponent().appendingPathComponent("report.v1 — Pages")
                try manager.createDirectory(at:folder,withIntermediateDirectories:false)
                try Data("page".utf8).write(to:folder.appendingPathComponent("001.txt"))
                _=try workspace.publish([folder]).get()
                let repeated=try workspace.publish([folder]).get();precondition(repeated[0].lastPathComponent=="report.v1 — Pages 2")
                let escaped=root.appendingPathComponent("escape.txt");try Data().write(to:escaped)
                if case .success=workspace.publish([escaped]) { preconditionFailure("Accepted output outside private workspace") }
                if case .success=workspace.publish(outputs,cancelled:{true}) { preconditionFailure("Published cancelled result") }
                let missing=root.appendingPathComponent("missing")
                let deniedSource=missing.appendingPathComponent("input.txt")
                try manager.createDirectory(at:missing,withIntermediateDirectories:false);try Data().write(to:deniedSource)
                let partial=try StagedOperation(sources:[first,deniedSource])
                let one=partial.stagedSources[0].deletingLastPathComponent().appendingPathComponent("partial.txt")
                let two=partial.stagedSources[1].deletingLastPathComponent().appendingPathComponent("partial.txt")
                try Data("one".utf8).write(to:one);try Data("two".utf8).write(to:two);try manager.removeItem(at:missing)
                if case .failure(let error)=partial.publish([one,two]) { precondition(error.completed.count==1 && manager.fileExists(atPath:error.completed[0].path)) }
                else { preconditionFailure("Missing destination accepted") }
            }
            precondition(!manager.fileExists(atPath:stagedRoot.path))
            let remaining=try manager.contentsOfDirectory(atPath:a.path)
            precondition(remaining.allSatisfy {!$0.hasPrefix(".anasing-")})
            print("ANASING_FOLDER_GRANTS_STAGING_AND_SAFE_SAVE_PASSED")
        } catch { fputs("File access checks failed: \(error)\n",stderr);exit(1) }
    }
    /// This can be launched via Finder/LaunchServices to exercise real Downloads TCC attribution.
    func folderPipelineTest(at root:URL) {
        let manager=FileManager.default
        do {
            try manager.createDirectory(at:root,withIntermediateDirectories:true)
            let a=root.appendingPathComponent("source A"),b=root.appendingPathComponent("source B")
            try manager.createDirectory(at:a,withIntermediateDirectories:true);try manager.createDirectory(at:b,withIntermediateDirectories:true)
            let first=a.appendingPathComponent("photo.png"),second=b.appendingPathComponent("photo.png")
            let image=NSImage(size:NSSize(width:180,height:120),flipped:false) { rect in NSColor.systemOrange.setFill();rect.fill();return true }
            let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
            try data.write(to:first);try data.write(to:second)
            guard FileAccess.shared.prepare([first,second],writeBeside:true) else { fputs("Folder permission not granted\n",stderr);exit(1) }
            let collision=a.appendingPathComponent("photo — JPG.jpg");try Data("keep this existing file".utf8).write(to:collision)
            runner.run(action:.format("jpg"),urls:[first,second],parameters:[:]) { outputs,error in
                guard error==nil,let outputs,outputs.count==2 else { fputs("Protected folder conversion failed: \(error ?? "missing output")\n",stderr);exit(1) }
                let report:[String:Any]=["outputs":outputs.map(\.path),"parents":outputs.map {$0.deletingLastPathComponent().resolvingSymlinksInPath().path},"expectedParents":[a,b].map {$0.resolvingSymlinksInPath().path},"sourceUnchanged":(try? Data(contentsOf:first))==data,"collisionUnchanged":(try? Data(contentsOf:collision))==Data("keep this existing file".utf8),"readableOutputs":outputs.allSatisfy { NSImage(contentsOf:$0) != nil }]
                try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:root.appendingPathComponent("batch-report.json"))
                precondition(outputs[0].lastPathComponent=="photo — JPG 2.jpg")
                precondition(outputs.map {$0.deletingLastPathComponent().resolvingSymlinksInPath().path}==[a,b].map {$0.resolvingSymlinksInPath().path})
                precondition((try? Data(contentsOf:first))==data && (try? Data(contentsOf:collision))==Data("keep this existing file".utf8))
                precondition(outputs.allSatisfy { NSImage(contentsOf:$0) != nil })
                self.runner.run(action:WheelAction(id:"createPDF",title:"PDF",symbol:""),urls:[first,second],parameters:[:]) { outputs,error in
                    guard error==nil,let output=outputs?.first,let document=PDFDocument(url:output),document.pageCount==2 else { fputs("Protected folder combine failed\n",stderr);exit(1) }
                    precondition(output.deletingLastPathComponent().resolvingSymlinksInPath().path==a.resolvingSymlinksInPath().path)
                    try? Data("ANASING_PROTECTED_FOLDER_BATCH_AND_COMBINED_OUTPUTS_PASSED".utf8).write(to:root.appendingPathComponent("PASSED.txt"))
                    print("ANASING_PROTECTED_FOLDER_BATCH_AND_COMBINED_OUTPUTS_PASSED");NSApp.terminate(nil)
                }
            }
        } catch { fputs("Protected folder check failed: \(error)\n",stderr);exit(1) }
    }
}
