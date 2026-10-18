#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Local file operations. JSON in, JSON out. No shell commands or network calls."""
import csv
import gzip
import html
import io
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps
import pillow_heif
import fitz

pillow_heif.register_heif_opener()
RESOURCES=Path(os.environ["ANASING_BUNDLE_RESOURCES"]) if os.environ.get("ANASING_BUNDLE_RESOURCES") else None
def tool(relative,development):
    if RESOURCES:
        path=RESOURCES/relative
        if not path.exists(): raise RuntimeError("A bundled conversion engine is missing: "+relative)
        return str(path)
    return development
FFMPEG=tool("tools/bin/ffmpeg","/opt/homebrew/bin/ffmpeg")
FFPROBE=tool("tools/bin/ffprobe","/opt/homebrew/bin/ffprobe")
SOFFICE=tool("LibreOffice.app/Contents/MacOS/soffice","/Applications/LibreOffice.app/Contents/MacOS/soffice")
TESSERACT=tool("tools/bin/tesseract","/opt/homebrew/bin/tesseract")
if RESOURCES:
    os.environ["TESSDATA_PREFIX"]=str(RESOURCES/"tools/share/tessdata")
    os.environ["PYTHONDONTWRITEBYTECODE"]="1"
    sys.dont_write_bytecode=True
IMAGE_EXTS = {"jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif", "avif", "bmp", "svg"}
VIDEO_EXTS = {"mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "m4v"}
AUDIO_EXTS = {"mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma", "aac"}
ARCHIVE_EXTS = {"zip", "tar", "gz", "tgz", "rar", "xz", "bz2"}
_active = None

def cancel(signum, frame):
    if _active and _active.poll() is None:
        try: os.killpg(_active.pid,signal.SIGTERM)
        except ProcessLookupError: pass
    raise InterruptedError("Cancelled")
signal.signal(signal.SIGTERM, cancel)

def run(args, timeout=3600):
    global _active
    with tempfile.TemporaryFile() as errors:
        _active = subprocess.Popen([str(x) for x in args], stdout=subprocess.PIPE, stderr=errors, start_new_session=True)
        try:
            data, _ = _active.communicate(timeout=timeout)
            if _active.returncode:
                errors.seek(0)
                raise ValueError(errors.read().decode("utf-8", "replace")[-3000:] or "Conversion failed")
            return data
        except BaseException:
            if _active.poll() is None:
                try: os.killpg(_active.pid,signal.SIGTERM)
                except ProcessLookupError: pass
                try: _active.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try: os.killpg(_active.pid,signal.SIGKILL)
                    except ProcessLookupError: pass
                    _active.wait()
            raise
        finally: _active = None

def ff(args): return run([FFMPEG, "-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + args)
def probe(path): return json.loads(run([FFPROBE, "-v", "error", "-show_format", "-show_streams", "-of", "json", path]))
def ext(path): return path.suffix.lower().lstrip(".")
def bounded(p, name, default, low, high):
    value = float(p.get(name, default))
    if not math.isfinite(value) or value < low or value > high: raise ValueError("%s must be between %s and %s" % (name, low, high))
    return value

def image(path):
    if ext(path) == "svg":
        doc = fitz.open(path)
        pdf = fitz.open("pdf", doc.convert_to_pdf())
        return Image.open(io.BytesIO(pdf[0].get_pixmap(matrix=fitz.Matrix(2,2), alpha=True).tobytes("png"))).convert("RGBA")
    with Image.open(path) as opened:
        return ImageOps.exif_transpose(opened).copy()

def save_image(im, output, quality=85, metadata=None):
    fmt = {"jpg":"JPEG", "heic":"HEIF", "tif":"TIFF"}.get(ext(output), ext(output).upper())
    if fmt in {"JPEG", "BMP", "PDF"} and im.mode != "RGB":
        flat = Image.new("RGB", im.size, "white")
        flat.paste(im, mask=im.getchannel("A") if "A" in im.getbands() else None); im = flat
    kwargs = {"quality":int(quality)} if fmt in {"JPEG", "WEBP", "AVIF", "HEIF"} else {}
    if fmt == "PNG": kwargs["optimize"] = True
    if metadata:
        if fmt == "PNG":
            from PIL.PngImagePlugin import PngInfo
            info = PngInfo()
            for k,v in metadata.items(): info.add_text(k, str(v))
            kwargs["pnginfo"] = info
        elif fmt in {"JPEG", "TIFF", "WEBP", "HEIF", "AVIF"}:
            exif = Image.Exif()
            for k,tag in {"title":270,"author":315,"copyright":33432,"date":306,"comment":37510}.items():
                if metadata.get(k): exif[tag] = str(metadata[k])
            kwargs["exif"] = exif.tobytes()
    # New pixel storage strips embedded metadata by default.
    clean = Image.frombytes(im.mode, im.size, im.tobytes())
    clean.save(output, format=fmt, **kwargs)

def box(p, size):
    region = p.get("region", [0.1,0.1,0.8,0.8])
    if len(region) != 4: raise ValueError("Select a rectangle")
    x,y,w,h = [float(n) for n in region]
    if any(not math.isfinite(n) for n in (x,y,w,h)) or x < 0 or y < 0 or w <= 0 or h <= 0 or x+w > 1.001 or y+h > 1.001: raise ValueError("The selected rectangle must fit inside the image")
    width,height = size
    return (int(x*width), int(y*height), min(width,int((x+w)*width)), min(height,int((y+h)*height)))

def image_tool(source, output, action, p):
    im = image(source).convert("RGBA")
    if action == "cropImage": im = im.crop(box(p, im.size))
    elif action == "redactImage":
        rect = box(p,im.size)
        if p.get("style") == "blur":
            im.paste(im.crop(rect).filter(ImageFilter.GaussianBlur(bounded(p,"blur",25,1,100))),rect[:2])
        else: ImageDraw.Draw(im).rectangle(rect, fill=p.get("color", "#000000"))
    elif action == "editImage":
        for key, cls in [("brightness",ImageEnhance.Brightness),("contrast",ImageEnhance.Contrast),("saturation",ImageEnhance.Color),("sharpness",ImageEnhance.Sharpness)]:
            im = cls(im).enhance(bounded(p,key,1,0,4))
        im = im.rotate(-bounded(p,"rotation",0,-360,360), expand=True)
    elif action == "annotateImage":
        draw = ImageDraw.Draw(im); rect = box(p,im.size)
        color = p.get("color","#FF5500")
        draw.rectangle(rect, outline=color, width=max(2,round(im.width/150)))
        text = p.get("text", "")
        if text:
            font_size = int(bounded(p,"fontSize",36,6,300))
            font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf",font_size)
            draw.text((rect[0]+8,rect[1]+8), text, font=font, fill=color, stroke_width=1)
    elif action == "frameImage":
        margin = int(bounded(p,"margin",40,0,1000))
        radius = int(bounded(p,"radius",20,0,1000))
        mask = Image.new("L",im.size); ImageDraw.Draw(mask).rounded_rectangle((0,0,im.width,im.height),radius=radius,fill=255)
        result = Image.new("RGBA",(im.width+margin*2,im.height+margin*2),p.get("color","#FFFFFF"))
        result.paste(im,(margin,margin),ImageChops_multiply_alpha(im,mask)); im = result
    elif action == "compress":
        width = int(bounded(p,"width",1920,16,20000))
        im.thumbnail((width,width*10), Image.Resampling.LANCZOS)
    elif action != "metadata": raise ValueError("Unknown image operation")
    save_image(im,output,bounded(p,"quality",75,1,100),p.get("metadata") if action == "metadata" else None)

def ImageChops_multiply_alpha(im, mask):
    from PIL import ImageChops
    return ImageChops.multiply(im.getchannel("A"),mask)

def audio_args(target, p=None):
    p = p or {}; bitrate = str(int(bounded(p,"bitrate",160,32,320))) + "k"
    return {
        "mp3":["-c:a","libmp3lame","-b:a",bitrate], "m4a":["-c:a","aac","-b:a",bitrate],
        "aac":["-c:a","aac","-b:a",bitrate], "wav":["-c:a","pcm_s16le"], "flac":["-c:a","flac"],
        "ogg":["-c:a","vorbis","-strict","experimental","-ac","2","-q:a","4"], "opus":["-c:a","libopus","-b:a",bitrate],
        "aiff":["-c:a","pcm_s16be"], "wma":["-c:a","wmav2","-b:a",bitrate]
    }[target]

def video_args(target, p=None):
    p = p or {}; crf = str(int(bounded(p,"crf",24,0,51)))
    if target == "webm": return ["-c:v","libvpx-vp9","-crf",crf,"-b:v","0","-c:a","libopus"]
    if target == "wmv": return ["-c:v","wmv2","-b:v","2M","-c:a","wmav2"]
    if target == "avi": return ["-c:v","mpeg4","-q:v","5","-c:a","libmp3lame"]
    if target == "gif": return ["-an","-loop","0"]
    return ["-c:v","libx264","-preset","fast","-crf",crf,"-pix_fmt","yuv420p","-c:a","aac"] + (["-movflags","+faststart"] if target in {"mp4","mov"} else [])

def atempo(value):
    filters = []
    while value > 2: filters.append("atempo=2"); value /= 2
    while value < .5: filters.append("atempo=0.5"); value /= .5
    return ",".join(filters+["atempo=%s" % value])

def media(source, output, action, p):
    info = probe(source); streams = info.get("streams",[])
    has_video = any(s["codec_type"] == "video" for s in streams)
    has_audio = any(s["codec_type"] == "audio" for s in streams)
    target = ext(output); is_audio = target in AUDIO_EXTS
    args = ["-i",str(source)]
    vf = []; af = []
    if action in {"trimVideo","trimAudio"}:
        start = bounded(p,"start",0,0,1e9); end = bounded(p,"end",10,0.001,1e9)
        duration = float(info.get("format",{}).get("duration",end))
        if start >= end or start >= duration: raise ValueError("Trim start must be before the end and inside the recording")
        args += ["-ss",str(start),"-t",str(end-start)]
    if action == "cropVideo":
        stream = next(s for s in streams if s["codec_type"] == "video")
        x,y,right,bottom = box(p,(stream["width"],stream["height"]))
        width=max(2,(right-x)//2*2); height=max(2,(bottom-y)//2*2)
        vf += ["crop=%d:%d:%d:%d" % (width,height,x//2*2,y//2*2)]
    if action == "speed":
        speed = bounded(p,"speed",2,.125,8); vf += ["setpts=PTS/%s" % speed]
        if has_audio: af += [atempo(speed)]
    if action == "redactVideo":
        stream = next(s for s in streams if s["codec_type"] == "video")
        x,y,right,bottom = box(p,(stream["width"],stream["height"]))
        start = bounded(p,"start",0,0,1e9); end = bounded(p,"end",1e9,0.001,1e9)
        if end <= start: raise ValueError("Redaction end must follow start")
        vf += ["drawbox=x=%d:y=%d:w=%d:h=%d:color=black:t=fill:enable='between(t,%s,%s)'" % (x,y,right-x,bottom-y,start,end)]
    if action == "normalizeAudio": af += ["loudnorm=I=%s:TP=-1.5:LRA=11" % bounded(p,"loudness",-16,-30,-5)]
    if action == "channels": args += ["-ac",str(int(bounded(p,"channels",1,1,2)))]
    if action == "bleep":
        start = bounded(p,"start",0,0,1e9); end = bounded(p,"end",1,0.001,1e9)
        if end <= start: raise ValueError("Bleep end must follow start")
        duration = float(info.get("format",{}).get("duration",0))
        if start >= duration: raise ValueError("Bleep range is outside the recording")
        filtergraph = "[0:a]volume=0:enable='between(t,%s,%s)'[base];sine=frequency=1000:duration=%s,volume=0.15,adelay=%d:all=1[tone];[base][tone]amix=inputs=2:duration=first:normalize=0[out]" % (start,end,min(end,duration)-start,int(start*1000))
        args += ["-filter_complex",filtergraph,"-map","[out]"]
    if action == "visualize":
        args += ["-filter_complex","[0:a]showwaves=s=1280x720:mode=line:colors=0xff6600:rate=30,format=yuv420p[v]","-map","[v]","-map","0:a","-shortest"]
    if action == "compress" and has_video and not is_audio:
        width = int(bounded(p,"width",1280,16,20000))//2*2
        vf += ["scale='min(%d,iw)':-2" % width]
    if has_video and not is_audio and target != "gif" and action not in {"visualize","metadata"}: vf += ["scale=trunc(iw/2)*2:trunc(ih/2)*2"]
    if target == "gif" and action != "metadata": vf += ["fps=12","scale=640:-1:flags=lanczos","split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"]
    if vf: args += ["-vf", ",".join(vf)]
    if af: args += ["-af", ",".join(af)]
    if action == "metadata":
        args += ["-map_metadata","-1"]
        for key,value in p.get("metadata",{}).items():
            if key not in {"title","artist","author","album","comment","date","copyright"}: continue
            args += ["-metadata",key+"="+str(value)]
        args += ["-c","copy"]
    elif is_audio:
        args += ["-vn"] + audio_args(target,p)
    else: args += video_args(target,p)
    if action == "muteVideo": args += ["-an"]
    args += [str(output)]; ff(args)

def libreoffice(source, target, directory):
    if not Path(SOFFICE).exists(): raise ValueError("LibreOffice is required. Run scripts/setup.sh.")
    profile = directory / "lo-profile"
    filters = {"pdf":"pdf", "docx":"docx:Office Open XML Text", "xlsx":"xlsx:Calc MS Excel 2007 XML", "ods":"ods:calc8", "csv":"csv:Text - txt - csv (StarCalc):44,34,76,1", "tsv":"csv:Text - txt - csv (StarCalc):9,34,76,1", "html":"html", "txt":"txt:Text"}
    result = run([SOFFICE,"-env:UserInstallation="+profile.as_uri(),"--headless","--convert-to",filters.get(target,target),"--outdir",directory,source],timeout=180)
    actual = directory / (source.stem + (".csv" if target == "tsv" else "."+target))
    if not actual.exists(): raise ValueError("LibreOffice could not convert this file: " + result.decode("utf8","replace")[-1500:])
    return actual

def pdf_to(source, output, target, p):
    doc = fitz.open(source)
    if target in {"png","jpg"}:
        output.mkdir()
        for i,page in enumerate(doc):
            page.get_pixmap(dpi=300,alpha=False).save(output / ("page-%03d.%s" % (i+1,target)))
        return
    page_texts=[]
    needs_text=target in {"txt","md","docx","epub","xlsx"}
    for page in doc:
        content=page.get_text()
        if needs_text and not content.strip():
            tesseract=Path(TESSERACT)
            if not tesseract.exists(): raise ValueError("Local OCR is missing. Run scripts/setup.sh to enable scanned PDF text export.")
            with tempfile.TemporaryDirectory(prefix="Anasing-OCR-") as temp:
                raster=Path(temp)/"page.png";page.get_pixmap(dpi=250,alpha=False).save(raster)
                content=run([tesseract,raster,"stdout","-l","eng"]).decode("utf8","replace")
        page_texts.append(content)
    text="\n\n".join(page_texts)
    if needs_text and not text.strip(): raise ValueError("No readable text was found in this PDF.")
    if target in {"txt","md"}: output.write_text(text,encoding="utf8")
    elif target == "docx":
        from docx import Document
        result = Document()
        for i,page in enumerate(doc):
            if i: result.add_page_break()
            for para in page_texts[i].split("\n\n"): result.add_paragraph(para)
        result.save(output)
    elif target == "pptx":
        from pptx import Presentation
        from pptx.util import Inches
        result = Presentation(); ratio = doc[0].rect.width / doc[0].rect.height
        result.slide_width = Inches(10); result.slide_height = Inches(10/ratio)
        for page in doc:
            slide = result.slides.add_slide(result.slide_layouts[6])
            slide.shapes.add_picture(io.BytesIO(page.get_pixmap(dpi=144).tobytes("png")),0,0,width=result.slide_width,height=result.slide_height)
        result.save(output)
    elif target == "xlsx":
        from openpyxl import Workbook
        result = Workbook(); result.remove(result.active)
        for i,page in enumerate(doc):
            sheet = result.create_sheet("Page %d" % (i+1)); tables = page.find_tables().tables
            if tables:
                for table in tables:
                    for row in table.extract(): sheet.append(row)
                    sheet.append([])
            else:
                for line in page_texts[i].splitlines(): sheet.append([line])
        result.save(output)
    elif target == "epub": text_document(text,output,"epub",source.stem)
    else: raise ValueError("PDF export to %s is unavailable" % target)

def text_document(text, output, target, title="Document"):
    import pypandoc
    if target == "txt": output.write_text(text,encoding="utf8"); return
    fmt = {"md":"markdown","html":"html5","epub":"epub3"}.get(target,target)
    pypandoc.convert_text(text,fmt,format="markdown",outputfile=str(output),extra_args=["--standalone","--metadata","title="+title])

def document_to(source, output, target, scratch):
    import pypandoc
    source_ext = ext(source)
    if source_ext == target:
        shutil.copy2(source,output); return
    if source_ext in {"csv","tsv"}:
        rows=list(csv.reader(io.StringIO(source.read_text(encoding="utf-8-sig")),delimiter="\t" if source_ext=="tsv" else ","))
        if target in {"csv","tsv"}:
            with output.open("w",encoding="utf8",newline="") as stream:
                csv.writer(stream,delimiter="\t" if target=="tsv" else ",").writerows(rows)
            return
        from openpyxl import Workbook
        workbook=Workbook()
        for row in rows: workbook.active.append(row)
        if target=="xlsx": workbook.save(output); return
        work=scratch/"csv-work";work.mkdir(parents=True,exist_ok=True)
        intermediate=work/"table.xlsx";workbook.save(intermediate)
        document_to(intermediate,output,target,work/"convert"); return
    if target == "pages": raise ValueError("Apple Pages export is not available. Choose DOCX, PDF, or EPUB.")
    # Let LibreOffice preserve complex Office layouts; use Pandoc for text and EPUB interchange.
    office = {"docx","doc","odt","rtf","rtfd","pages","ppt","pptx","odp","xls","xlsx","ods"}
    if source_ext == "textclipping":
        import plistlib
        value = plistlib.loads(source.read_bytes()); text = value.get("UTI-Data",{}).get("public.utf8-plain-text","")
        if isinstance(text,bytes): text=text.decode("utf8")
        source = scratch / "clipping.txt"; source.write_text(text,encoding="utf8"); source_ext="txt"
    if target in {"jpg","png"}:
        pdf = scratch / "document.pdf"
        document_to(source,pdf,"pdf",scratch / "pdf-work")
        pdf_to(pdf,output,target,{})
    elif target == "pdf":
        work = scratch / "office"; work.mkdir(parents=True,exist_ok=True)
        if source_ext not in office and source_ext not in {"html","htm","csv","tsv"}:
            intermediate = work / "source.docx"
            if source_ext == "txt": text_document(source.read_text(encoding="utf8"),intermediate,"docx",source.stem)
            else: pypandoc.convert_file(str(source),"docx",outputfile=str(intermediate),extra_args=["--standalone"])
            source=intermediate
        shutil.copy2(libreoffice(source,"pdf",work),output)
    elif source_ext in office and target in {"docx","xlsx","ods","csv","tsv","html","txt"}:
        work=scratch/"office"; work.mkdir(parents=True,exist_ok=True)
        if target == source_ext: shutil.copy2(source,output)
        else: shutil.copy2(libreoffice(source,target,work),output)
    elif source_ext in {"csv","tsv"} and target in {"xlsx","ods"}:
        # Deterministic delimiter handling before handing the workbook to LibreOffice.
        from openpyxl import Workbook
        workbook=Workbook()
        for row in csv.reader(io.StringIO(source.read_text(encoding="utf-8-sig")), delimiter="\t" if source_ext=="tsv" else ","): workbook.active.append(row)
        if target=="xlsx": workbook.save(output)
        else:
            work=scratch/"office";work.mkdir(parents=True,exist_ok=True)
            temp=work/"table.xlsx";workbook.save(temp);shutil.copy2(libreoffice(temp,target,work),output)
    else:
        work=scratch/"pandoc";work.mkdir(parents=True,exist_ok=True)
        if source_ext in {"pages","doc","odt","rtf","rtfd","ppt","pptx"}:
            source = libreoffice(source,"docx",work);source_ext="docx"
        fmt={"txt":"plain","md":"markdown","html":"html5","epub":"epub3"}.get(target,target)
        if source_ext == "txt":
            text_document(source.read_text(encoding="utf8"),output,target,source.stem)
        else: pypandoc.convert_file(str(source),fmt,outputfile=str(output),extra_args=["--standalone","--metadata","title="+source.stem])

def subtitles(source, output, target):
    text = source.read_text(encoding="utf-8-sig").replace("\r\n","\n")
    cues = []
    for block in re.split(r"\n\s*\n",text.strip()):
        lines=block.splitlines()
        timing=next((i for i,line in enumerate(lines) if "-->" in line),None)
        if timing is None: continue
        times=lines[timing].split("-->")
        def normalize(s):
            t=s.strip().split()[0].replace(",", ".")
            if t.count(":")==1: t="00:"+t
            if not re.fullmatch(r"\d{2,}:\d{2}:\d{2}\.\d{3}",t): raise ValueError("Invalid subtitle timestamp: "+t)
            return t
        cues.append((normalize(times[0]),normalize(times[1]),"\n".join(lines[timing+1:])))
    if not cues: raise ValueError("No timed subtitle cues were found")
    if target == "txt":
        from bs4 import BeautifulSoup
        output.write_text("\n\n".join(BeautifulSoup(c[2],"html.parser").get_text() for c in cues),encoding="utf8")
    else:
        result = "WEBVTT\n\n" if target == "vtt" else ""
        for i,(start,end,words) in enumerate(cues,1):
            if target == "srt": start=start.replace(".",",");end=end.replace(".",",")
            result += (str(i)+"\n" if target == "srt" else "")+start+" --> "+end+"\n"+words+"\n\n"
        output.write_text(result,encoding="utf8")

# Extraction checks every member before writing; symlinks, hardlinks, and path escapes are rejected.
def safe_member(name, root):
    path = (root / name).resolve()
    if Path(name).is_absolute() or (path != root.resolve() and root.resolve() not in path.parents): raise ValueError("Archive contains an unsafe path")
    return path

def extract(source, directory):
    directory.mkdir(parents=True,exist_ok=True)
    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            for info in archive.infolist():
                safe_member(info.filename,directory)
                if ((info.external_attr >> 16) & 0o170000) == 0o120000: raise ValueError("Symbolic links in archives are not supported")
            archive.extractall(directory)
    elif tarfile.is_tarfile(source):
        with tarfile.open(source) as archive:
            for info in archive.getmembers():
                safe_member(info.name,directory)
                if not (info.isfile() or info.isdir()): raise ValueError("Archive contains links or special files")
            archive.extractall(directory)
    elif ext(source) == "rar":
        import rarfile
        rarfile.BSDTAR_TOOL="/usr/bin/tar"
        with rarfile.RarFile(source) as archive:
            for info in archive.infolist():
                safe_member(info.filename,directory)
                if info.is_symlink(): raise ValueError("Symbolic links in archives are not supported")
            archive.extractall(directory)
    elif ext(source) in {"gz","bz2","xz"}:
        import bz2,lzma
        opener={"gz":gzip.open,"bz2":bz2.open,"xz":lzma.open}[ext(source)]
        with opener(source,"rb") as src, open(directory/source.stem,"wb") as dst: shutil.copyfileobj(src,dst)
    else: raise ValueError("This archive format is not supported")

def archive_to(source,output,target,scratch):
    contents=scratch/"contents";extract(source,contents)
    if target=="zip":
        with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_DEFLATED) as archive:
            for path in contents.rglob("*"):
                if path.is_file(): archive.write(path,path.relative_to(contents))
    else:
        with tarfile.open(output,"w:gz" if target=="gz" else "w") as archive:
            for path in contents.iterdir(): archive.add(path,arcname=path.name)

def pdf_tool(sources,output,action,p):
    doc=fitz.open(sources[0])
    if action=="mergePDF":
        for source in sources[1:]:
            with fitz.open(source) as part: doc.insert_pdf(part)
    elif action=="splitPDF":
        output.mkdir()
        for i in range(len(doc)):
            part=fitz.open();part.insert_pdf(doc,from_page=i,to_page=i);part.save(output/("page-%03d.pdf" % (i+1)));part.close()
        return
    elif action=="organizePDF":
        order=p.get("pages","").strip()
        if not order: raise ValueError("Enter the pages to keep, in order (for example 3,1,2)")
        indices=[]
        for token in order.split(","):
            if "-" in token:
                a,b=map(int,token.strip().split("-"));indices.extend(range(a-1,b))
            else: indices.append(int(token)-1)
        if not indices or any(i<0 or i>=len(doc) for i in indices): raise ValueError("Page numbers are outside this PDF")
        doc.select(indices)
        rotation=int(p.get("rotation",0))
        for page in doc: page.set_rotation((page.rotation+rotation)%360)
    elif action=="metadata": doc.set_metadata({k:str(v) for k,v in p.get("metadata",{}).items() if k in {"title","author","subject","keywords","creator"}})
    elif action=="compress":
        quality=int(bounded(p,"quality",65,10,95))
        doc.rewrite_images(dpi_threshold=150,dpi_target=120,quality=quality,lossy=True)
    doc.save(output,garbage=4,deflate=True,clean=True)

def create_pdf(sources,output):
    doc=fitz.open()
    for source in sources:
        im=image(source).convert("RGB");buffer=io.BytesIO();im.save(buffer,format="PNG")
        page=doc.new_page(width=im.width*.75,height=im.height*.75)
        page.insert_image(page.rect,stream=buffer.getvalue())
    doc.save(output,deflate=True)

def collage(sources,output,p):
    columns=int(bounded(p,"columns",2,1,10));cell=int(bounded(p,"cell",600,64,4000));gap=int(bounded(p,"margin",20,0,200))
    rows=math.ceil(len(sources)/columns)
    result=Image.new("RGB",(columns*cell+(columns+1)*gap,rows*cell+(rows+1)*gap),p.get("color","#FFFFFF"))
    for index,path in enumerate(sources):
        im=ImageOps.fit(image(path).convert("RGB"),(cell,cell),method=Image.Resampling.LANCZOS)
        result.paste(im,(gap+(index%columns)*(cell+gap),gap+(index//columns)*(cell+gap)))
    save_image(result,output)

def join_videos(sources,output,scratch):
    normalized=[]
    for index,source in enumerate(sources):
        result=scratch/("clip-%d.mp4" % index); info=probe(source)
        args=["-i",str(source)]
        if not any(s["codec_type"]=="audio" for s in info["streams"]): args += ["-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-shortest"]
        args += ["-vf","scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1","-r","30","-c:v","libx264","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-ar","48000","-ac","2",str(result)]
        ff(args);normalized.append(result)
    listing=scratch/"join.txt";listing.write_text("\n".join("file '"+str(path).replace("'","'\\''")+"'" for path in normalized))
    ff(["-f","concat","-safe","0","-i",str(listing),"-c","copy",str(output)])

def execute(request):
    sources=[Path(p).resolve() for p in request.get("sources",[])]
    if not sources or any(not p.exists() for p in sources): raise ValueError("One or more source files no longer exist")
    action=request["action"]; p=request.get("parameters",{});outputs=[]
    if action=="convert:pages": raise ValueError("Pages export requires Apple Pages. Choose DOCX instead.")
    combine=action in {"createPDF","mergePDF","collage","joinVideos"}
    groups=[sources] if combine else [[s] for s in sources]
    for group in groups:
        source=group[0];source_ext=ext(source)
        parent=Path(request.get("outputDirectory") or source.parent).resolve()
        if not parent.is_dir(): raise ValueError("Output folder does not exist")
        target=action.split(":",1)[1] if action.startswith("convert:") else source_ext
        if target=="aif": target="aiff"
        is_folder=action in {"splitPDF","splitVideo","snapshot","extract"} or (action.startswith("convert:") and target in {"png","jpg"} and source_ext not in IMAGE_EXTS)
        if action in {"createPDF","mergePDF"}: target="pdf"
        if action=="collage": target="png"
        if action in {"joinVideos","visualize"}: target="mp4"
        if not action.startswith("convert:") and source_ext=="svg" and action not in {"createPDF","collage"}: target="png"
        if action=="compress" and source_ext=="wav": target="flac"
        suffix="" if is_folder else "."+("tar.gz" if target=="gz" else target)
        labels={"editImage":"Edited","cropImage":"Cropped","cropVideo":"Cropped","annotateImage":"Annotated","frameImage":"Background","redactImage":"Redacted","redactVideo":"Redacted","compress":"Compressed","metadata":"Metadata","createPDF":"Combined","collage":"Collage","joinVideos":"Joined","normalizeAudio":"Normalized","visualize":"Visualizer","trimAudio":"Trimmed","trimVideo":"Trimmed","channels":"Channels","bleep":"Bleeped","muteVideo":"Muted","speed":"Speed","snapshot":"Snapshots","splitVideo":"Clips","splitPDF":"Pages","organizePDF":"Organized","mergePDF":"Merged","extract":"Extracted"}
        base=source.stem+" — "+(target.upper() if action.startswith("convert:") else labels.get(action,action))
        destination=parent/(base+suffix);index=2
        while destination.exists(): destination=parent/(base+" "+str(index)+suffix);index+=1
        # All processing takes place in a temporary workspace. Commit only a complete result.
        with tempfile.TemporaryDirectory(prefix=".anasing-",dir=parent) as temp:
            scratch=Path(temp);output=scratch/("result"+suffix)
            if action.startswith("convert:"):
                if source_ext in IMAGE_EXTS:
                    if target=="pdf": create_pdf(group,output)
                    else: save_image(image(source),output,bounded(p,"quality",85,1,100))
                elif source_ext in VIDEO_EXTS or source_ext in AUDIO_EXTS: media(source,output,"convert",p)
                elif source_ext=="pdf": pdf_to(source,output,target,p)
                elif source_ext in {"srt","vtt"}: subtitles(source,output,target)
                elif source_ext in ARCHIVE_EXTS: archive_to(source,output,target,scratch)
                else: document_to(source,output,target,scratch)
            elif action=="createPDF": create_pdf(group,output)
            elif action=="collage": collage(group,output,p)
            elif action=="joinVideos": join_videos(group,output,scratch)
            elif action=="extract": extract(source,output)
            elif source_ext=="pdf": pdf_tool(group,output,action,p)
            elif source_ext in IMAGE_EXTS: image_tool(source,output,action,p)
            elif action=="snapshot":
                output.mkdir()
                for i,stamp in enumerate(str(p.get("times","0")).split(",")):
                    seconds=float(stamp)
                    if seconds<0: raise ValueError("Snapshot times must be positive")
                    ff(["-ss",str(seconds),"-i",str(source),"-frames:v","1",str(output/("frame-%03d.png" % (i+1)))])
                if not list(output.iterdir()): raise ValueError("No frame at that timestamp")
            elif action=="splitVideo":
                output.mkdir();seconds=bounded(p,"seconds",30,.1,86400)
                # Encode closed GOPs on boundaries for deterministic segment lengths.
                ff(["-i",str(source),"-c:v","libx264","-c:a","aac","-force_key_frames","expr:gte(t,n_forced*%s)"%seconds,"-f","segment","-segment_time",str(seconds),"-reset_timestamps","1",str(output/"clip-%03d.mp4")])
            else: media(source,output,action,p)
            if not output.exists() or (output.is_file() and not output.stat().st_size): raise ValueError("The operation produced no output")
            # Never overwrite an existing file, even if another process created it while working.
            index=2
            while destination.exists(): destination=parent/(base+" "+str(index)+suffix);index+=1
            shutil.move(str(output),str(destination));outputs.append(str(destination))
    return {"ok":True,"outputs":outputs}

if __name__=="__main__":
    try: result=execute(json.load(sys.stdin))
    except Exception as error: result={"ok":False,"error":str(error)}
    print(json.dumps(result));sys.exit(0 if result["ok"] else 1)
