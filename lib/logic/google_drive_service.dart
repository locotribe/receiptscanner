import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'auth_service.dart';

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();

  factory GoogleDriveService() => instance;

  GoogleDriveService._internal();

  // 保存先フォルダ名
  static const String _folderName = "ReceiptScanner";

  /// 認証済みのDrive APIクライアントを取得する
  Future<drive.DriveApi?> _getDriveApi() async {
    final googleSignIn = AuthService.instance.googleSignIn;
    // ログインしていない場合はnull
    if (googleSignIn.currentUser == null) return null;

    // 認証済みHTTPクライアントを生成 (extension_google_sign_in_as_googleapis_auth の機能)
    final client = await googleSignIn.authenticatedClient();
    if (client == null) return null;

    return drive.DriveApi(client);
  }

  /// 保存先フォルダのIDを取得する（なければ作成する）
  Future<String?> _getOrCreateFolderId(drive.DriveApi api) async {
    try {
      // 1. フォルダが存在するか検索
      final found = await api.files.list(
        q: "mimeType = 'application/vnd.google-apps.folder' and name = '$_folderName' and trashed = false",
        $fields: "files(id, name)",
      );

      // 2. 見つかればそのIDを返す
      if (found.files != null && found.files!.isNotEmpty) {
        return found.files!.first.id;
      }

      // 3. なければ新規作成
      final folderToCreate = drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await api.files.create(folderToCreate);
      return createdFolder.id;
    } catch (e) {
      print("Folder Error: $e");
      return null;
    }
  }

  /// ファイルをアップロードする
  /// [file]: アップロードするローカルファイル
  /// [fileName]: ドライブ上でのファイル名
  /// 戻り値: アップロードされたファイルのID (失敗時はnull)
  Future<String?> uploadFile(File file, String fileName) async {
    final api = await _getDriveApi();
    if (api == null) {
      print("Drive API Client is null (Not signed in?)");
      return null;
    }

    final folderId = await _getOrCreateFolderId(api);
    if (folderId == null) {
      print("Failed to get target folder ID");
      return null;
    }

    // アップロードするファイルのメタデータ
    final fileToUpload = drive.File()
      ..name = fileName
      ..parents = [folderId]; // 専用フォルダの中に保存

    // ファイルの中身
    final media = drive.Media(file.openRead(), file.lengthSync());

    try {
      final result = await api.files.create(
        fileToUpload,
        uploadMedia: media,
        $fields: 'id', // 結果としてIDだけ返してくれればOK
      );
      print("Upload Success: ID=${result.id}");
      return result.id;
    } catch (e) {
      print("Upload Error: $e");
      return null;
    }
  }
}