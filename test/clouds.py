"""Turn test/clouds_view.bend's Image trees into PNGs and a contact sheet (Pillow)."""
from pathlib import Path

from PIL import Image, ImageDraw
from sky import picture


if __name__ == '__main__':
    labels = ['morning', 'morning-off', 'clear', 'overcast', 'away', 'overhead', 'sunset', 'night',
              'ground', 'ground-off', 'ground-overcast', 'ground-clear']
    sheet = Image.new('RGB', (1024, 312 * ((len(labels) + 1) // 2)), '#161922')
    for i, label in enumerate(labels):
        path = Path(f'build/clouds-{label}.tree')
        image = picture(path)
        image.save(path.with_suffix('.png'))
        x, y = i % 2 * 512, i // 2 * 312
        sheet.paste(image, (x, y + 24))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), label, fill='white')
    sheet.save('build/clouds-contact.png')
    print('build/clouds-contact.png')
