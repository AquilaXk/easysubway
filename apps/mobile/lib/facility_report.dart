import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_headers.dart';
import 'core/database/user/user_database.dart' as user_db;
import 'mobile_error_reporter.dart';
import 'secure_key_value_storage.dart';

const _facilityReportTimeout = Duration(seconds: 8);
const _facilityReportErrorMessage = '신고를 보내지 못했습니다.';
const _facilityReportStatusErrorMessage = '처리 상태를 확인하지 못했습니다.';
const _facilityReportListErrorMessage = '신고 내역을 불러오지 못했습니다.';
const _facilityReportFailureNextAction = '내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.';
const _anonymousReportUserId = 'anonymous-mobile-user';
const _facilityReportPhotoTooLargeMessage = '사진이 너무 큽니다. 다른 사진을 선택해 주세요.';
const _facilityReportLocationDisabledMessage =
    '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _facilityReportLocationRationaleTitle = '현재 위치 사용';
const _facilityReportLocationRationalePurpose =
    '가까운 역 찾기와 시설 신고 위치 확인에만 현재 위치를 사용합니다.';
const _facilityReportLocationRationaleFallback =
    '위치 권한을 거부해도 역명 검색, 즐겨찾기, 접근성 정보 조회는 계속 사용할 수 있습니다.';
const _facilityReportUploadDisclosureTitle = '사진·위치 확인';
const _facilityReportUploadDisclosurePurpose =
    '사진과 신고 위치는 시설 신고 확인과 운영 검수에만 사용됩니다.';
const _facilityReportUploadDisclosureScope =
    '신고 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.';
const _facilityReportDraftTargetStorageKey =
    'easysubway.facilityReport.draftTarget';

abstract class FacilityReportRepository {
  Future<FacilityReportResult> createReport(FacilityReportRequest request);

  Future<FacilityReportResult> getReport(String reportId);

  Future<List<FacilityReportResult>> listMyReports();
}

class FacilityReportApiRepository implements FacilityReportRepository {
  FacilityReportApiRepository({
    required this.baseUri,
    this.authProvider,
    this.receiptStore,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider? authProvider;
  final FacilityReportReceiptStore? receiptStore;
  final HttpClient _httpClient;

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest reportRequest,
  ) async {
    try {
      return await _postReportWithAuthorizationRetry(reportRequest);
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 접수 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportErrorMessage);
    }
  }

  Future<FacilityReportResult> _postReportWithAuthorizationRetry(
    FacilityReportRequest reportRequest,
  ) async {
    final preparedRequest = await _prepareReportRequest(reportRequest);
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .postUrl(baseUri.resolve('/api/v1/reports'))
          .timeout(_facilityReportTimeout);
      final authorizationHeader = await authProvider
          ?.authorizationHeader()
          .timeout(_facilityReportTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(preparedRequest.toJson()));

      final response = await request.close().timeout(_facilityReportTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 만료된 익명 인증은 비우고 새 인증으로 한 번만 다시 시도한다.
        await authProvider!.invalidateAuthorization().timeout(
          _facilityReportTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.created &&
          response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportErrorMessage);
      }

      final result = _reportResultFromBody(
        body,
        errorMessage: _facilityReportErrorMessage,
      );
      await _saveReceiptIfPresent(result);
      return result;
    }
    throw const FacilityReportException(_facilityReportErrorMessage);
  }

  Future<FacilityReportRequest> _prepareReportRequest(
    FacilityReportRequest reportRequest,
  ) async {
    final request = reportRequest.trimmed();
    if (request.photoDataBase64 == null || request.photoDataBase64!.isEmpty) {
      return request;
    }
    final clientSubmissionId = request.clientSubmissionId?.isNotEmpty == true
        ? request.clientSubmissionId!
        : _newClientSubmissionId();
    final photoBytes = base64Decode(request.photoDataBase64!);
    final photoSha256 = sha256.convert(photoBytes).toString();
    final uploadIntent = await _createPhotoUploadIntent(
      clientSubmissionId: clientSubmissionId,
      request: request,
      photoSha256: photoSha256,
      photoSizeBytes: photoBytes.length,
    );
    await _uploadPhoto(uploadIntent, request.photoContentType!, photoBytes);
    return request.withUploadedPhoto(
      clientSubmissionId: clientSubmissionId,
      photoObjectKey: uploadIntent.objectKey,
      photoSha256: photoSha256,
      photoSizeBytes: photoBytes.length,
    );
  }

  Future<FacilityReportPhotoUploadIntent> _createPhotoUploadIntent({
    required String clientSubmissionId,
    required FacilityReportRequest request,
    required String photoSha256,
    required int photoSizeBytes,
  }) async {
    final uploadRequest = await _httpClient
        .postUrl(baseUri.resolve('/api/v1/report-uploads'))
        .timeout(_facilityReportTimeout);
    uploadRequest.headers.contentType = ContentType.json;
    uploadRequest.write(
      jsonEncode({
        'clientSubmissionId': clientSubmissionId,
        'photoFileName': request.photoFileName,
        'photoContentType': request.photoContentType,
        'photoSha256': photoSha256,
        'photoSizeBytes': photoSizeBytes,
      }),
    );
    final uploadResponse = await uploadRequest.close().timeout(
      _facilityReportTimeout,
    );
    final body = await utf8
        .decodeStream(uploadResponse)
        .timeout(_facilityReportTimeout);
    if (uploadResponse.statusCode != HttpStatus.created &&
        uploadResponse.statusCode != HttpStatus.ok) {
      throw const FacilityReportException(_facilityReportErrorMessage);
    }
    return FacilityReportPhotoUploadIntent.fromBody(
      body,
      errorMessage: _facilityReportErrorMessage,
    );
  }

  Future<void> _uploadPhoto(
    FacilityReportPhotoUploadIntent uploadIntent,
    String contentType,
    List<int> photoBytes,
  ) async {
    final uploadRequest = await _httpClient
        .putUrl(uploadIntent.uploadUri(baseUri))
        .timeout(_facilityReportTimeout);
    uploadRequest.headers.contentType = ContentType.parse(contentType);
    uploadRequest.add(photoBytes);
    final uploadResponse = await uploadRequest.close().timeout(
      _facilityReportTimeout,
    );
    await uploadResponse.drain<void>();
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw const FacilityReportException(_facilityReportErrorMessage);
    }
  }

  Future<void> _saveReceiptIfPresent(FacilityReportResult result) async {
    final receiptToken = result.receiptToken;
    if (receiptToken == null || receiptToken.isEmpty || receiptStore == null) {
      return;
    }
    await receiptStore!.saveReceipt(
      FacilityReportReceipt(
        receiptId: result.id,
        reportId: result.id,
        status: result.status,
        receiptToken: receiptToken,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _newClientSubmissionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    final trimmedReportId = reportId.trim();
    if (trimmedReportId.isEmpty) {
      throw const FacilityReportException(_facilityReportStatusErrorMessage);
    }

    final uri = baseUri.resolve(
      '/api/v1/reports/${Uri.encodeComponent(trimmedReportId)}',
    );

    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(_facilityReportTimeout);
      final receiptToken = await receiptStore
          ?.receiptTokenForReport(trimmedReportId)
          .timeout(_facilityReportTimeout);
      if (receiptToken != null && receiptToken.isNotEmpty) {
        request.headers.set('X-Easysubway-Report-Receipt-Token', receiptToken);
      }
      final response = await request.close().timeout(_facilityReportTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportStatusErrorMessage);
      }

      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);
      return _reportResultFromBody(
        body,
        errorMessage: _facilityReportStatusErrorMessage,
      );
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 처리 상태 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportStatusErrorMessage);
    }
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    try {
      return await _getMyReportsWithAuthorizationRetry();
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '내 시설 신고 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportListErrorMessage);
    }
  }

  Future<List<FacilityReportResult>>
  _getMyReportsWithAuthorizationRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .getUrl(baseUri.resolve('/api/v1/me/reports'))
          .timeout(_facilityReportTimeout);
      final authorizationHeader = await authProvider
          ?.authorizationHeader()
          .timeout(_facilityReportTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }

      final response = await request.close().timeout(_facilityReportTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 목록 조회도 접수와 같은 익명 인증을 쓰므로 만료 시 한 번만 갱신한다.
        await authProvider!.invalidateAuthorization().timeout(
          _facilityReportTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportListErrorMessage);
      }

      return _reportListFromBody(
        body,
        errorMessage: _facilityReportListErrorMessage,
      );
    }
    throw const FacilityReportException(_facilityReportListErrorMessage);
  }

  FacilityReportResult _reportResultFromBody(
    String body, {
    required String errorMessage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }

    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw FacilityReportException(errorMessage);
    }

    return FacilityReportResult.fromJson(data);
  }

  List<FacilityReportResult> _reportListFromBody(
    String body, {
    required String errorMessage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }

    final data = decoded['data'];
    final items = switch (data) {
      {'items': final List<Object?> pageItems} => pageItems,
      final List<Object?> listItems => listItems,
      _ => throw FacilityReportException(errorMessage),
    };

    if (items.isEmpty) {
      return const [];
    }

    return [
      for (final item in items)
        if (item is Map<String, Object?>)
          FacilityReportResult.fromJson(item)
        else
          throw FacilityReportException(errorMessage),
    ];
  }
}

class FacilityReportException implements Exception {
  const FacilityReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FacilityReportRequest {
  const FacilityReportRequest({
    required this.userId,
    this.clientSubmissionId,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
    this.photoFileName,
    this.photoContentType,
    this.photoDataBase64,
    this.photoObjectKey,
    this.photoSha256,
    this.photoSizeBytes,
    this.latitude,
    this.longitude,
  });

  final String userId;
  final String? clientSubmissionId;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;
  final String? photoFileName;
  final String? photoContentType;
  final String? photoDataBase64;
  final String? photoObjectKey;
  final String? photoSha256;
  final int? photoSizeBytes;
  final double? latitude;
  final double? longitude;

  FacilityReportRequest trimmed() {
    return FacilityReportRequest(
      userId: userId.trim(),
      clientSubmissionId: clientSubmissionId?.trim(),
      stationId: stationId.trim(),
      facilityId: facilityId.trim(),
      reportType: reportType.trim(),
      description: description.trim(),
      photoFileName: photoFileName?.trim(),
      photoContentType: photoContentType?.trim(),
      photoDataBase64: photoDataBase64?.trim(),
      photoObjectKey: photoObjectKey?.trim(),
      photoSha256: photoSha256?.trim(),
      photoSizeBytes: photoSizeBytes,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Map<String, Object?> toJson() {
    final request = trimmed();
    final json = <String, Object?>{
      'userId': request.userId,
      'stationId': request.stationId,
      'facilityId': request.facilityId,
      'reportType': request.reportType,
      'description': request.description,
    };
    if (request.clientSubmissionId != null &&
        request.clientSubmissionId!.isNotEmpty) {
      json['clientSubmissionId'] = request.clientSubmissionId;
    }
    if (request.photoFileName != null &&
        request.photoFileName!.isNotEmpty &&
        request.photoContentType != null &&
        request.photoContentType!.isNotEmpty &&
        request.photoObjectKey != null &&
        request.photoObjectKey!.isNotEmpty &&
        request.photoSha256 != null &&
        request.photoSha256!.isNotEmpty &&
        request.photoSizeBytes != null) {
      json['photoFileName'] = request.photoFileName;
      json['photoContentType'] = request.photoContentType;
      json['photoObjectKey'] = request.photoObjectKey;
      json['photoSha256'] = request.photoSha256;
      json['photoSizeBytes'] = request.photoSizeBytes;
    }
    // 좌표 한쪽만 저장되면 현장 위치를 잘못 해석할 수 있어 한 쌍일 때만 보낸다.
    if (request.latitude != null && request.longitude != null) {
      json['latitude'] = request.latitude;
      json['longitude'] = request.longitude;
    }
    return json;
  }

  FacilityReportRequest withUploadedPhoto({
    required String clientSubmissionId,
    required String photoObjectKey,
    required String photoSha256,
    required int photoSizeBytes,
  }) {
    final request = trimmed();
    return FacilityReportRequest(
      userId: request.userId,
      clientSubmissionId: clientSubmissionId,
      stationId: request.stationId,
      facilityId: request.facilityId,
      reportType: request.reportType,
      description: request.description,
      photoFileName: request.photoFileName,
      photoContentType: request.photoContentType,
      photoObjectKey: photoObjectKey,
      photoSha256: photoSha256,
      photoSizeBytes: photoSizeBytes,
      latitude: request.latitude,
      longitude: request.longitude,
    );
  }
}

class FacilityReportPhotoUploadIntent {
  const FacilityReportPhotoUploadIntent({
    required this.objectKey,
    required this.uploadUrl,
    required this.uploadMethod,
  });

  factory FacilityReportPhotoUploadIntent.fromBody(
    String body, {
    required String errorMessage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw FacilityReportException(errorMessage);
    }
    return FacilityReportPhotoUploadIntent(
      objectKey: _requiredReportString(data, 'objectKey'),
      uploadUrl: _requiredReportString(data, 'uploadUrl'),
      uploadMethod: _requiredReportString(data, 'uploadMethod'),
    );
  }

  final String objectKey;
  final String uploadUrl;
  final String uploadMethod;

  Uri uploadUri(Uri baseUri) {
    final parsed = Uri.parse(uploadUrl);
    if (parsed.hasScheme) {
      return parsed;
    }
    return baseUri.resolve(uploadUrl);
  }
}

class FacilityReportReceipt {
  const FacilityReportReceipt({
    required this.receiptId,
    required this.reportId,
    required this.status,
    required this.receiptToken,
    required this.createdAt,
  });

  final String receiptId;
  final String reportId;
  final String status;
  final String receiptToken;
  final DateTime createdAt;
}

abstract interface class FacilityReportReceiptStore {
  Future<void> saveReceipt(FacilityReportReceipt receipt);

  Future<String?> receiptTokenForReport(String reportId);
}

class DriftFacilityReportReceiptStore implements FacilityReportReceiptStore {
  const DriftFacilityReportReceiptStore({
    required this.userDatabase,
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final user_db.UserDatabase userDatabase;
  final SecureKeyValueStorage storage;

  @override
  Future<void> saveReceipt(FacilityReportReceipt receipt) async {
    final secureKey = 'easysubway.facilityReport.receipt.${receipt.receiptId}';
    await storage.write(key: secureKey, value: receipt.receiptToken);
    await userDatabase
        .into(userDatabase.reportReceipts)
        .insertOnConflictUpdate(
          user_db.ReportReceiptsCompanion.insert(
            receiptId: receipt.receiptId,
            reportId: Value(receipt.reportId),
            status: receipt.status,
            createdAt: receipt.createdAt,
          ),
        );
  }

  @override
  Future<String?> receiptTokenForReport(String reportId) async {
    final trimmedReportId = reportId.trim();
    if (trimmedReportId.isEmpty) {
      return null;
    }
    final directToken = await storage.read(
      key: 'easysubway.facilityReport.receipt.$trimmedReportId',
    );
    if (directToken != null && directToken.isNotEmpty) {
      return directToken;
    }
    final receipt = await (userDatabase.select(
      userDatabase.reportReceipts,
    )..where((row) => row.reportId.equals(trimmedReportId))).getSingleOrNull();
    if (receipt == null) {
      return null;
    }
    return storage.read(
      key: 'easysubway.facilityReport.receipt.${receipt.receiptId}',
    );
  }
}

class FacilityReportPhotoAttachment {
  const FacilityReportPhotoAttachment({
    required this.fileName,
    required this.contentType,
    required this.dataBase64,
  });

  final String fileName;
  final String contentType;
  final String dataBase64;
}

class FacilityReportPhotoException implements Exception {
  const FacilityReportPhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FacilityReportLocation {
  const FacilityReportLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class FacilityReportLocationException implements Exception {
  const FacilityReportLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef FacilityReportLocationLoader =
    Future<FacilityReportLocation> Function();

typedef FacilityReportLocationPermissionRequestChecker =
    Future<bool> Function();

typedef FacilityReportLocationSettingsOpener = Future<bool> Function();

typedef FacilityReportPhotoPicker =
    Future<FacilityReportPhotoAttachment?> Function();

typedef FacilityReportLostPhotoRestorer =
    Future<FacilityReportPhotoAttachment?> Function();

class ImagePickerFacilityReportPhotoPicker {
  ImagePickerFacilityReportPhotoPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const int _maxPhotoBytes = 900 * 1024;
  static const double _maxPhotoDimension = 1600;
  static const int _imageQuality = 72;

  final ImagePicker _imagePicker;

  Future<FacilityReportPhotoAttachment?> pickFromGallery() {
    return _pick(ImageSource.gallery);
  }

  Future<FacilityReportPhotoAttachment?> takePhoto() {
    return _pick(ImageSource.camera);
  }

  Future<FacilityReportPhotoAttachment?> retrieveLostPhoto() async {
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) {
      return null;
    }
    if (response.exception != null) {
      throw const FacilityReportPhotoException('사진을 다시 선택해 주세요.');
    }
    if (response.type != RetrieveType.image || response.file == null) {
      return null;
    }
    return _attachmentFromFile(response.file!);
  }

  Future<FacilityReportPhotoAttachment?> _pick(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: _maxPhotoDimension,
      maxHeight: _maxPhotoDimension,
      imageQuality: _imageQuality,
    );
    if (image == null) {
      return null;
    }
    return _attachmentFromFile(image);
  }

  Future<FacilityReportPhotoAttachment> _attachmentFromFile(XFile image) async {
    final bytes = await image.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const FacilityReportPhotoException(
        _facilityReportPhotoTooLargeMessage,
      );
    }
    return FacilityReportPhotoAttachment(
      fileName: image.name.isEmpty ? 'facility-report.jpg' : image.name,
      contentType: _contentTypeFromName(image.name),
      dataBase64: base64Encode(bytes),
    );
  }

  String _contentTypeFromName(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

class FacilityReportResult {
  const FacilityReportResult({
    required this.id,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
    required this.status,
    required this.createdAt,
    this.receiptToken,
  });

  factory FacilityReportResult.fromJson(Map<String, Object?> json) {
    return FacilityReportResult(
      id: _requiredReportString(json, 'id'),
      stationId: _requiredReportString(json, 'stationId'),
      facilityId: _requiredReportString(json, 'facilityId'),
      reportType: _requiredReportString(json, 'reportType'),
      description: _optionalReportString(json, 'description'),
      status: _requiredReportString(json, 'status'),
      createdAt: _requiredReportString(json, 'createdAt'),
      receiptToken: _optionalReportString(json, 'receiptToken'),
    );
  }

  final String id;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;
  final String status;
  final String createdAt;
  final String? receiptToken;

  String get statusLabel {
    return switch (status) {
      'SUBMITTED' => '접수됨',
      'UNDER_REVIEW' => '확인 중',
      'ACCEPTED' => '반영됨',
      'REJECTED' => '반려됨',
      'DUPLICATE' => '중복 신고',
      'RESOLVED' => '처리 완료',
      _ => '접수 상태 확인 필요',
    };
  }

  String get reportTypeLabel {
    return switch (reportType) {
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'LOCATION_WRONG' => '위치가 달라요',
      'INFORMATION_WRONG' => '정보가 달라요',
      'RECOVERED' => '다시 정상',
      _ => '시설 신고',
    };
  }
}

class FacilityReportTarget {
  const FacilityReportTarget({
    required this.stationId,
    required this.stationName,
    required this.facilityId,
    required this.facilityName,
    required this.facilityTypeLabel,
    required this.facilityStatusLabel,
  });

  factory FacilityReportTarget.fromJson(Map<String, Object?> json) {
    return FacilityReportTarget(
      stationId: _requiredReportString(json, 'stationId'),
      stationName: _requiredReportString(json, 'stationName'),
      facilityId: _requiredReportString(json, 'facilityId'),
      facilityName: _requiredReportString(json, 'facilityName'),
      facilityTypeLabel: _requiredReportString(json, 'facilityTypeLabel'),
      facilityStatusLabel: _requiredReportString(json, 'facilityStatusLabel'),
    );
  }

  factory FacilityReportTarget.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid facility report target payload');
    }
    return FacilityReportTarget.fromJson(decoded);
  }

  final String stationId;
  final String stationName;
  final String facilityId;
  final String facilityName;
  final String facilityTypeLabel;
  final String facilityStatusLabel;

  Map<String, Object?> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'facilityId': facilityId,
      'facilityName': facilityName,
      'facilityTypeLabel': facilityTypeLabel,
      'facilityStatusLabel': facilityStatusLabel,
    };
  }

  String encode() => jsonEncode(toJson());
}

abstract class FacilityReportDraftTargetStore {
  Future<FacilityReportTarget?> readTarget();

  Future<void> saveTarget(FacilityReportTarget target);

  Future<void> clearTarget();
}

class SecureFacilityReportDraftTargetStore
    implements FacilityReportDraftTargetStore {
  const SecureFacilityReportDraftTargetStore({
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final SecureKeyValueStorage storage;

  @override
  Future<FacilityReportTarget?> readTarget() async {
    try {
      final value = await storage.read(
        key: _facilityReportDraftTargetStorageKey,
      );
      if (value == null) {
        return null;
      }
      return FacilityReportTarget.decode(value);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '저장된 시설 신고 대상을 읽는 중 예외가 발생했습니다.',
      );
      await _clearTargetAfterReadFailure();
      return null;
    }
  }

  @override
  Future<void> saveTarget(FacilityReportTarget target) async {
    await storage.write(
      key: _facilityReportDraftTargetStorageKey,
      value: target.encode(),
    );
  }

  @override
  Future<void> clearTarget() async {
    await storage.delete(key: _facilityReportDraftTargetStorageKey);
  }

  Future<void> _clearTargetAfterReadFailure() async {
    try {
      await clearTarget();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '손상된 시설 신고 대상을 지우는 중 예외가 발생했습니다.',
      );
    }
  }
}

enum FacilityReportTypeOption {
  broken,
  underConstruction,
  closed,
  locationWrong,
  informationWrong,
  recovered,
}

extension FacilityReportTypeOptionLabel on FacilityReportTypeOption {
  String get reportType {
    return switch (this) {
      FacilityReportTypeOption.broken => 'BROKEN',
      FacilityReportTypeOption.underConstruction => 'UNDER_CONSTRUCTION',
      FacilityReportTypeOption.closed => 'CLOSED',
      FacilityReportTypeOption.locationWrong => 'LOCATION_WRONG',
      FacilityReportTypeOption.informationWrong => 'INFORMATION_WRONG',
      FacilityReportTypeOption.recovered => 'RECOVERED',
    };
  }

  String get label {
    return switch (this) {
      FacilityReportTypeOption.broken => '고장',
      FacilityReportTypeOption.underConstruction => '공사 중',
      FacilityReportTypeOption.closed => '폐쇄',
      FacilityReportTypeOption.locationWrong => '위치가 달라요',
      FacilityReportTypeOption.informationWrong => '정보가 달라요',
      FacilityReportTypeOption.recovered => '다시 정상',
    };
  }

  IconData get icon {
    return switch (this) {
      FacilityReportTypeOption.broken => Icons.warning_amber_rounded,
      FacilityReportTypeOption.underConstruction => Icons.construction,
      FacilityReportTypeOption.closed => Icons.block,
      FacilityReportTypeOption.locationWrong => Icons.wrong_location_outlined,
      FacilityReportTypeOption.informationWrong => Icons.edit_note,
      FacilityReportTypeOption.recovered => Icons.check_circle_outline,
    };
  }
}

enum FacilityReportViewStatus { idle, loading, success, failure }

class FacilityReportState {
  const FacilityReportState({
    required this.status,
    this.message = '',
    this.result,
  });

  const FacilityReportState.idle()
    : status = FacilityReportViewStatus.idle,
      message = '',
      result = null;

  final FacilityReportViewStatus status;
  final String message;
  final FacilityReportResult? result;
}

class FacilityReportController extends ChangeNotifier {
  FacilityReportController({required this.repository});

  final FacilityReportRepository repository;

  FacilityReportState _state = const FacilityReportState.idle();
  bool _disposed = false;

  FacilityReportState get state => _state;

  Future<void> submit({
    required FacilityReportTarget target,
    required FacilityReportTypeOption selectedType,
    required String description,
    FacilityReportPhotoAttachment? photoAttachment,
    double? latitude,
    double? longitude,
  }) async {
    if (_disposed || _state.status == FacilityReportViewStatus.loading) {
      return;
    }

    _emitState(
      const FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '신고 보내는 중',
      ),
    );

    try {
      final result = await repository.createReport(
        FacilityReportRequest(
          userId: _anonymousReportUserId,
          stationId: target.stationId,
          facilityId: target.facilityId,
          reportType: selectedType.reportType,
          description: description,
          photoFileName: photoAttachment?.fileName,
          photoContentType: photoAttachment?.contentType,
          photoDataBase64: photoAttachment?.dataBase64,
          latitude: latitude,
          longitude: longitude,
        ),
      );
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '신고가 접수되었습니다.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 화면 제출 처리 중 예외가 발생했습니다.',
      );
      _emitState(
        const FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: _facilityReportErrorMessage,
        ),
      );
    }
  }

  Future<void> refreshCurrentReport() async {
    final currentResult = _state.result;
    if (_disposed ||
        _state.status == FacilityReportViewStatus.loading ||
        currentResult == null) {
      return;
    }

    _emitState(
      FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '처리 상태 확인 중',
        result: currentResult,
      ),
    );

    try {
      final result = await repository.getReport(currentResult.id);
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '처리 상태를 확인했습니다.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      // 상태 확인이 실패해도 사용자가 접수번호를 잃지 않도록 직전 결과는 유지한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
          result: currentResult,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 처리 상태 새로고침 중 예외가 발생했습니다.',
      );
      // 알 수 없는 오류도 같은 화면에서 다시 확인할 수 있게 접수 결과를 보존한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: '처리 상태를 확인하지 못했습니다.',
          result: currentResult,
        ),
      );
    }
  }

  void _emitState(FacilityReportState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class FacilityReportScreen extends StatefulWidget {
  const FacilityReportScreen({
    required this.repository,
    required this.target,
    this.locationLoader,
    this.needsLocationPermissionRequest,
    this.openLocationSettings,
    this.photoPicker,
    this.lostPhotoRestorer,
    this.draftTargetStore,
    this.initialPhotoAttachment,
    super.key,
  });

  final FacilityReportRepository repository;
  final FacilityReportTarget target;
  final FacilityReportLocationLoader? locationLoader;
  final FacilityReportLocationPermissionRequestChecker?
  needsLocationPermissionRequest;
  final FacilityReportLocationSettingsOpener? openLocationSettings;
  final FacilityReportPhotoPicker? photoPicker;
  final FacilityReportLostPhotoRestorer? lostPhotoRestorer;
  final FacilityReportDraftTargetStore? draftTargetStore;
  final FacilityReportPhotoAttachment? initialPhotoAttachment;

  @override
  State<FacilityReportScreen> createState() => _FacilityReportScreenState();
}

class MyFacilityReportListScreen extends StatefulWidget {
  const MyFacilityReportListScreen({required this.repository, super.key});

  final FacilityReportRepository repository;

  @override
  State<MyFacilityReportListScreen> createState() =>
      _MyFacilityReportListScreenState();
}

class _MyFacilityReportListScreenState
    extends State<MyFacilityReportListScreen> {
  late Future<List<FacilityReportResult>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = widget.repository.listMyReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 신고')),
      body: SafeArea(
        child: FutureBuilder<List<FacilityReportResult>>(
          future: _reportsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _MyReportLoading();
            }
            if (snapshot.hasError) {
              return _MyReportError(onRetry: _retry);
            }

            final reports = snapshot.data ?? const <FacilityReportResult>[];
            if (reports.isEmpty) {
              return const _MyReportEmpty();
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _MyReportListItem(report: reports[index]);
              },
            );
          },
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _reportsFuture = widget.repository.listMyReports();
    });
  }
}

class _MyReportLoading extends StatelessWidget {
  const _MyReportLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '신고 내역 불러오는 중',
      liveRegion: true,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MyReportEmpty extends StatelessWidget {
  const _MyReportEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '접수한 신고가 없습니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _MyReportError extends StatelessWidget {
  const _MyReportError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _facilityReportListErrorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('myReportsRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReportListItem extends StatelessWidget {
  const _MyReportListItem({required this.report});

  final FacilityReportResult report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = report.description.isEmpty
        ? report.reportTypeLabel
        : report.description;
    final createdAtLabel = _reportDateLabel(report.createdAt);
    void openReportDetail() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyFacilityReportDetailScreen(report: report),
        ),
      );
    }

    return Semantics(
      label:
          '내 신고, ${report.reportTypeLabel}, 접수번호 ${report.id}, ${report.statusLabel}, $description, 접수일 $createdAtLabel',
      button: true,
      onTap: openReportDetail,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFD5E2E4)),
          ),
          child: InkWell(
            key: Key('myReport-${report.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: openReportDetail,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          report.reportTypeLabel,
                          style: textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF102A2C),
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MyReportStatusPill(label: report.statusLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _MyReportMetaText(label: '접수번호', value: report.id),
                      _MyReportMetaText(label: '접수일', value: createdAtLabel),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyFacilityReportDetailScreen extends StatelessWidget {
  const MyFacilityReportDetailScreen({required this.report, super.key});

  final FacilityReportResult report;

  @override
  Widget build(BuildContext context) {
    final description = report.description.isEmpty
        ? report.reportTypeLabel
        : report.description;
    final createdAtLabel = _reportDateLabel(report.createdAt);

    return Scaffold(
      appBar: AppBar(title: const Text('신고 상세')),
      body: SafeArea(
        child: Semantics(
          label:
              '내 신고 상세, ${report.reportTypeLabel}, 현재 상태 ${report.statusLabel}, 접수번호 ${report.id}',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                report.reportTypeLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              _MyReportDetailStatus(label: report.statusLabel),
              const SizedBox(height: 24),
              _MyReportDetailRow(label: '접수번호', value: report.id),
              const Divider(height: 32),
              _MyReportDetailRow(label: '접수일', value: createdAtLabel),
              const Divider(height: 32),
              _MyReportDetailRow(label: '신고 내용', value: description),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyReportDetailStatus extends StatelessWidget {
  const _MyReportDetailStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE6F2F0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF93C7C2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyReportDetailRow extends StatelessWidget {
  const _MyReportDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF29484B),
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _MyReportStatusPill extends StatelessWidget {
  const _MyReportStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C7C2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _MyReportMetaText extends StatelessWidget {
  const _MyReportMetaText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF29484B),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }
}

class _FacilityReportScreenState extends State<FacilityReportScreen> {
  late final FacilityReportController _controller;
  late final ImagePickerFacilityReportPhotoPicker _defaultPhotoPicker;
  final TextEditingController _descriptionController = TextEditingController();
  FacilityReportTypeOption _selectedType = FacilityReportTypeOption.broken;
  FacilityReportLocation? _attachedLocation;
  FacilityReportPhotoAttachment? _photoAttachment;
  String _photoMessage = '';
  String _locationMessage = '';
  bool _isLoadingLocation = false;
  bool _isLocationFailure = false;
  bool _isOpeningLocationSettings = false;
  bool _isPhotoFailure = false;
  bool _isConfirmingPhotoUse = false;
  bool _isPickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _controller = FacilityReportController(repository: widget.repository)
      ..addListener(_onReportStateChanged);
    _defaultPhotoPicker = ImagePickerFacilityReportPhotoPicker();
    _photoAttachment = widget.initialPhotoAttachment;
    if (_photoAttachment != null) {
      _photoMessage = '사진 1장 추가됨';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_restoreLostPhoto());
        unawaited(_requestCurrentLocation());
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onReportStateChanged);
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final isLoading = state.status == FacilityReportViewStatus.loading;
    final reportResult = state.result;
    final hasSubmittedReport = reportResult != null;
    // 현장 좌표가 없으면 역·시설 판단이 흔들릴 수 있어 위치 확인 전 제출을 막는다.
    final isSubmitDisabled =
        isLoading ||
        hasSubmittedReport ||
        _isLoadingLocation ||
        _isLocationFailure ||
        (widget.locationLoader != null && _attachedLocation == null);

    return Scaffold(
      appBar: AppBar(title: const Text('시설 신고')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _FacilityReportHeader(target: widget.target),
            const SizedBox(height: 24),
            const _FacilityReportSectionTitle(title: '무엇을 알려드릴까요?'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in FacilityReportTypeOption.values)
                      SizedBox(
                        width: cardWidth,
                        child: _FacilityReportTypeCard(
                          option: option,
                          selected: option == _selectedType,
                          onTap: isLoading || hasSubmittedReport
                              ? null
                              : () => setState(() => _selectedType = option),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('facilityReportDescriptionInput'),
              controller: _descriptionController,
              enabled: !isLoading && !hasSubmittedReport,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(fontSize: 18, height: 1.35),
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '상황을 짧게 적어 주세요',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('facilityReportAddPhotoButton'),
              onPressed:
                  isLoading ||
                      hasSubmittedReport ||
                      _isConfirmingPhotoUse ||
                      _isPickingPhoto
                  ? null
                  : _pickPhoto,
              icon: _isPickingPhoto
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.add_a_photo),
              label: Text(_photoAttachment == null ? '사진 추가' : '사진 바꾸기'),
            ),
            if (_photoMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              _FacilityReportLocationMessage(
                message: _photoMessage,
                isFailure: _isPhotoFailure,
              ),
            ],
            if (_locationMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              _FacilityReportLocationMessage(
                message: _locationMessage,
                isFailure: _isLocationFailure,
              ),
              if (_isLocationFailure && !hasSubmittedReport) ...[
                const SizedBox(height: 10),
                if (_canOpenLocationSettings) ...[
                  OutlinedButton.icon(
                    key: const Key('facilityReportOpenLocationSettingsButton'),
                    onPressed:
                        isLoading ||
                            _isOpeningLocationSettings ||
                            _isLoadingLocation
                        ? null
                        : _openLocationSettings,
                    icon: _isOpeningLocationSettings
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.settings),
                    label: const Text('위치 설정 열기'),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  key: const Key('facilityReportRetryLocationButton'),
                  onPressed:
                      isLoading ||
                          _isOpeningLocationSettings ||
                          _isLoadingLocation
                      ? null
                      : _requestCurrentLocation,
                  icon: _isLoadingLocation
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('위치 다시 확인'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (state.message.isNotEmpty) _FacilityReportMessage(state: state),
            const SizedBox(height: 16),
            if (reportResult != null) ...[
              _FacilityReportStatusPanel(
                result: reportResult,
                isLoading: isLoading,
                onRefresh: _controller.refreshCurrentReport,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              key: const Key('facilityReportSubmitButton'),
              onPressed: isSubmitDisabled ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send),
              label: Text(hasSubmittedReport ? '접수 완료' : '신고 보내기'),
            ),
          ],
        ),
      ),
    );
  }

  void _onReportStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canOpenLocationSettings =>
      widget.openLocationSettings != null &&
      _locationMessage == _facilityReportLocationDisabledMessage;

  Future<void> _submit() async {
    if (_photoAttachment != null || _attachedLocation != null) {
      final confirmed = await _confirmReportUpload();
      if (!confirmed) {
        return;
      }
    }
    _controller.submit(
      target: widget.target,
      selectedType: _selectedType,
      description: _descriptionController.text,
      photoAttachment: _photoAttachment,
      latitude: _attachedLocation?.latitude,
      longitude: _attachedLocation?.longitude,
    );
  }

  Future<bool> _confirmReportUpload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_facilityReportUploadDisclosureTitle),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_facilityReportUploadDisclosurePurpose),
            SizedBox(height: 8),
            Text(_facilityReportUploadDisclosureScope),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmPhotoUse() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 확인'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('사진은 신고 확인에만 사용됩니다.'),
            SizedBox(height: 8),
            Text('얼굴이나 전화번호가 보이면 가려 주세요.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('계속'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _requestCurrentLocation() async {
    if (widget.locationLoader == null || _isLoadingLocation) {
      return;
    }
    final shouldContinue = await _confirmLocationUseIfNeeded();
    if (!shouldContinue) {
      if (mounted) {
        setState(() {
          _attachedLocation = null;
          _locationMessage = '위치 안내를 확인한 뒤 신고 위치를 첨부해 주세요.';
          _isLocationFailure = true;
        });
      }
      return;
    }
    await _loadCurrentLocation();
  }

  Future<bool> _confirmLocationUseIfNeeded() async {
    final checker = widget.needsLocationPermissionRequest;
    if (checker == null) {
      return true;
    }
    var needsPermissionRequest = true;
    try {
      needsPermissionRequest = await checker();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 위치 권한 사전 확인 중 예외가 발생했습니다.',
      );
    }
    if (!needsPermissionRequest) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(_facilityReportLocationRationaleTitle),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_facilityReportLocationRationalePurpose),
                SizedBox(height: 8),
                Text(_facilityReportLocationRationaleFallback),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('계속'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openLocationSettings() async {
    final openLocationSettings = widget.openLocationSettings;
    if (openLocationSettings == null || _isOpeningLocationSettings) {
      return;
    }
    setState(() => _isOpeningLocationSettings = true);
    try {
      await openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningLocationSettings = false);
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_isConfirmingPhotoUse || _isPickingPhoto) {
      return;
    }
    setState(() => _isConfirmingPhotoUse = true);
    final confirmed = await _confirmPhotoUse();
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      setState(() => _isConfirmingPhotoUse = false);
      return;
    }
    setState(() {
      _isConfirmingPhotoUse = false;
      _isPickingPhoto = true;
      _photoMessage = '';
      _isPhotoFailure = false;
    });
    try {
      await _saveDraftTargetForPhotoPicker();
      final picker = widget.photoPicker ?? _pickPhotoWithDevicePicker;
      final photo = await picker();
      if (!mounted || photo == null) {
        return;
      }
      setState(() {
        _photoAttachment = photo;
        _photoMessage = '사진 1장 추가됨';
        _isPhotoFailure = false;
      });
    } on FacilityReportPhotoException catch (error) {
      if (mounted) {
        setState(() {
          _photoAttachment = null;
          _photoMessage = error.message;
          _isPhotoFailure = true;
        });
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 사진 첨부 중 예외가 발생했습니다.',
      );
      if (mounted) {
        setState(() {
          _photoAttachment = null;
          _photoMessage = '사진을 추가하지 못했습니다.';
          _isPhotoFailure = true;
        });
      }
    } finally {
      await _clearDraftTargetForPhotoPicker();
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _restoreLostPhoto() async {
    if (_photoAttachment != null) {
      return;
    }
    final restorer = widget.lostPhotoRestorer;
    if (restorer == null) {
      return;
    }
    try {
      final photo = await restorer();
      if (!mounted || photo == null || _photoAttachment != null) {
        return;
      }
      setState(() {
        _photoAttachment = photo;
        _photoMessage = '사진 1장 추가됨';
        _isPhotoFailure = false;
      });
    } on FacilityReportPhotoException catch (error) {
      if (mounted) {
        setState(() {
          _photoMessage = error.message;
          _isPhotoFailure = true;
        });
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 사진 선택 복구 중 예외가 발생했습니다.',
      );
      if (mounted) {
        setState(() {
          _photoMessage = '사진을 다시 선택해 주세요.';
          _isPhotoFailure = true;
        });
      }
    }
  }

  Future<void> _saveDraftTargetForPhotoPicker() async {
    try {
      await widget.draftTargetStore?.saveTarget(widget.target);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 사진 선택 대상 저장 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _clearDraftTargetForPhotoPicker() async {
    try {
      await widget.draftTargetStore?.clearTarget();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 사진 선택 대상 정리 중 예외가 발생했습니다.',
      );
    }
  }

  Future<FacilityReportPhotoAttachment?> _pickPhotoWithDevicePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('사진 찍기'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('앨범에서 선택'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    return switch (source) {
      ImageSource.camera => _defaultPhotoPicker.takePhoto(),
      ImageSource.gallery => _defaultPhotoPicker.pickFromGallery(),
      null => null,
    };
  }

  Future<void> _loadCurrentLocation() async {
    final locationLoader = widget.locationLoader;
    if (locationLoader == null || _isLoadingLocation) {
      return;
    }
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = '';
      _isLocationFailure = false;
    });

    try {
      final location = await locationLoader();
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = location;
        _locationMessage = '';
        _isLocationFailure = false;
      });
    } on FacilityReportLocationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = null;
        _locationMessage = error.message;
        _isLocationFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 현재 위치 확인 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = null;
        _locationMessage = '현재 위치를 확인하지 못했습니다.';
        _isLocationFailure = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }
}

class _FacilityReportStatusPanel extends StatelessWidget {
  const _FacilityReportStatusPanel({
    required this.result,
    required this.isLoading,
    required this.onRefresh,
  });

  final FacilityReportResult result;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C7C2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              // 접수번호와 상태를 한 문장으로 묶어 스크린리더가 상태 변화를 읽게 한다.
              label: '신고 접수번호 ${result.id}, 현재 상태 ${result.statusLabel}',
              liveRegion: true,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FacilityReportStatusRow(label: '접수번호', value: result.id),
                    const SizedBox(height: 10),
                    _FacilityReportStatusRow(
                      label: '처리 상태',
                      value: result.statusLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('facilityReportRefreshButton'),
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(isLoading ? '확인 중' : '처리 상태 확인'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityReportStatusRow extends StatelessWidget {
  const _FacilityReportStatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: const Color(0xFF29484B),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _FacilityReportHeader extends StatelessWidget {
  const _FacilityReportHeader({required this.target});

  final FacilityReportTarget target;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label:
          '${target.stationName}역, ${target.facilityName}, ${target.facilityTypeLabel}, 현재 ${target.facilityStatusLabel}',
      header: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${target.stationName}역',
              style: textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              target.facilityName,
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${target.facilityTypeLabel} · ${target.facilityStatusLabel}',
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityReportSectionTitle extends StatelessWidget {
  const _FacilityReportSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFF102A2C),
          fontWeight: FontWeight.w900,
          height: 1.25,
        ),
      ),
    );
  }
}

class _FacilityReportTypeCard extends StatelessWidget {
  const _FacilityReportTypeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FacilityReportTypeOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF006D77) : const Color(0xFFD5E2E4);
    final textColor = selected ? Colors.white : const Color(0xFF102A2C);
    final semanticsLabel = '${option.label} ${selected ? '선택됨' : '선택 가능'}';

    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? color : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: color, width: 1.5),
          ),
          child: InkWell(
            key: Key('facilityReportType-${option.reportType}'),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(option.icon, color: textColor, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        option.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FacilityReportMessage extends StatelessWidget {
  const _FacilityReportMessage({required this.state});

  final FacilityReportState state;

  @override
  Widget build(BuildContext context) {
    final isFailure = state.status == FacilityReportViewStatus.failure;
    final color = isFailure ? const Color(0xFF8A4B00) : const Color(0xFF006D77);
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;
    final shouldShowNextAction = _shouldShowFacilityReportFailureNextAction(
      state,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: state.message,
          liveRegion: true,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shouldShowNextAction) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('facilityReportFailureNextAction'),
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: '다음 행동, $_facilityReportFailureNextAction',
            child: Text(
              _facilityReportFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF506B6F),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

bool _shouldShowFacilityReportFailureNextAction(FacilityReportState state) {
  return state.status == FacilityReportViewStatus.failure &&
      state.result == null;
}

class _FacilityReportLocationMessage extends StatelessWidget {
  const _FacilityReportLocationMessage({
    required this.message,
    required this.isFailure,
  });

  final String message;
  final bool isFailure;

  @override
  Widget build(BuildContext context) {
    final color = isFailure ? const Color(0xFF8A4B00) : const Color(0xFF006D77);
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;

    return Semantics(
      label: message,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _requiredReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required report field: $key');
}

String _optionalReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  return '';
}

String _reportDateLabel(String createdAt) {
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) {
    return createdAt;
  }
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}.$month.$day';
}
