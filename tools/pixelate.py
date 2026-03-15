#!/usr/bin/env python3
"""Interactive image pixelator with a slider."""

import sys
import tkinter as tk
from tkinter import filedialog
from PIL import Image, ImageTk


def pixelate(img, block_size):
    w, h = img.size
    small = img.resize((max(1, w // block_size), max(1, h // block_size)), Image.NEAREST)
    return small.resize((w, h), Image.NEAREST)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else None

    root = tk.Tk()
    root.title("Pixelator")
    root.configure(bg="#1a1a2e")

    if not path:
        path = filedialog.askopenfilename(
            title="Select an image",
            filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp *.gif *.webp *.svg")],
        )
        if not path:
            sys.exit(0)

    original = Image.open(path).convert("RGBA")

    # Scale down for display if too large
    max_display = 800
    display_scale = min(max_display / original.width, max_display / original.height, 1.0)
    display_w = int(original.width * display_scale)
    display_h = int(original.height * display_scale)
    display_img = original.resize((display_w, display_h), Image.LANCZOS)

    canvas = tk.Canvas(root, width=display_w, height=display_h, bg="#1a1a2e", highlightthickness=0)
    canvas.pack(padx=10, pady=10)

    tk_img = ImageTk.PhotoImage(display_img)
    canvas_img = canvas.create_image(0, 0, anchor=tk.NW, image=tk_img)

    info_var = tk.StringVar(value=f"Original: {original.width}x{original.height}")
    info_label = tk.Label(root, textvariable=info_var, bg="#1a1a2e", fg="#e0e0e0", font=("monospace", 11))
    info_label.pack()

    def update(val):
        nonlocal tk_img
        block = int(float(val))
        if block <= 1:
            result = display_img
            eff_w, eff_h = display_img.size
        else:
            result = pixelate(display_img, block)
            eff_w = max(1, display_w // block)
            eff_h = max(1, display_h // block)

        tk_img = ImageTk.PhotoImage(result)
        canvas.itemconfig(canvas_img, image=tk_img)
        info_var.set(f"Block size: {block}px | Effective resolution: {eff_w}x{eff_h}")

    max_block = max(display_w, display_h) // 2

    slider_frame = tk.Frame(root, bg="#1a1a2e")
    slider_frame.pack(fill=tk.X, padx=10, pady=(0, 5))
    tk.Label(slider_frame, text="Fine", bg="#1a1a2e", fg="#888").pack(side=tk.LEFT)
    slider = tk.Scale(
        slider_frame, from_=1, to=max_block, orient=tk.HORIZONTAL,
        command=update, bg="#1a1a2e", fg="#e0e0e0", troughcolor="#16213e",
        highlightthickness=0, length=display_w - 60,
    )
    slider.set(1)
    slider.pack(side=tk.LEFT, fill=tk.X, expand=True)
    tk.Label(slider_frame, text="Blocky", bg="#1a1a2e", fg="#888").pack(side=tk.LEFT)

    def save():
        block = slider.get()
        if block > 1:
            out = pixelate(original, block)
        else:
            out = original
        save_path = filedialog.asksaveasfilename(
            defaultextension=".png",
            filetypes=[("PNG", "*.png"), ("JPEG", "*.jpg")],
        )
        if save_path:
            out.save(save_path)
            info_var.set(f"Saved to {save_path}")

    btn = tk.Button(root, text="Save", command=save, bg="#16213e", fg="#e0e0e0", padx=20)
    btn.pack(pady=(0, 10))

    root.mainloop()


if __name__ == "__main__":
    main()
