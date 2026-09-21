"""Turn test/sky.bend's Image trees into PNGs and a contact sheet (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw


def picture(path):
    lines = iter(path.read_text().splitlines())
    image = Image.new('RGB', (512, 512))
    draw = ImageDraw.Draw(image)

    def node(x, y, size):
        line = next(lines)
        if line.startswith('P '):
            c = int(line[2:])
            draw.rectangle((x, y, x + size - 1, y + size - 1),
                           fill=(c >> 16, c >> 8 & 255, c & 255))
        else:
            assert line == 'Q'
            half = size // 2
            for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
                node(x + dx, y + dy, half)

    node(0, 0, 512)
    assert next(lines, None) is None
    return image.crop((0, 0, 512, 288))


if __name__ == '__main__':
    sheet = Image.new('RGB', (1024, 3 * 312), '#161922')
    labels = ['dawn', 'morning', 'noon', 'dusk', 'night', 'default']
    for i, label in enumerate(labels):
        path = Path(f'build/sky-{label}.tree')
        image = picture(path)
        image.save(path.with_suffix('.png'))
        x, y = i % 2 * 512, i // 2 * 312
        sheet.paste(image, (x, y + 24))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), label, fill='white')
    sheet.save('build/sky-contact.png')
    print('build/sky-contact.png')
