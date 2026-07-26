#!/usr/bin/env python3
"""크롭 전후 렌더를 비교해 **잉크가 하나도 잘리지 않았음**을 증명한다(#2603).

`render-svg.mjs --ink`로 뽑은 두 PNG(투명 배경·장식 숨김)를 받아서
크롭 창을 겹쳐 비교한다. 검사 항목은 셋이다.

1. 크롭 창 안의 픽셀이 바이트 단위로 같은가 — viewBox 원점을 0으로 두면
   래스터 격자가 어긋나지 않아 완전 동일이 나온다(#2603 실측: 5권역 전부 동일).
2. 잉크 픽셀 수가 같은가 — 잘린 것도 생긴 것도 없어야 한다.
3. 1픽셀 팽창 허용 비교 — 원점이 0이 아닌 크롭을 검토할 때는 안티에일리어싱
   위상이 달라져 1번이 깨질 수 있다. 그때도 서로 1픽셀 안에 들어오는지 본다.

사용법:
  python3 tools/route-map/svg-crop/verify-ink-lossless.py \
      before.png after.png [--offset X Y]

`--offset`은 크롭 박스의 좌상단(원본 좌표계, 렌더 배율을 곱한 픽셀값)이다.
우·하단만 자르는 현행 크롭(#2603)에서는 0 0이라 생략해도 된다.
"""
import argparse
import os
import sys
import tempfile

from PIL import Image, ImageChops, ImageFilter

Image.MAX_IMAGE_PIXELS = None


_HERE = os.path.dirname(os.path.abspath(__file__))
_ALLOWED_ROOTS = [
    os.path.realpath(os.path.join(_HERE, "..", "..", "..")),
    os.path.realpath(tempfile.gettempdir()),
    os.path.realpath("/tmp"),
]


def resolve_allowed(candidate):
    """저장소나 임시 디렉터리 안으로 해석되는 경로만 돌려준다."""
    resolved = os.path.realpath(candidate)
    for root in _ALLOWED_ROOTS:
        if resolved == root or resolved.startswith(root + os.sep):
            return resolved
    raise ValueError(
        "경로가 허용 범위 밖입니다: %s (허용: %s)"
        % (resolved, ", ".join(_ALLOWED_ROOTS))
    )


def alpha_mask(image):
    return image.getchannel("A").point(lambda v: 255 if v else 0)


def count(mask):
    return sum(1 for v in mask.get_flattened_data() if v)


def main():
    parser = argparse.ArgumentParser(description="크롭 전후 잉크 무손실 검증")
    parser.add_argument("before", help="크롭 전 렌더 PNG (render-svg.mjs --ink)")
    parser.add_argument("after", help="크롭 후 렌더 PNG (render-svg.mjs --ink)")
    parser.add_argument(
        "--offset",
        nargs=2,
        type=int,
        default=[0, 0],
        metavar=("X", "Y"),
        help="크롭 박스 좌상단(픽셀). 우·하단만 자르면 0 0.",
    )
    args = parser.parse_args()

    before = Image.open(resolve_allowed(args.before)).convert("RGBA")
    after = Image.open(resolve_allowed(args.after)).convert("RGBA")
    left, top = args.offset

    if left + after.width > before.width or top + after.height > before.height:
        print(
            "크롭 창이 원본 밖으로 나갑니다 — offset이나 배율을 확인하세요.",
            file=sys.stderr,
        )
        return 2

    window = before.crop((left, top, left + after.width, top + after.height))
    identical = window.tobytes() == after.tobytes()

    mask_before = alpha_mask(window)
    mask_after = alpha_mask(after)
    ink_before = count(mask_before)
    ink_after = count(mask_after)

    lost = count(
        ImageChops.subtract(mask_before, mask_after.filter(ImageFilter.MaxFilter(3)))
    )
    added = count(
        ImageChops.subtract(mask_after, mask_before.filter(ImageFilter.MaxFilter(3)))
    )

    # 크롭 창 **밖**에 잉크가 남아 있으면 그건 잘려나간 잉크다.
    outside = 0
    full = alpha_mask(before)
    full.paste(0, (left, top, left + after.width, top + after.height))
    outside = count(full)

    print(f"크롭 창 픽셀 완전 동일 : {identical}")
    print(f"잉크 픽셀 before/after : {ink_before:,} / {ink_after:,}")
    print(f"1px 팽창 허용 손실/추가: {lost:,} / {added:,}")
    print(f"크롭 창 밖 잔여 잉크    : {outside:,}")

    ok = lost == 0 and added == 0 and outside == 0
    print()
    print("RESULT:", "PASS — 잉크 무손실" if ok else "FAIL — 잉크가 잘렸습니다")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
