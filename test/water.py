"""Inspect test/water_view.bend's GPU images above and below the lake."""
from pathlib import Path

from PIL import Image, ImageDraw
from sky import picture


if __name__ == '__main__':
    sheet = Image.new('RGB', (1024, 936), '#161922')
    for i, label in enumerate(['default', 'lake', 'off', 'dusk', 'under']):
        path = Path(f'build/water-{label}.tree')
        image = picture(path)
        image.save(path.with_suffix('.png'))
        x, y = i % 2 * 512, i // 2 * 312
        sheet.paste(image, (x, y + 24))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), label, fill='white')
    sheet.save('build/water-contact.png')
    print('build/water-contact.png')
