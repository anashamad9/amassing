#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import subprocess
import fitz
root=Path(__file__).resolve().parents[1]
folder=root/'.release-cache/Anasing.iconset';folder.mkdir(parents=True,exist_ok=True)
doc=fitz.open(root/'assets/Anasing.svg');pdf=fitz.open('pdf',doc.convert_to_pdf())
for size in [16,32,128,256,512]:
 for scale in [1,2]:
  pixels=size*scale
  pdf[0].get_pixmap(matrix=fitz.Matrix(pixels/1024,pixels/1024),alpha=True).save(folder/('icon_%dx%d%s.png'%(size,size,'@2x' if scale==2 else '')))
subprocess.run(['/usr/bin/iconutil','-c','icns',str(folder),'-o',str(root/'assets/Anasing.icns')],check=True)
