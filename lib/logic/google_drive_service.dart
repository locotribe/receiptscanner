import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart'; // 日付フォーマット用に必要
import 'auth_service.dart';

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();

  factory GoogleDriveService() => instance;

  GoogleDriveService._internal();

  static const String _rootFolderName = "ReceiptScanner";

  Future<drive.DriveApi?> _getDriveApi() async {
    final googleSignIn = AuthService.instance.googleSignIn;
    if (googleSignIn.currentUser == null) return null;

    final client = await googleSignIn.authenticatedClient();
    if (client == null) return null;

    return drive.DriveApi(client);
  }

  /// 指定した親フォルダの中に、指定した名前のフォルダを取得（なければ作成）する
  /// [parentId] が null の場合はルート直下を探します
  Future<String?> _getOrCreateFolder(drive.DriveApi api, String folderName, String? parentId) async {
    try {
      // 検索クエリの構築
      String query = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";
      if (parentId != null) {
        query += " and '$parentId' in parents";
      }

      final found = await api.files.list(
        q: query,
        $fields: "files(id, name)",
      );

      if (found.files != null && found.files!.isNotEmpty) {
        return found.files!.first.id;
      }

      // 新規作成
      final folderToCreate = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      if (parentId != null) {
        folderToCreate.parents = [parentId];
      }

      final createdFolder = await api.files.create(folderToCreate);
      return createdFolder.id;
    } catch (e) {
      print("Folder Error ($folderName): $e");
      return null;
    }
  }

  /// ファイルをアップロードする (年/月フォルダ対応版)
  Future<String?> uploadFile(File file, String fileName, DateTime date) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    // 1. ルートフォルダ (ReceiptScanner)
    final rootId = await _getOrCreateFolder(api, _rootFolderName, null);
    if (rootId == null) return null;

    // 2. 年フォルダ (例: 2025)
    final yearStr = DateFormat('yyyy').format(date);
    final yearId = await _getOrCreateFolder(api, yearStr, rootId);
    if (yearId == null) return null;

    // 3. 月フォルダ (例: 01)
    final monthStr = DateFormat('MM').format(date);
    final monthId = await _getOrCreateFolder(api, monthStr, yearId);
    if (monthId == null) return null;

    // 4. ファイルのアップロード
    final fileToUpload = drive.File()
      ..name = fileName
      ..parents = [monthId]; // 月フォルダの中に保存

    final media = drive.Media(file.openRead(), file.lengthSync());

    try {
      final result = await api.files.create(
        fileToUpload,
        uploadMedia: media,
        $fields: 'id',
      );
      print("Upload Success: ID=${result.id} in $yearStr/$monthStr");
      return result.id;
    } catch (e) {
      print("Upload Error: $e");
      return null;
    }
  }
// 【追加】指定したIDのファイルをゴミ箱に移動する（削除）
  Future<void> deleteFile(String fileId) async {
    final api = await _getDriveApi();
    if (api == null) return;

    try {
      // deleteメソッドを呼ぶと完全に削除されますが、
      // 安全のため trash (ゴミ箱) フラグを立てる形にするupdateを使うのが一般的です。
      // ですが、Drive API v3では update で trashed=true にします。

      final file = drive.File()..trashed = true;
      await api.files.update(file, fileId);

      print("File trashed: ID=$fileId");
    } catch (e) {
      print("Delete Error: $e");
      // 既に削除されている場合などはエラーになるが、進行には影響させない
    }
  }

  // 【追加】ファイルをダウンロードする
  // [fileId]: ドライブ上のファイルID
  // [savePath]: 保存先のローカルパス
  Future<File?> downloadFile(String fileId, String savePath) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    try {
      final drive.Media file = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final saveFile = File(savePath);
      final List<int> dataStore = [];

      await for (final data in file.stream) {
        dataStore.addAll(data);
      }

      await saveFile.writeAsBytes(dataStore);
      print("Download Success: $savePath");
      return saveFile;
    } catch (e) {
      print("Download Error: $e");
      return null;
    }
  }
}