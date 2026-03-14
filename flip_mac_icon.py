from PIL import Image
import glob
import os

png_files = glob.glob('macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png')
for path in png_files:
    try:
        img = Image.open(path)
        img.transpose(Image.FLIP_LEFT_RIGHT).save(path)
        print("Flipped", path)
    except Exception as e:
        print("Failed", path, e)
