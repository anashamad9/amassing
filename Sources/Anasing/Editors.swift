// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI
import AVKit
import PDFKit
import CoreImage

// Only free-form content uses a text field. Numeric and finite choices have typed controls.
enum FieldControl {
    case text
    case slider(Double,Double,Double,String)
    case choice([(String,String)])
    case color
    case timeline
    case snapshots
    case pages
}
struct EditorField:Identifiable {
    let key:String
    let label:String
    let initial:String
    var control:FieldControl = .text
    var id:String { key }
}
struct PageItem:Identifiable {
    let id:Int
    let image:NSImage
}
final class EditorModel:ObservableObject {
    @Published var values:[String:String]=[:]
    @Published var region:[Double]=[0.1,0.1,0.8,0.8]
    @Published var setMetadata=false
    @Published var original=false
    @Published var renderedPreview:NSImage?
    @Published var position:Double=0
    @Published var snapshots:[Double]=[0]
    @Published var pageOrder:[Int]=[]
    @Published var playing=false
    let fields:[EditorField]
    let action:WheelAction
    let source:URL
    @Published var preview:NSImage?
    let duration:Double
    let player:AVPlayer?
    let pages:[PageItem]
    private var observer:Any?
    private var frameGenerator:AVAssetImageGenerator?
    private var previewInput:CIImage?
    private var frameGeneration=0
    private var pendingPreview:DispatchWorkItem?
    private let previewQueue=DispatchQueue(label:"app.anasing.preview",qos:.userInitiated)
    private var previewGeneration=0
    var needsRegion:Bool { ["cropImage","redactImage","annotateImage","cropVideo","redactVideo"].contains(action.id) }
    var hasTimeline:Bool { fields.contains { if case .timeline=$0.control { return true };return false } }
    init(action:WheelAction,source:URL) {
        self.action=action;self.source=source
        let category=FileCategory.identify(source)
        var fields:[EditorField]=[]
        func field(_ key:String,_ label:String,_ value:String,_ control:FieldControl = .text) { fields.append(.init(key:key,label:label,initial:value,control:control)) }
        switch action.id {
        case "compress":
            if category == .image || category == .pdf { field("quality","Quality","75",.slider(10,95,1,"%")) }
            if category == .image || category == .video { field("width","Maximum width",category == .video ? "1280":"1920",.choice([("640","640 px"),("1280","1280 px"),("1920","1920 px"),("2560","2560 px"),("3840","3840 px"),("20000","Original · الأصلي")])) }
            if category == .video { field("crf","Video compression","28",.slider(18,40,1,"CRF")) }
            if category == .audio || category == .video { field("bitrate","Audio quality","128",.choice([("64","64 kbps"),("96","96 kbps"),("128","128 kbps"),("192","192 kbps"),("256","256 kbps"),("320","320 kbps")])) }
        case "metadata":
            field("title","Title","");field("author","Author","")
            if category == .audio || category == .video { field("artist","Artist","");field("album","Album","") }
            if category == .pdf { field("subject","Subject","") } else { field("comment","Comment","") }
        case "editImage":
            for (key,label) in [("brightness","Brightness"),("contrast","Contrast"),("saturation","Saturation"),("sharpness","Sharpness")] { field(key,label,"1",.slider(0,4,0.05,"×")) }
            field("rotation","Clockwise rotation","0",.slider(-180,180,1,"°"))
        case "annotateImage":
            field("text","Annotation text","");field("fontSize","Font size","36",.slider(6,300,1,"px"));field("color","Text and outline color","#FF5500",.color)
        case "frameImage":
            field("margin","Background padding","40",.slider(0,500,1,"px"));field("radius","Corner radius","20",.slider(0,500,1,"px"));field("color","Background color","#FFFFFF",.color)
        case "redactImage": field("color","Solid cover color","#000000",.color)
        case "trimVideo","trimAudio","redactVideo","bleep":
            field("start","Time range","0",.timeline);field("end","End","10",.timeline)
        case "speed": field("speed","Playback speed","2",.choice([("0.25","0.25×"),("0.5","0.5×"),("0.75","0.75×"),("1","1×"),("1.25","1.25×"),("1.5","1.5×"),("2","2×"),("4","4×")]))
        case "snapshot": field("times","Snapshot positions","0",.snapshots)
        case "splitVideo": field("seconds","Length of each clip","30",.slider(1,300,1,"s"))
        case "normalizeAudio": field("loudness","Target loudness","-16",.choice([("-23","Broadcast · بث (−23 LUFS)"),("-16","Podcast · بودكاست (−16 LUFS)"),("-14","Streaming · بث رقمي (−14 LUFS)"),("-9","Louder · أعلى (−9 LUFS)")]))
        case "channels": field("channels","Audio channels","1",.choice([("1","Mono · أحادي"),("2","Stereo · ستيريو")]))
        case "collage":
            field("columns","Columns","2",.slider(1,8,1,""));field("cell","Size of each square","600",.choice([("300","300 px"),("600","600 px"),("1000","1000 px"),("1600","1600 px")]))
            field("margin","Spacing","20",.slider(0,200,1,"px"));field("color","Background color","#FFFFFF",.color)
        case "organizePDF":
            field("pages","Choose and reorder pages","",.pages);field("rotation","Rotate selected pages","0",.choice([("0","0°"),("90","90°"),("180","180°"),("270","270°")]))
        default: break
        }
        self.fields=fields
        self.values=Dictionary(uniqueKeysWithValues:fields.map { ($0.key,$0.initial) })
        let media=category == .video || category == .audio
        let asset=media ? AVURLAsset(url:source):nil
        let seconds=asset.map { CMTimeGetSeconds($0.duration) } ?? 0
        self.duration=seconds.isFinite && seconds>0 ? seconds:0
        self.player=media ? AVPlayer(url:source):nil
        if category == .image { self.preview=NSImage(contentsOf:source) }
        else if category == .video,let asset {
            let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true;generator.maximumSize=NSSize(width:1000,height:700)
            self.preview=(try? generator.copyCGImage(at:.zero,actualTime:nil)).map { NSImage(cgImage:$0,size:.zero) }
        } else { self.preview=nil }
        if action.id == "organizePDF",let document=PDFDocument(url:source) {
            self.pages=(0..<document.pageCount).compactMap { i in document.page(at:i).map { PageItem(id:i+1,image:$0.thumbnail(of:NSSize(width:100,height:130),for:.cropBox)) } }
            self.pageOrder=pages.map(\.id)
        } else { self.pages=[] }
        if hasTimeline,duration>0 { values["end"]=String(min(10,duration)) }
        self.renderedPreview=preview
        if action.id=="editImage",let data=preview?.tiffRepresentation { previewInput=CIImage(data:data) }
        if needsRegion,category == .video,let asset {
            let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true;generator.maximumSize=NSSize(width:1000,height:700);frameGenerator=generator
        }
        observer=player?.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { [weak self] time in
            guard let self else { return }
            let seconds=CMTimeGetSeconds(time)
            if seconds.isFinite { self.position=max(0,min(self.duration,seconds)) }
            if self.hasTimeline,self.playing,seconds>=self.number("end") { self.pause();self.seek(self.number("start")) }
            if seconds>=self.duration { self.pause() }
        }
    }
    deinit { pendingPreview?.cancel();player?.pause();if let observer { player?.removeTimeObserver(observer) } }
    func number(_ key:String)->Double { Double(values[key] ?? "") ?? 0 }
    func update(_ key:String,_ value:String) { values[key]=value;schedulePreview() }
    func binding(_ key:String)->Binding<String> { Binding(get:{self.values[key] ?? ""},set:{self.update(key,$0)}) }
    func numericBinding(_ key:String)->Binding<Double> { Binding(get:{self.number(key)},set:{self.update(key,String($0))}) }
    func rangeBinding(_ key:String)->Binding<Double> {
        Binding(get:{self.number(key)},set:{ value in
            let gap=min(0.05,self.duration/2)
            let bounded=key=="start" ? min(max(0,value),self.number("end")-gap):max(min(self.duration,value),self.number("start")+gap)
            self.values[key]=String(bounded);self.pause();self.seek(bounded)
        })
    }
    func seek(_ time:Double) {
        position=max(0,min(duration,time));let target=CMTime(seconds:position,preferredTimescale:600)
        player?.seek(to:target,toleranceBefore:.zero,toleranceAfter:.zero)
        guard let generator=frameGenerator else { return }
        frameGeneration+=1;let generation=frameGeneration;generator.cancelAllCGImageGeneration()
        generator.generateCGImagesAsynchronously(forTimes:[NSValue(time:target)]) { [weak self] _,cg,_,_,_ in
            guard let cg else { return };DispatchQueue.main.async { [weak self] in
                guard let self,self.frameGeneration==generation else { return };self.preview=NSImage(cgImage:cg,size:.zero)
            }
        }
    }
    func pause() { player?.pause();playing=false }
    func togglePlayback() {
        if playing { pause();return }
        if hasTimeline && (position<number("start") || position>=number("end")) { seek(number("start")) }
        else if position>=duration { seek(0) }
        player?.playImmediately(atRate:action.id=="speed" ? Float(number("speed")):1);playing=true
    }
    func togglePage(_ page:Int) { if pageOrder.contains(page) { pageOrder.removeAll {$0==page} } else { pageOrder.append(page) } }
    func movePage(_ page:Int,by offset:Int) {
        guard let index=pageOrder.firstIndex(of:page),pageOrder.indices.contains(index+offset) else { return };pageOrder.swapAt(index,index+offset)
    }
    var validation:String? {
        if action.id=="organizePDF" && pageOrder.isEmpty { return "Select at least one page · اختر صفحة واحدة على الأقل" }
        if action.id=="annotateImage" && (values["text"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return "Add your annotation text · أضف نص التعليق" }
        if hasTimeline && (duration<=0 || number("end")<=number("start")) { return "Choose a valid time range · اختر فترة زمنية صالحة" }
        if action.id=="snapshot" && snapshots.isEmpty { return "Choose a snapshot position · اختر موضع اللقطة" }
        if needsRegion && preview == nil { return "This format has no native preview. Convert it to PNG or MP4 first.\nلا تتوفر معاينة لهذا التنسيق. حوّله أولاً إلى PNG أو MP4." }
        return nil
    }
    var parameters:[String:Any] {
        var result:[String:Any]=[:]
        for field in fields {
            let value=values[field.key] ?? ""
            switch field.control {
            case .pages: result[field.key]=pageOrder.map(String.init).joined(separator:",")
            case .snapshots: result[field.key]=snapshots.sorted().map { String($0) }.joined(separator:",")
            case .text,.color: result[field.key]=value
            default: result[field.key]=Double(value) ?? 0
            }
        }
        if needsRegion { result["region"]=region }
        if action.id=="metadata" { result=["metadata":setMetadata ? values.filter { !$0.value.isEmpty }:[:]] }
        return result
    }
    func reset() {
        values=Dictionary(uniqueKeysWithValues:fields.map { ($0.key,$0.initial) })
        if hasTimeline,duration>0 { values["end"]=String(min(10,duration)) }
        region=[0.1,0.1,0.8,0.8];snapshots=[0];pageOrder=pages.map(\.id);original=false;pause();seek(0);schedulePreview()
    }
    // A small native approximation keeps sliders responsive; the saved copy uses the full-resolution engine.
    func schedulePreview() {
        guard action.id=="editImage",let input=previewInput else { return }
        previewGeneration+=1;let generation=previewGeneration
        pendingPreview?.cancel()
        let values=self.values
        let work=DispatchWorkItem { [weak self] in
            var image=input
            let factor=min(1,800/max(image.extent.width,image.extent.height))
            image=image.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
            let brightness=Double(values["brightness"] ?? "1") ?? 1
            image=image.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:brightness,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:brightness,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:brightness,w:0)])
            image=image.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:Double(values["contrast"] ?? "1") ?? 1,kCIInputSaturationKey:Double(values["saturation"] ?? "1") ?? 1])
            let sharpness=Double(values["sharpness"] ?? "1") ?? 1
            if sharpness<1 { image=image.applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:(1-sharpness)*2]).cropped(to:image.extent) }
            else if sharpness>1 { image=image.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:(sharpness-1)*0.5]) }
            let angle = -(Double(values["rotation"] ?? "0") ?? 0)*Double.pi/180
            image=image.transformed(by:CGAffineTransform(rotationAngle:angle))
            if let cg=CIContext().createCGImage(image,from:image.extent) {
                DispatchQueue.main.async { [weak self] in guard let self,self.previewGeneration==generation else { return };self.renderedPreview=NSImage(cgImage:cg,size:.zero) }
            }
        }
        pendingPreview=work;previewQueue.asyncAfter(deadline:.now()+0.06,execute:work)
    }
}

func timeLabel(_ value:Double)->String {
    let value=max(0,value);return String(format:"%02d:%05.2f",Int(value)/60,value.truncatingRemainder(dividingBy:60))
}
struct PlayerSurface:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->AVPlayerView { let view=AVPlayerView();view.controlsStyle = .none;view.videoGravity = .resizeAspect;view.player=player;return view }
    func updateNSView(_ view:AVPlayerView,context:Context) { view.player=player }
}
struct OperationEditor:View {
    @ObservedObject var model:EditorModel
    let finish:(Bool)->Void
    private var contentHeight:CGFloat { min(590,max(260,(NSScreen.main?.visibleFrame.height ?? 900)-240)) }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text(model.action.displayTitle).font(.system(size:18,weight:.semibold));Spacer();Text("Anasing").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(glassAccent) }
            Text(model.source.lastPathComponent).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    preview
                    if model.action.id=="metadata" { Toggle("Set new metadata · إضافة بيانات جديدة\nLeave off to remove existing metadata · أوقفه لحذف البيانات",isOn:$model.setMetadata).font(.system(size:12)) }
                    if model.hasTimeline { timeline }
                    ForEach(model.fields) { field in
                        if case .timeline=field.control { EmptyView() }
                        else { fieldView(field).disabled(model.action.id=="metadata" && !model.setMetadata) }
                    }
                    if let error=model.validation { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
                }.padding(.trailing,8).padding(.vertical,2)
            }.frame(maxHeight:contentHeight)
            Text("New copy saved beside the original · نسخة جديدة بجانب الملف الأصلي").font(.system(size:10)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel · إلغاء") { model.pause();finish(false) }.keyboardShortcut(.cancelAction)
                Button("Reset · إعادة") { model.reset() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Apply · تطبيق") { model.pause();finish(true) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.white.opacity(0.22)).disabled(model.validation != nil)
            }
        }.padding(22).frame(width:586).foregroundStyle(.white.opacity(0.94)).background(GlassSurface()).preferredColorScheme(.dark)
    }
    @ViewBuilder var preview:some View {
        if model.needsRegion,let image=model.preview {
            RegionSelector(image:image,region:$model.region,action:model.action.id,values:model.values).frame(height:230).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:10))
            Text(model.action.id.hasPrefix("redact") ? "Drag over the area to cover · اسحب فوق المنطقة لحجبها":model.action.id=="annotateImage" ? "Drag to position your text · اسحب لتحديد موضع النص":"Drag to crop · اسحب لتحديد الاقتصاص").font(.caption).foregroundStyle(.secondary)
        } else if model.action.id=="editImage",let image=model.original ? model.preview:model.renderedPreview {
            Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:.infinity).frame(height:215).background(.black.opacity(0.45),in:RoundedRectangle(cornerRadius:10))
            HStack { Text("Live preview · معاينة تقريبية").font(.caption).foregroundStyle(.secondary);Spacer();Toggle("Original · الأصل",isOn:$model.original).toggleStyle(.switch).controlSize(.mini) }
        } else if model.action.id=="frameImage",let image=model.preview {
            GeometryReader { geo in
                let scale=min(geo.size.width/(image.size.width+2*model.number("margin")),geo.size.height/(image.size.height+2*model.number("margin")))
                Image(nsImage:image).resizable().frame(width:image.size.width*scale,height:image.size.height*scale)
                    .clipShape(RoundedRectangle(cornerRadius:model.number("radius")*scale))
                    .padding(model.number("margin")*scale).background(color(model.values["color"] ?? "#FFFFFF"))
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.frame(height:210)
        }
        if let player=model.player {
            if FileCategory.identify(model.source) == .video && !model.needsRegion {
                ZStack {
                    PlayerSurface(player:player)
                    if !model.playing,model.position<0.01,let image=model.preview { Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity).background(.black) }
                }.frame(height:210).clipShape(RoundedRectangle(cornerRadius:10))
            }
            HStack {
                Button { model.togglePlayback() } label:{ Image(systemName:model.playing ? "pause.fill":"play.fill").frame(width:24) }.help("Play / Pause · تشغيل / إيقاف")
                Slider(value:Binding(get:{model.position},set:{model.pause();model.seek($0)}),in:0...max(0.01,model.duration)).accessibilityLabel("Playback position · موضع التشغيل").disabled(model.duration<=0)
                Text(timeLabel(model.position)+" / "+timeLabel(model.duration)).font(.system(size:10,design:.monospaced))
            }
        }
    }
    var timeline:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Select time range · حدد الفترة الزمنية").font(.system(size:12,weight:.medium))
            RangeTrack(start:model.rangeBinding("start"),end:model.rangeBinding("end"),duration:max(0.01,model.duration)).frame(height:36)
            HStack {
                Text("In · بداية  "+timeLabel(model.number("start")))
                Spacer()
                Text("Out · نهاية  "+timeLabel(model.number("end")))
            }.font(.system(size:11,design:.monospaced))
            HStack {
                Button("Start here · البداية هنا") { model.rangeBinding("start").wrappedValue=model.position }
                Button("End here · النهاية هنا") { model.rangeBinding("end").wrappedValue=model.position }
                Spacer();Text(timeLabel(model.number("end")-model.number("start"))).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            }.controlSize(.small)
        }.padding(12).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
    }
    @ViewBuilder func fieldView(_ field:EditorField)->some View {
        VStack(alignment:.leading,spacing:7) {
            if case .pages=field.control { pagePicker }
            else if case .snapshots=field.control { snapshotPicker }
            else {
                HStack {
                    Text(field.label+" · "+field.arabicLabel).font(.system(size:11,weight:.medium))
                    Spacer()
                    if case let .slider(_,_,step,unit)=field.control { Text(String(format:step<1 ? "%.2f%@":"%.0f%@",model.number(field.key),unit)).monospacedDigit().font(.system(size:11)).foregroundStyle(.secondary) }
                }
                switch field.control {
                case .text:
                    TextField(field.label,text:model.binding(field.key)).textFieldStyle(.roundedBorder).controlSize(.regular)
                case let .slider(low,high,step,_):
                    HStack(spacing:12) {
                        Slider(value:model.numericBinding(field.key),in:low...high,step:step).accessibilityLabel(field.label+" · "+field.arabicLabel)
                        Stepper("",value:model.numericBinding(field.key),in:low...high,step:step).labelsHidden().controlSize(.small)
                    }
                case let .choice(options):
                    Picker(field.label,selection:model.binding(field.key)) { ForEach(options,id:\.0) { value,label in Text(label).tag(value) } }.labelsHidden().pickerStyle(.menu)
                case .color:
                    HStack(spacing:10) {
                        ColorPicker("Choose color · اختر اللون",selection:Binding(get:{color(model.values[field.key] ?? "#FFFFFF")},set:{ value in
                            guard let c=NSColor(value).usingColorSpace(.sRGB) else { return }
                            model.update(field.key,String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded())))
                        }),supportsOpacity:false)
                        ForEach(["#000000","#FFFFFF","#FF5500","#2785FF","#34C759"],id:\.self) { hex in
                            Button { model.update(field.key,hex) } label:{ Circle().fill(color(hex)).frame(width:18,height:18).overlay(Circle().stroke(.white.opacity(model.values[field.key]==hex ? 1:0.2),lineWidth:2)) }.buttonStyle(.plain).accessibilityLabel(hex)
                        }
                    }
                default: EmptyView()
                }
            }
        }
    }
    var snapshotPicker:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Scrub, then add a frame · حرّك المؤشر ثم أضف لقطة").font(.system(size:11));Spacer();Button("＋ Add · إضافة") {
                let t=(model.position*100).rounded()/100
                if !model.snapshots.contains(where:{abs($0-t)<0.01}) { model.snapshots.append(t) }
            }.disabled(model.duration<=0) }
            ScrollView(.horizontal) { HStack { ForEach(model.snapshots.sorted(),id:\.self) { time in
                HStack(spacing:6) {
                    Button(timeLabel(time)) { model.pause();model.seek(time) }.buttonStyle(.plain)
                    Button { model.snapshots.removeAll {$0==time} } label:{ Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).help("Remove · حذف")
                }.font(.system(size:11,design:.monospaced)).padding(7).background(.white.opacity(0.1),in:Capsule())
            } } }
        }
    }
    var pagePicker:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Choose pages · اختر الصفحات").font(.system(size:12,weight:.medium));Spacer()
                Button("All · الكل") { model.pageOrder=model.pages.map(\.id) }
                Button("Clear · مسح") { model.pageOrder=[] }
            }.controlSize(.small)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:84))],spacing:12) {
                ForEach(model.pages) { page in
                    Button { model.togglePage(page.id) } label:{
                        VStack(spacing:5) {
                            Image(nsImage:page.image).resizable().scaledToFit().frame(height:92).rotationEffect(.degrees(model.number("rotation")))
                            HStack { Text("\(page.id)");Image(systemName:model.pageOrder.contains(page.id) ? "checkmark.circle.fill":"circle") }.font(.system(size:11))
                        }.padding(6).frame(maxWidth:.infinity).background(.white.opacity(model.pageOrder.contains(page.id) ? 0.16:0.04),in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).accessibilityLabel("Page · صفحة \(page.id)")
                }
            }
            Text("Output order · ترتيب الناتج").font(.system(size:11)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing:8) { ForEach(model.pageOrder,id:\.self) { page in
                    HStack(spacing:7) {
                        Button { model.movePage(page,by:-1) } label:{ Image(systemName:"chevron.left") }.disabled(model.pageOrder.first==page).help("Move earlier · تقديم")
                        Text("\(page)").monospacedDigit()
                        Button { model.movePage(page,by:1) } label:{ Image(systemName:"chevron.right") }.disabled(model.pageOrder.last==page).help("Move later · تأخير")
                    }.buttonStyle(.plain).font(.system(size:11)).padding(8).background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
                } }
            }
        }
    }
    func color(_ hex:String)->Color {
        let n=UInt32(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0
        return Color(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255)
    }
}
struct RangeTrack:View {
    @Binding var start:Double
    @Binding var end:Double
    let duration:Double
    var body:some View {
        GeometryReader { geo in
            let width=max(1,geo.size.width-20)
            let left=10+width*start/duration,right=10+width*end/duration
            ZStack(alignment:.topLeading) {
                Capsule().fill(.white.opacity(0.12)).frame(height:6).offset(y:15)
                Capsule().fill(.white.opacity(0.65)).frame(width:max(0,right-left),height:6).offset(x:left,y:15)
                handle("Start · البداية").accessibilityValue(timeLabel(start)).accessibilityAdjustableAction { direction in
                    if direction == .increment { start+=0.1 } else if direction == .decrement { start-=0.1 }
                }.offset(x:left-10).gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("range")).onChanged { start=max(0,min(duration,($0.location.x-10)/width*duration)) })
                handle("End · النهاية").accessibilityValue(timeLabel(end)).accessibilityAdjustableAction { direction in
                    if direction == .increment { end+=0.1 } else if direction == .decrement { end-=0.1 }
                }.offset(x:right-10).gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("range")).onChanged { end=max(0,min(duration,($0.location.x-10)/width*duration)) })
            }.coordinateSpace(name:"range")
        }
    }
    func handle(_ label:String)->some View {
        RoundedRectangle(cornerRadius:5).fill(.white).frame(width:20,height:36).overlay(Image(systemName:"line.3.vertical").font(.system(size:10)).foregroundStyle(.black.opacity(0.6)))
            .accessibilityLabel(label)
    }
}
struct RegionSelector:NSViewRepresentable {
    let image:NSImage
    @Binding var region:[Double]
    let action:String
    let values:[String:String]
    func makeNSView(context:Context)->RegionCanvas { let view=RegionCanvas();view.image=image;view.changed={region=$0};return view }
    func updateNSView(_ view:RegionCanvas,context:Context) { view.image=image;view.region=region;view.action=action;view.values=values;view.needsDisplay=true }
}
final class RegionCanvas:NSView {
    var image:NSImage?
    var action=""
    var values:[String:String]=[:]
    var region:[Double]=[0.1,0.1,0.8,0.8]
    var changed:(([Double])->Void)?
    var start:NSPoint?
    override var isFlipped:Bool { true }
    var imageRect:NSRect {
        guard let image, image.size.width>0,image.size.height>0 else { return bounds }
        let ratio=min(bounds.width/image.size.width,bounds.height/image.size.height)
        let size=NSSize(width:image.size.width*ratio,height:image.size.height*ratio)
        return NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
    }
    override func draw(_ dirtyRect:NSRect) {
        let rect=imageRect
        image?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        let selection=NSRect(x:rect.minX+region[0]*rect.width,y:rect.minY+region[1]*rect.height,width:region[2]*rect.width,height:region[3]*rect.height)
        let shade=NSBezierPath(rect:rect);shade.append(NSBezierPath(rect:selection));shade.windingRule = .evenOdd;NSColor.black.withAlphaComponent(0.45).setFill();shade.fill()
        NSColor.white.setStroke();let path=NSBezierPath(rect:selection);path.lineWidth=2;path.stroke()
        let hex=UInt32((values["color"] ?? "#000000").replacingOccurrences(of:"#",with:""),radix:16) ?? 0
        let color=NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
        if action.hasPrefix("redact") { color.setFill();selection.fill() }
        if action=="annotateImage" {
            color.setStroke();path.stroke()
            let size=max(6,(Double(values["fontSize"] ?? "36") ?? 36)*rect.width/max(1,image?.size.width ?? 1))
            ((values["text"] ?? "") as NSString).draw(in:selection.insetBy(dx:4,dy:4),withAttributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color])
        }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
    func clamped(_ event:NSEvent)->NSPoint { let p=convert(event.locationInWindow,from:nil),r=imageRect;return NSPoint(x:min(max(p.x,r.minX),r.maxX),y:min(max(p.y,r.minY),r.maxY)) }
    override func mouseDown(with event:NSEvent) { start=clamped(event) }
    override func mouseDragged(with event:NSEvent) {
        guard let start else { return };let end=clamped(event),rect=imageRect
        let width=max(1,abs(end.x-start.x)),height=max(1,abs(end.y-start.y))
        region=[(min(start.x,end.x)-rect.minX)/rect.width,(min(start.y,end.y)-rect.minY)/rect.height,width/rect.width,height/rect.height]
        changed?(region);needsDisplay=true
    }
}

func editParameters(action:WheelAction,urls:[URL])->[String:Any]? {
    let needs=["compress","metadata","editImage","annotateImage","frameImage","cropImage","redactImage","cropVideo","trimVideo","trimAudio","speed","snapshot","splitVideo","redactVideo","normalizeAudio","channels","bleep","collage","organizePDF"]
    guard needs.contains(action.id),let source=urls.first else { return [:] }
    let model=EditorModel(action:action,source:source)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:586,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.title="Anasing · "+action.title.capitalized;window.isReleasedWhenClosed=false;configureGlassWindow(window)
    let hosting=NSHostingView(rootView:OperationEditor(model:model) { accepted in NSApp.stopModal(withCode:accepted ? .OK:.cancel) })
    window.contentView=hosting;window.setContentSize(hosting.fittingSize)
    window.center();NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
    let result=NSApp.runModal(for:window);model.pause();window.orderOut(nil)
    return result == .OK ? model.parameters:nil
}
