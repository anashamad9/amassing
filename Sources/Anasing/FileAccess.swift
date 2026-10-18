// SPDX-License-Identifier: AGPL-3.0-only
import AppKit

final class SecurityScopeLease {
    private let urls:[URL]
    init(_ locations:[URL]) { urls=locations.filter { $0.startAccessingSecurityScopedResource() } }
    deinit { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
}

/// Folder grants are shared by all actions and restored on subsequent launches.
final class FileAccess {
    static let shared=FileAccess()
    private let defaults:UserDefaults
    private let key="approvedFolderBookmarks"
    private var active:[String:(url:URL,scoped:Bool)]=[:]
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        var refreshed:[Data]=[]
        for data in defaults.array(forKey:key) as? [Data] ?? [] {
            var stale=false
            guard let url=try? URL(resolvingBookmarkData:data,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale) else { continue }
            activate(url)
            refreshed.append(stale ? ((try? bookmark(url)) ?? data):data)
        }
        defaults.set(refreshed,forKey:key)
    }
    deinit { for item in active.values where item.scoped { item.url.stopAccessingSecurityScopedResource() } }
    private func bookmark(_ url:URL) throws -> Data { try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil) }
    func activate(_ url:URL) {
        let path=url.standardizedFileURL.path
        guard active[path]==nil else { return }
        active[path]=(url,url.startAccessingSecurityScopedResource())
    }
    func remember(_ folder:URL) throws {
        activate(folder)
        let data=try bookmark(folder)
        var stored=defaults.array(forKey:key) as? [Data] ?? []
        stored.removeAll { existing in
            var stale=false
            return (try? URL(resolvingBookmarkData:existing,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale).standardizedFileURL.path)==folder.standardizedFileURL.path
        }
        stored.append(data);defaults.set(stored,forKey:key)
    }
    @discardableResult func chooseFolders(suggested:URL?=nil,required:URL?=nil)->Bool {
        precondition(Thread.isMainThread)
        NSApp.activate(ignoringOtherApps:true)
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=required==nil
        panel.title="Remember folder access · حفظ صلاحية المجلد"
        panel.prompt="Allow access · السماح"
        panel.message="Choose a folder once. Anasing remembers it for all file actions, including new copies saved beside originals.\nاختر المجلد مرة واحدة لحفظ الصلاحية لجميع الإجراءات والنسخ الجديدة."
        panel.directoryURL=suggested
        guard panel.runModal() == .OK else { return false }
        if let required,!panel.urls.contains(where:{ Self.contains(folder:$0,url:required) }) {
            showError("Choose the source folder or a parent folder that contains it.\nاختر مجلد الملف الأصلي أو مجلداً يحتويه.");return false
        }
        do { for folder in panel.urls { try remember(folder) };return true }
        catch { showError("Could not save folder access · تعذّر حفظ صلاحية المجلد\n"+error.localizedDescription);return false }
    }
    static func contains(folder:URL,url:URL)->Bool {
        let parent=folder.standardizedFileURL.path,child=url.standardizedFileURL.path
        return child==parent || parent=="/" || child.hasPrefix(parent+"/")
    }
    /// Actual reads/writes catch TCC denials that isReadableFile/isWritableFile can miss.
    static func check(_ url:URL,writeBeside:Bool) throws {
        let manager=FileManager.default
        let directory=(try url.resourceValues(forKeys:[.isDirectoryKey])).isDirectory ?? false
        if directory { _=try manager.contentsOfDirectory(at:url,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles]) }
        else { let handle=try FileHandle(forReadingFrom:url);defer { try? handle.close() };_=try handle.read(upToCount:1) }
        if writeBeside {
            let folder=url.deletingLastPathComponent()
            let probe=folder.appendingPathComponent(".anasing-access-"+UUID().uuidString)
            try Data().write(to:probe,options:.withoutOverwriting)
            try manager.removeItem(at:probe)
        }
    }
    @discardableResult func prepare(_ urls:[URL],writeBeside:Bool)->Bool {
        precondition(Thread.isMainThread)
        let lease=SecurityScopeLease(urls);defer { withExtendedLifetime(lease) {} }
        for url in urls {
            do { try Self.check(url,writeBeside:writeBeside) }
            catch {
                guard Self.isPermissionError(error) else { showError(error.localizedDescription);return false }
                let folder=url.deletingLastPathComponent()
                guard chooseFolders(suggested:folder,required:folder) else { return false }
                do { try Self.check(url,writeBeside:writeBeside) }
                catch { showError("macOS still denied access. Check Anasing under System Settings → Privacy & Security → Files and Folders.\nما زال macOS يمنع الوصول. راجع صلاحيات أناسينغ في إعدادات الخصوصية.\n"+error.localizedDescription);return false }
            }
        }
        return true
    }
    static func isPermissionError(_ error:Error)->Bool {
        let value=error as NSError
        if value.domain==NSPOSIXErrorDomain && [Int(EPERM),Int(EACCES)].contains(value.code) { return true }
        if value.domain==NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(value.code) { return true }
        return (value.userInfo[NSUnderlyingErrorKey] as? Error).map(isPermissionError) ?? false
    }
}

struct StagedPublishError:Error {
    let cause:Error
    let completed:[URL]
}
/// Only the native app touches user folders. Python/FFmpeg/Office receive private temporary copies.
final class StagedOperation {
    let root:URL
    let stagedSources:[URL]
    private let sourceParents:[String:URL]
    private let manager=FileManager.default
    init(sources:[URL],cancelled:()->Bool = {false}) throws {
        let manager=FileManager.default
        root=manager.temporaryDirectory.appendingPathComponent("Anasing-job-"+UUID().uuidString,isDirectory:true)
        try manager.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var staged:[URL]=[],parents:[String:URL]=[:]
        do {
            for (index,source) in sources.enumerated() {
                if cancelled() { throw CancellationError() }
                let parent=root.appendingPathComponent(String(index),isDirectory:true)
                try manager.createDirectory(at:parent,withIntermediateDirectories:false)
                let copy=parent.appendingPathComponent(source.lastPathComponent)
                try manager.copyItem(at:source.resolvingSymlinksInPath(),to:copy)
                staged.append(copy);parents[parent.resolvingSymlinksInPath().standardizedFileURL.path]=source.deletingLastPathComponent()
            }
        } catch { try? manager.removeItem(at:root);throw error }
        stagedSources=staged;sourceParents=parents
    }
    deinit { try? manager.removeItem(at:root) }
    func publish(_ outputs:[URL],cancelled:()->Bool = {false})->Result<[URL],StagedPublishError> {
        var completed:[URL]=[]
        do {
            for output in outputs {
                if cancelled() { throw CancellationError() }
                let parentPath=output.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
                guard let destinationFolder=sourceParents[parentPath],output.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else {
                    throw NSError(domain:"Anasing",code:1,userInfo:[NSLocalizedDescriptionKey:"The conversion returned an unexpected output path."])
                }
                let staged=destinationFolder.appendingPathComponent(".anasing-save-"+UUID().uuidString)
                defer { try? manager.removeItem(at:staged) }
                try manager.copyItem(at:output,to:staged)
                if cancelled() { throw CancellationError() }
                var candidate=destinationFolder.appendingPathComponent(output.lastPathComponent),index=2
                while true {
                    do { try manager.moveItem(at:staged,to:candidate);completed.append(candidate);break }
                    catch {
                        guard (error as NSError).domain==NSCocoaErrorDomain && (error as NSError).code==NSFileWriteFileExistsError else { throw error }
                        let directory=(try? output.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false
                        let ext=directory ? "":output.lastPathComponent.hasSuffix(".tar.gz") ? "tar.gz":output.pathExtension
                        let stem=ext.isEmpty ? output.lastPathComponent:String(output.lastPathComponent.dropLast(ext.count+1))
                        candidate=destinationFolder.appendingPathComponent(stem+" "+String(index)+(ext.isEmpty ? "":"."+ext));index+=1
                    }
                }
            }
            return .success(completed)
        } catch { return .failure(StagedPublishError(cause:error,completed:completed)) }
    }
}
extension AppDelegate {
    @objc func allowFolderAccess() { _=FileAccess.shared.chooseFolders() }
}
