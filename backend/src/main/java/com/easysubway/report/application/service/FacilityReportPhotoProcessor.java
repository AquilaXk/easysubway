package com.easysubway.report.application.service;

import com.easysubway.report.domain.InvalidFacilityReportException;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Set;
import javax.imageio.ImageIO;

final class FacilityReportPhotoProcessor {

	static final int MAX_PHOTO_BYTES = 900 * 1024;
	private static final int MAX_PHOTO_BASE64_CHARS = ((MAX_PHOTO_BYTES + 2) / 3) * 4;
	private static final int THUMBNAIL_MAX_SIDE = 320;
	private static final Set<String> ALLOWED_PHOTO_CONTENT_TYPES = Set.of(
		"image/jpeg",
		"image/png"
	);

	FacilityReportPhotoAttachment process(String fileName, String contentType, String photoBase64) {
		validateCompleteAttachment(fileName, contentType, photoBase64);
		String normalizedContentType = normalizeContentType(contentType);
		String normalizedFileName = normalizeFileName(fileName);
		requireAllowedExtension(normalizedFileName, normalizedContentType);

		byte[] decodedBytes = decode(photoBase64);
		requireSupportedMagic(decodedBytes, normalizedContentType);
		BufferedImage image = readImage(decodedBytes);
		byte[] sanitizedBytes = rewriteImage(image, normalizedContentType);
		byte[] thumbnailBytes = rewriteImage(thumbnail(image), normalizedContentType);

		if (sanitizedBytes.length > MAX_PHOTO_BYTES) {
			throw new InvalidFacilityReportException("사진 파일 크기를 줄여야 합니다.");
		}
		return new FacilityReportPhotoAttachment(
			normalizedFileName,
			normalizedContentType,
			sanitizedBytes,
			thumbnailBytes,
			sha256(sanitizedBytes),
			sanitizedBytes.length
		);
	}

	boolean hasAnyPhotoField(String fileName, String contentType, String photoBase64) {
		return hasText(fileName) || hasText(contentType) || hasText(photoBase64);
	}

	private void validateCompleteAttachment(String fileName, String contentType, String photoBase64) {
		if (!hasText(fileName) || !hasText(contentType) || !hasText(photoBase64)) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
	}

	private String normalizeContentType(String contentType) {
		String normalized = contentType.trim().toLowerCase(Locale.ROOT);
		if (!ALLOWED_PHOTO_CONTENT_TYPES.contains(normalized)) {
			throw new InvalidFacilityReportException("사진 파일 형식을 확인해야 합니다.");
		}
		return normalized;
	}

	private String normalizeFileName(String fileName) {
		String normalized = fileName.trim();
		if (normalized.isEmpty()) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
		return normalized;
	}

	private void requireAllowedExtension(String fileName, String contentType) {
		String lowerName = fileName.toLowerCase(Locale.ROOT);
		boolean extensionMatches = switch (contentType) {
			case "image/jpeg" -> lowerName.endsWith(".jpg") || lowerName.endsWith(".jpeg");
			case "image/png" -> lowerName.endsWith(".png");
			default -> false;
		};
		if (!extensionMatches) {
			throw new InvalidFacilityReportException("사진 파일 형식을 확인해야 합니다.");
		}
	}

	private byte[] decode(String photoBase64) {
		String normalized = photoBase64.trim();
		if (normalized.length() > MAX_PHOTO_BASE64_CHARS) {
			throw new InvalidFacilityReportException("사진 파일 크기를 줄여야 합니다.");
		}
		try {
			byte[] decodedBytes = Base64.getDecoder().decode(normalized);
			if (decodedBytes.length > MAX_PHOTO_BYTES) {
				throw new InvalidFacilityReportException("사진 파일 크기를 줄여야 합니다.");
			}
			return decodedBytes;
		} catch (IllegalArgumentException exception) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
	}

	private void requireSupportedMagic(byte[] bytes, String contentType) {
		boolean matches = switch (contentType) {
			case "image/jpeg" -> bytes.length >= 3
				&& (bytes[0] & 0xff) == 0xff
				&& (bytes[1] & 0xff) == 0xd8
				&& (bytes[2] & 0xff) == 0xff;
			case "image/png" -> bytes.length >= 8
				&& (bytes[0] & 0xff) == 0x89
				&& bytes[1] == 0x50
				&& bytes[2] == 0x4e
				&& bytes[3] == 0x47
				&& bytes[4] == 0x0d
				&& bytes[5] == 0x0a
				&& bytes[6] == 0x1a
				&& bytes[7] == 0x0a;
			default -> false;
		};
		if (!matches) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
	}

	private BufferedImage readImage(byte[] bytes) {
		try {
			BufferedImage image = ImageIO.read(new ByteArrayInputStream(bytes));
			if (image == null || image.getWidth() <= 0 || image.getHeight() <= 0) {
				throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
			}
			return image;
		} catch (IOException exception) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
	}

	private byte[] rewriteImage(BufferedImage image, String contentType) {
		try {
			ByteArrayOutputStream output = new ByteArrayOutputStream();
			String formatName = "image/png".equals(contentType) ? "png" : "jpg";
			BufferedImage writable = ensureWritableRgb(image, contentType);
			if (!ImageIO.write(writable, formatName, output)) {
				throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
			}
			return output.toByteArray();
		} catch (IOException exception) {
			throw new InvalidFacilityReportException("사진 첨부 정보를 확인해야 합니다.");
		}
	}

	private BufferedImage ensureWritableRgb(BufferedImage image, String contentType) {
		int targetType = "image/png".equals(contentType) ? BufferedImage.TYPE_INT_ARGB : BufferedImage.TYPE_INT_RGB;
		if (image.getType() == targetType) {
			return image;
		}
		BufferedImage converted = new BufferedImage(image.getWidth(), image.getHeight(), targetType);
		Graphics2D graphics = converted.createGraphics();
		try {
			graphics.drawImage(image, 0, 0, null);
		} finally {
			graphics.dispose();
		}
		return converted;
	}

	private BufferedImage thumbnail(BufferedImage image) {
		int width = image.getWidth();
		int height = image.getHeight();
		int maxSide = Math.max(width, height);
		if (maxSide <= THUMBNAIL_MAX_SIDE) {
			return image;
		}
		double ratio = THUMBNAIL_MAX_SIDE / (double) maxSide;
		int thumbnailWidth = Math.max(1, (int) Math.round(width * ratio));
		int thumbnailHeight = Math.max(1, (int) Math.round(height * ratio));
		BufferedImage thumbnail = new BufferedImage(thumbnailWidth, thumbnailHeight, BufferedImage.TYPE_INT_RGB);
		Graphics2D graphics = thumbnail.createGraphics();
		try {
			graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
			graphics.drawImage(image, 0, 0, thumbnailWidth, thumbnailHeight, null);
		} finally {
			graphics.dispose();
		}
		return thumbnail;
	}

	private String sha256(byte[] bytes) {
		try {
			return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 digest is not available", exception);
		}
	}

	private boolean hasText(String value) {
		return value != null && !value.isBlank();
	}
}
