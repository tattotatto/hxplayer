from PIL import Image

ico_path = 'windows/runner/resources/app_icon.ico'
try:
    img = Image.open(ico_path)
    flipped = img.transpose(Image.FLIP_LEFT_RIGHT)
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    # Save flipped image as ICO, PIL will handle multiple sizes if sizes param is provided
    flipped.save(ico_path, format='ICO', sizes=sizes)
    print('Windows icon successfully flipped.')
except Exception as e:
    print('Failed to flip Windows icon:', e)
