// SPDX-License-Identifier: AGPL-3.0-only
import AppKit

enum WheelMode: String, CaseIterable { case conversions, tools, actions
    var label: String { switch self { case .conversions: return "⇧ Convert · تحويل"; case .tools: return "⌘ Tools · أدوات"; case .actions: return "⌃ Actions · إجراءات" } }
}
enum FileCategory: String, CaseIterable {
    case image, video, audio, pdf, document, slides, spreadsheet, epub, subtitle, archive, other
    static func identify(_ url: URL) -> FileCategory {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue && url.pathExtension != "rtfd" && url.pathExtension != "pages" { return .other }
        let ext = url.pathExtension.lowercased()
        if ["jpg","jpeg","png","webp","heic","heif","tiff","tif","avif","bmp","svg"].contains(ext) { return .image }
        if ["mp4","mov","mkv","webm","avi","wmv","gif","m4v"].contains(ext) { return .video }
        if ["mp3","m4a","wav","flac","ogg","opus","aiff","aif","wma","aac"].contains(ext) { return .audio }
        if ext == "pdf" { return .pdf }
        if ["docx","doc","pages","md","txt","html","htm","rtf","rtfd","textclipping","odt"].contains(ext) { return .document }
        if ["ppt","pptx","odp"].contains(ext) { return .slides }
        if ["xlsx","xls","ods","csv","tsv"].contains(ext) { return .spreadsheet }
        if ext == "epub" { return .epub }
        if ["srt","vtt"].contains(ext) { return .subtitle }
        if ["zip","tar","gz","tgz","rar","bz2","xz"].contains(ext) { return .archive }
        return .other
    }
}
struct WheelAction: Equatable {
    let id: String
    let title: String
    let symbol: String
    var available = true
    var explanation = ""
    static func format(_ name: String) -> WheelAction { .init(id: "convert:" + name, title: name.uppercased(), symbol: "", available: name != "pages", explanation: name == "pages" ? "Pages export requires Apple Pages; choose DOCX instead." : "") }
}
enum Catalog {
    static let universal: [WheelAction] = [
        .init(id:"airDrop", title:"AIRDROP", symbol:"airplayaudio"), .init(id:"float", title:"FLOAT", symbol:"pin"),
        .init(id:"copy", title:"COPY", symbol:"doc.on.doc"), .init(id:"move", title:"MOVE", symbol:"folder"),
        .init(id:"copyPath", title:"COPY PATH", symbol:"doc.text"), .init(id:"terminal", title:"TERMINAL", symbol:"terminal")]
    static let toolDefinitions: [String:(String,String)] = [
        "compress":("COMPRESS","arrow.down.right.and.arrow.up.left"), "metadata":("METADATA","tag"),
        "editImage":("EDIT","slider.horizontal.3"), "annotateImage":("ANNOTATE","pencil.tip.crop.circle"), "frameImage":("ADD BG","photo.artframe"),
        "cropImage":("CROP","crop"), "redactImage":("REDACT","eye.slash"), "createPDF":("CREATE PDF","doc.badge.plus"), "collage":("COLLAGE","rectangle.3.group"),
        "normalizeAudio":("NORMALIZE","waveform"), "visualize":("VISUALIZE","waveform.path"), "trimAudio":("TRIM","scissors"), "channels":("CHANNELS","hifispeaker.2"), "bleep":("BLEEP","waveform.badge.minus"),
        "muteVideo":("MUTE","speaker.slash"), "trimVideo":("TRIM","scissors"), "cropVideo":("CROP","crop"), "speed":("SPEED","speedometer"), "snapshot":("SNAPSHOT","camera"), "splitVideo":("SPLIT","film"), "redactVideo":("REDACT","eye.slash"), "joinVideos":("JOIN","film.stack"),
        "splitPDF":("SPLIT","rectangle.split.2x1"), "organizePDF":("ORGANIZE","square.grid.2x2"), "mergePDF":("MERGE PDF","doc.on.doc"), "extract":("EXTRACT","archivebox")]
    static func actions(mode: WheelMode, urls: [URL]) -> [WheelAction] {
        if mode == .actions { return universal }
        guard let first = urls.first else { return [] }
        let category = FileCategory.identify(first)
        guard urls.allSatisfy({ FileCategory.identify($0) == category }) else { return [] }
        if mode == .conversions {
            let formats: [String]
            switch category {
            case .image: formats = ["png","jpg","webp","heic","tiff","avif","bmp","pdf"]
            case .video: formats = first.pathExtension.lowercased() == "gif" ? ["mp4","mov","mkv","webm","avi","wmv"] : ["mp4","mov","mkv","webm","avi","wmv","gif","mp3"]
            case .audio: formats = ["mp3","m4a","wav","flac","ogg","opus","aiff","wma"]
            case .pdf: formats = ["docx","pages","pptx","xlsx","jpg","png","epub","txt","md"]
            case .document: formats = ["docx","pages","pdf","txt","md","html","epub","png","jpg"]
            case .slides: formats = ["pdf","jpg","png"]
            case .spreadsheet: formats = ["xlsx","ods","csv","tsv","pdf"]
            case .epub: formats = ["pdf","docx","pages","txt","md","html"]
            case .subtitle: formats = ["srt","vtt","txt"]
            case .archive: formats = ["zip","tar","gz"]
            case .other: formats = []
            }
            let raw = first.pathExtension.lowercased()
            let ext = (["jpeg":"jpg", "tif":"tiff", "heif":"heic", "aif":"aiff"][raw] ?? raw)
            return formats.filter { urls.count > 1 || $0 != ext }.map(WheelAction.format)
        }
        let ids: [String]
        switch category {
        case .image: ids = urls.count > 1 ? ["compress","metadata","cropImage","createPDF","collage"] : ["compress","metadata","editImage","annotateImage","frameImage","cropImage","redactImage"]
        case .video: ids = first.pathExtension.lowercased() == "gif" ? ["metadata"] : urls.count > 1 ? ["compress","metadata","muteVideo","trimVideo","cropVideo","speed","joinVideos"] : ["compress","metadata","muteVideo","trimVideo","cropVideo","speed","snapshot","splitVideo","redactVideo"]
        case .audio: ids = ["compress","metadata","normalizeAudio","visualize","trimAudio","channels","bleep"]
        case .pdf: ids = urls.count > 1 ? ["compress","metadata","splitPDF","mergePDF"] : ["compress","metadata","splitPDF","organizePDF"]
        case .archive: ids = ["extract"]
        default: ids = []
        }
        return ids.map { let entry = toolDefinitions[$0]!; return WheelAction(id:$0, title:entry.0, symbol:entry.1) }
    }
}
