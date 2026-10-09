#!/usr/bin/env python3
"""Pack generated Iznanka art; nearest-neighbor only, preserve source alpha."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'mods/iznanka/art/v02'
OUT=ROOT/'mods/iznanka/content'

def pack(name, bounds, heights):
    im=Image.open(ART/f'{name}-source.png').convert('RGBA')
    atlas=Image.new('RGBA',(128,32*(len(bounds)-1)))
    for row,(top,bottom) in enumerate(zip(bounds,bounds[1:])):
        for col in range(4):
            i=row*4+col
            cell=im.crop((round(col*im.width/4),top,round((col+1)*im.width/4),bottom))
            bbox=cell.getbbox()
            if bbox is None:raise ValueError(f'Empty sprite {name}:{i}')
            cell=cell.crop(bbox)
            limit=heights[i];ratio=min(28/cell.width,limit/cell.height)
            size=(max(1,round(cell.width*ratio)),max(1,round(cell.height*ratio)))
            cell=cell.resize(size,Image.Resampling.NEAREST)
            atlas.alpha_composite(cell,(col*32+(32-size[0])//2,row*32+30-size[1]))
    atlas.save(OUT/f'iznanka-{name}.png')

if __name__=='__main__':
    pack('monsters',[0,425,887],[28,28,20,28,30,28,28,24])
    pack('objects',[0,341,578,815,1106,1402],[30,30,30,22,18,18,16,18,20,26,26,24,22,28,28,24,24,22,20,18])
    Image.open(ART/'terrain-source.png').convert('RGBA').resize((128,64),Image.Resampling.NEAREST).save(OUT/'iznanka-terrain.png')
