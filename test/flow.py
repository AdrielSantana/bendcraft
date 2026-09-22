"""Inspect test/flow_view.bend's GPU images of the flow."""
from pathlib import Path

from PIL import Image, ImageDraw
from sky import picture


if __name__ == '__main__':
    labels = ['dug', 'filling', 'wading', 'settled', 'settled-wading', 'stair-side']
    sheet = Image.new('RGB', (1024, 312 * ((len(labels) + 1) // 2)), '#161922')
    for i, label in enumerate(labels):
        path = Path(f'build/flow-{label}.tree')
        image = picture(path)
        image.save(path.with_suffix('.png'))
        x, y = i % 2 * 512, i // 2 * 312
        sheet.paste(image, (x, y + 24))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), label, fill='white')
    sheet.save('build/flow-contact.png')
    print('build/flow-contact.png')
