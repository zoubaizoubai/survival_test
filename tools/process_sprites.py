#!/usr/bin/env python3
"""Chroma-key magenta game art and pack engine-ready PNGs."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(
	"/Users/zoubai/.grok/sessions/%2FUsers%2Fzoubai%2Fworkspace%2Fgds%2F%E5%B9%B8%E5%AD%98%E8%80%85"
	"/01a028df-d81d-78f1-9dad-3e18f0beb9fd/images"
)
DST = Path("/Users/zoubai/workspace/gds/幸存者/assets")


def key_image(im: Image.Image) -> Image.Image:
	im = im.convert("RGBA")
	arr = np.asarray(im).copy()
	r = arr[:, :, 0].astype(np.int16)
	g = arr[:, :, 1].astype(np.int16)
	b = arr[:, :, 2].astype(np.int16)
	mx = np.maximum(r, b)
	mn = np.minimum(np.minimum(r, g), b)
	sat = (mx - mn).astype(np.float32) / np.maximum(mx, 1)
	# Magenta bg is pink (R≈B, G low). Coral/red fills have B much lower than R.
	is_mag = (
		(r > 90)
		& (b > 90)
		& (b > g * 1.18)
		& (b > r * 0.62)
		& (g < r * 0.62)
		& (sat > 0.25)
	)
	near = (
		(r > 80)
		& (b > 80)
		& (b > g * 1.08)
		& (b > r * 0.55)
		& (g < r * 0.70)
		& (sat > 0.16)
	)
	alpha = np.where(is_mag, 0, np.where(near, 110, 255)).astype(np.uint8)
	arr[:, :, 3] = alpha
	return Image.fromarray(arr, "RGBA")


def bbox_of(im: Image.Image, thresh: int = 140) -> tuple[int, int, int, int] | None:
	arr = np.asarray(im)
	mask = arr[:, :, 3] > thresh
	ys, xs = np.where(mask)
	if xs.size == 0:
		return None
	return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def pack(im: Image.Image, canvas: int | None, pad_ratio: float = 0.06) -> Image.Image:
	box = bbox_of(im)
	if box is None:
		return im
	x0, y0, x1, y1 = box
	cropped = im.crop((x0, y0, x1, y1))
	bw, bh = cropped.size
	pad = int(max(bw, bh) * pad_ratio)
	if canvas is None:
		out = Image.new("RGBA", (bw + pad * 2, bh + pad * 2), (0, 0, 0, 0))
		out.paste(cropped, (pad, pad), cropped)
		return out
	side = max(bw, bh) + pad * 2
	square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	square.paste(cropped, ((side - bw) // 2, (side - bh) // 2), cropped)
	return square.resize((canvas, canvas), Image.Resampling.LANCZOS)


def save(src_name: str, dest_rel: str, *, key: bool = True, canvas: int | None = 128, max_w: int | None = None) -> None:
	src = SRC / src_name
	if not src.exists():
		print("MISSING", src)
		return
	im = Image.open(src)
	if key:
		im = key_image(im)
		im = pack(im, canvas)
	else:
		im = im.convert("RGBA")
		if canvas is not None:
			im.thumbnail((canvas, canvas), Image.Resampling.LANCZOS)
	if max_w is not None and im.size[0] > max_w:
		nh = max(1, int(im.size[1] * (max_w / im.size[0])))
		im = im.resize((max_w, nh), Image.Resampling.LANCZOS)
	dest = DST / dest_rel
	dest.parent.mkdir(parents=True, exist_ok=True)
	im.save(dest, "PNG")
	print("wrote", dest.relative_to(DST), im.size)


# src, dest, key, canvas, max_w
JOBS = [
	# player
	("3.jpg", "sprites/player/idle.png", True, 128),
	("17.jpg", "sprites/player/walk_0.png", True, 128),
	("19.jpg", "sprites/player/walk_1.png", True, 128),
	("14.jpg", "sprites/player/walk_2.png", True, 128),
	("15.jpg", "sprites/player/walk_3.png", True, 128),
	("18.jpg", "sprites/player/attack_0.png", True, 128),
	("13.jpg", "sprites/player/attack_1.png", True, 128),
	("16.jpg", "sprites/player/attack_2.png", True, 128),
	# slime
	("7.jpg", "sprites/slime/walk_0.png", True, 96),
	("22.jpg", "sprites/slime/walk_1.png", True, 96),
	("7.jpg", "sprites/slime/walk_2.png", True, 96),
	("24.jpg", "sprites/slime/walk_3.png", True, 96),
	("24.jpg", "sprites/slime/attack_0.png", True, 96),
	("22.jpg", "sprites/slime/attack_1.png", True, 96),
	# bat
	("26.jpg", "sprites/bat/walk_0.png", True, 96),
	("8.jpg", "sprites/bat/walk_1.png", True, 96),
	("20.jpg", "sprites/bat/walk_2.png", True, 96),
	("8.jpg", "sprites/bat/walk_3.png", True, 96),
	("20.jpg", "sprites/bat/attack_0.png", True, 96),
	("26.jpg", "sprites/bat/attack_1.png", True, 96),
	# brute
	("9.jpg", "sprites/brute/walk_0.png", True, 128),
	("25.jpg", "sprites/brute/walk_1.png", True, 128),
	("25.jpg", "sprites/brute/attack_0.png", True, 128),
	("34.jpg", "sprites/brute/attack_1.png", True, 128),
	# charger
	("5.jpg", "sprites/charger/walk_0.png", True, 128),
	("23.jpg", "sprites/charger/walk_1.png", True, 128),
	("23.jpg", "sprites/charger/attack_0.png", True, 128),
	("5.jpg", "sprites/charger/attack_1.png", True, 128),
	# caster
	("11.jpg", "sprites/caster/walk_0.png", True, 112),
	("21.jpg", "sprites/caster/walk_1.png", True, 112),
	("21.jpg", "sprites/caster/attack_0.png", True, 112),
	("11.jpg", "sprites/caster/attack_1.png", True, 112),
	# elite
	("6.jpg", "sprites/elite/walk_0.png", True, 144),
	("31.jpg", "sprites/elite/walk_1.png", True, 144),
	("31.jpg", "sprites/elite/attack_0.png", True, 144),
	("6.jpg", "sprites/elite/attack_1.png", True, 144),
	# boss
	("10.jpg", "sprites/boss/walk_0.png", True, 192),
	("27.jpg", "sprites/boss/walk_1.png", True, 192),
	("27.jpg", "sprites/boss/attack_0.png", True, 192),
	("33.jpg", "sprites/boss/attack_1.png", True, 192),
	# ui
	("2.jpg", "ui/panel.png", True, None, 640),
	("1.jpg", "ui/hp_bar.png", True, None, 512),
	("30.jpg", "ui/xp_bar.png", True, None, 512),
	("4.jpg", "ui/btn_primary.png", True, None, 420),
	("12.jpg", "ui/btn_primary_hover.png", True, None, 420),
	("32.jpg", "ui/btn_primary_pressed.png", True, None, 420),
	("28.jpg", "ui/btn_secondary.png", True, None, 420),
	("35.jpg", "ui/home_hero.png", False, 768, None),
	# icons
	("29.jpg", "icons/dagger.png", True, 96),
	("41.jpg", "icons/orbit.png", True, 96),
	("37.jpg", "icons/lightning.png", True, 96),
	("42.jpg", "icons/aura.png", True, 96),
	("39.jpg", "icons/boomerang.png", True, 96),
	("43.jpg", "icons/frost.png", True, 96),
	("38.jpg", "icons/damage.png", True, 96),
	("36.jpg", "icons/speed.png", True, 96),
	("46.jpg", "icons/haste.png", True, 96),
	("44.jpg", "icons/hp.png", True, 96),
	("40.jpg", "icons/magnet.png", True, 96),
	("45.jpg", "icons/pause.png", True, 96),
]


def main() -> None:
	for job in JOBS:
		src, dest, key, canvas = job[:4]
		max_w = job[4] if len(job) > 4 else None
		save(src, dest, key=key, canvas=canvas, max_w=max_w)


if __name__ == "__main__":
	main()
