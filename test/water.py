"""Inspect test/water_view.bend's GPU images above and below the lake."""
from pathlib import Path

from PIL import Image, ImageDraw
from sky import picture


if __name__ == '__main__':
    labels = ['default', 'lake', 'ripples-off', 'reflection-off', 'fresnel-off', 'off',
              'dusk', 'under', 'under-off', 'sunset-reflection', 'night-reflection', 'night-ripples-off',
              'caustic', 'caustic-off', 'bed', 'levels']
    sheet = Image.new('RGB', (1024, 312 * ((len(labels) + 1) // 2)), '#161922')
    for i, label in enumerate(labels):
        path = Path(f'build/water-{label}.tree')
        image = picture(path)
        image.save(path.with_suffix('.png'))
        x, y = i % 2 * 512, i // 2 * 312
        sheet.paste(image, (x, y + 24))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), label, fill='white')
    sheet.save('build/water-contact.png')
    print('build/water-contact.png')
    frames = [picture(Path(f'build/water-motion-{i}.tree')) for i in range(128)]
    frames[0].save('build/water-motion.gif', save_all=True, append_images=frames[1:],
                   duration=[60, 60, 70, 60, 70] * 25 + [60, 60, 70], loop=0, disposal=2)
    motion = Image.new('RGB', (1024, 4 * 312), '#161922')
    for i, frame in enumerate(frames[::16]):
        x, y = i % 2 * 512, i // 2 * 312
        motion.paste(frame, (x, y + 24))
        ImageDraw.Draw(motion).text((x + 8, y + 5), f'{i * 1024} ms, fixed sun', fill='white')
    motion.save('build/water-motion-contact.png')
    print('build/water-motion.gif and build/water-motion-contact.png')
