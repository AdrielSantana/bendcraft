"""The sheet for test/mirror_view.bend: each view with the world in the water's mirror, and without."""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw
from sky import picture


if __name__ == '__main__':
    views = ['across', 'bank', 'lake', 'sunset']
    sheet = Image.new('RGB', (1024, 310 * len(views)), '#161922')
    for row, view in enumerate(views):
        on = picture(Path(f'build/mirror-{view}.tree')).convert('RGB')
        off = picture(Path(f'build/mirror-{view}-off.tree')).convert('RGB')
        levels = list(ImageChops.difference(on, off).convert('L').getdata())
        moved = sum(1 for level in levels if level > 3) / len(levels) * 100
        print(f'{view:8} differs by {max(levels)} levels at most, on {moved:.1f}% of the pixels')
        sheet.paste(on, (0, row * 310 + 22))
        sheet.paste(off, (512, row * 310 + 22))
        draw = ImageDraw.Draw(sheet)
        draw.text((6, row * 310 + 5), f'{view}: the world in the mirror', fill='white')
        draw.text((518, row * 310 + 5), f'{view}: the sky alone', fill='white')
    sheet.save('build/mirror-sheet.png')
    print('build/mirror-sheet.png')
