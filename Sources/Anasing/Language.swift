// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI

func bilingual(_ english:String,_ arabic:String)->String { english+" · "+arabic }

extension WheelAction {
    var arabicTitle:String {
        if id.hasPrefix("convert:") {
            let format=String(id.dropFirst(8))
            if ["png","jpg","webp","heic","tiff","avif","bmp"].contains(format) { return "صورة" }
            if ["mp4","mov","mkv","webm","avi","wmv"].contains(format) { return "فيديو" }
            if ["mp3","m4a","wav","flac","ogg","opus","aiff","wma"].contains(format) { return "صوت" }
            return ["pdf":"مستند","docx":"مستند","pages":"مستند","pptx":"شرائح","xlsx":"جدول","ods":"جدول","csv":"بيانات","tsv":"بيانات","txt":"نص","md":"ماركداون","html":"ويب","epub":"كتاب","srt":"ترجمة","vtt":"ترجمة","zip":"أرشيف","tar":"أرشيف","gz":"أرشيف","gif":"متحركة"][format] ?? format
        }
        return ["airDrop":"إيردروب","float":"تعليق","copy":"نسخ","move":"نقل","copyPath":"نسخ المسار","terminal":"الطرفية","compress":"ضغط","metadata":"بيانات","editImage":"تعديل","annotateImage":"تعليق نصي","frameImage":"خلفية","cropImage":"اقتصاص","redactImage":"حجب","createPDF":"إنشاء PDF","collage":"تجميع","normalizeAudio":"موازنة","visualize":"موجة مرئية","trimAudio":"قص","channels":"قنوات","bleep":"كتم جزئي","muteVideo":"كتم الصوت","trimVideo":"قص","cropVideo":"اقتصاص","speed":"السرعة","snapshot":"لقطة","splitVideo":"تقسيم","redactVideo":"حجب","joinVideos":"دمج","splitPDF":"تقسيم","organizePDF":"ترتيب","mergePDF":"دمج PDF","extract":"استخراج"][id] ?? ""
    }
    var displayTitle:String {
        let english=id.hasPrefix("convert:") ? "Convert to "+title:title.capitalized
        let arabic=id.hasPrefix("convert:") ? "تحويل إلى "+title:arabicTitle
        return bilingual(english,arabic)
    }
}
extension EditorField {
    var arabicLabel:String {
        let labels:[String:String]=["quality":"الجودة","width":"أقصى عرض بالبكسل","crf":"جودة الفيديو · القيمة الأعلى تعني حجماً أصغر","bitrate":"معدل الصوت · كيلوبت بالثانية","title":"العنوان","author":"المؤلف","artist":"الفنان","album":"الألبوم","subject":"الموضوع","comment":"تعليق","brightness":"الإضاءة · ١ دون تغيير","contrast":"التباين · ١ دون تغيير","saturation":"التشبع · ١ دون تغيير","sharpness":"الحدة · ١ دون تغيير","rotation":"الدوران مع عقارب الساعة بالدرجات","text":"نص التعليق","fontSize":"حجم الخط بالبكسل","color":"اللون","margin":"الهوامش بالبكسل","radius":"استدارة الزوايا بالبكسل","start":"وقت البداية بالثواني","end":"وقت النهاية بالثواني","speed":"السرعة · ٠٫٥ أبطأ، ٢ ضعف السرعة","times":"مواضع اللقطات","seconds":"عدد الثواني لكل مقطع","loudness":"مستوى الصوت المستهدف LUFS","channels":"القنوات · ١ أحادي، ٢ ستيريو","columns":"عدد الأعمدة","cell":"حجم كل مربع بالبكسل","pages":"اختيار وترتيب الصفحات"]
        return labels[key] ?? ""
    }
}

struct BilingualCaption:View {
    let english:String
    let arabic:String
    var body:some View {
        VStack(alignment:.leading,spacing:3) {
            Text(english)
            Text(arabic).environment(\.layoutDirection,.rightToLeft)
        }
    }
}

enum ActionSound {
    private static var cache:[String:NSSound]=[:]
    private static var lastHover=Date.distantPast
    static var muted:Bool {
        UserDefaults.standard.bool(forKey:"muteSounds") || ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--") && $0 != "--sound-test"})
    }
    static func play(_ name:String,volume:Float=0.9) {
        guard !muted else { return }
        if name=="hover" {
            guard Date().timeIntervalSince(lastHover)>0.07 else { return };lastHover=Date()
        }
        if cache[name]==nil,let url=Bundle.main.resourceURL?.appendingPathComponent("sounds/"+name+".wav") { cache[name]=NSSound(contentsOf:url,byReference:true) }
        guard let sound=cache[name] else { return }
        sound.stop();sound.currentTime=0;sound.volume=volume;sound.play()
    }
}

extension FileCategory {
    var arabicName:String { [.image:"صور",.video:"فيديو",.audio:"صوت",.pdf:"PDF",.document:"مستندات",.slides:"شرائح",.spreadsheet:"جداول",.epub:"كتب",.subtitle:"ترجمة",.archive:"أرشيف",.other:"ملفات"][self]! }
}
