import 'dart:io';
import 'dart:convert'; // JSON用
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'auth_service.dart';
import '../models/receipt_data.dart';
import '../database/database_helper.dart';

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();

  factory GoogleDriveService() => instance;

  GoogleDriveService._internal();

  static const String _rootFolderName = "ReceiptScanner";
  static const String _masterFileName = "receipts_master.json";

  Future<drive.DriveApi?> _getDriveApi() async {
    final googleSignIn = AuthService.instance.googleSignIn;
    if (googleSignIn.currentUser == null) return null;

    final client = await googleSignIn.authenticatedClient();
    if (client == null) return null;

    return drive.DriveApi(client);
  }

  Future<String?> _getOrCreateFolder(drive.DriveApi api, String folderName, String? parentId) async {
    try {
      String query = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";
      if (parentId != null) {
        query += " and '$parentId' in parents";
      }

      final found = await api.files.list(q: query, $fields: "files(id, name)");

      if (found.files != null && found.files!.isNotEmpty) {
        return found.files!.first.id;
      }

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

  // --- ファイル操作 ---

  Future<String?> uploadFile(File file, String fileName, DateTime date) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    final rootId = await _getOrCreateFolder(api, _rootFolderName, null);
    if (rootId == null) return null;

    final yearStr = DateFormat('yyyy').format(date);
    final yearId = await _getOrCreateFolder(api, yearStr, rootId);
    if (yearId == null) return null;

    final monthStr = DateFormat('MM').format(date);
    final monthId = await _getOrCreateFolder(api, monthStr, yearId);
    if (monthId == null) return null;

    final fileToUpload = drive.File()
      ..name = fileName
      ..parents = [monthId];

    final media = drive.Media(file.openRead(), file.lengthSync());

    try {
      final result = await api.files.create(fileToUpload, uploadMedia: media, $fields: 'id');

      // 画像UP成功時、JSONの driveFileId も更新する同期処理をここで呼ぶのがベスト
      return result.id;
    } catch (e) {
      print("Upload Error: $e");
      return null;
    }
  }

  Future<File?> downloadFile(String fileId, String savePath) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    try {
      final drive.Media file = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final saveFile = File(savePath);
      final List<int> dataStore = [];
      await for (final data in file.stream) {
        dataStore.addAll(data);
      }
      await saveFile.writeAsBytes(dataStore);
      return saveFile;
    } catch (e) {
      print("Download Error: $e");
      return null;
    }
  }

  Future<void> deleteFile(String fileId) async {
    final api = await _getDriveApi();
    if (api == null) return;
    try {
      final file = drive.File()..trashed = true;
      await api.files.update(file, fileId);
    } catch (e) {
      print("Delete Error: $e");
    }
  }

  // --- 【ここから追加】マスターデータ同期ロジック ---

  // 1. マスターJSONファイルを探して取得する
  Future<String?> _getMasterFileId(drive.DriveApi api) async {
    final rootId = await _getOrCreateFolder(api, _rootFolderName, null);
    if (rootId == null) return null;

    final query = "name = '$_masterFileName' and '$rootId' in parents and trashed = false";
    final found = await api.files.list(q: query, $fields: "files(id)");

    if (found.files != null && found.files!.isNotEmpty) {
      return found.files!.first.id;
    }
    return null; // まだない
  }

  // 2. クラウド上の全データを取得 (Pull)
  Future<List<ReceiptData>> fetchAllFromCloud() async {
    final api = await _getDriveApi();
    if (api == null) return [];

    final fileId = await _getMasterFileId(api);
    if (fileId == null) return []; // ファイルがない＝データなし

    try {
      // JSONをダウンロード
      final drive.Media file = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final List<int> dataStore = [];
      await for (final data in file.stream) {
        dataStore.addAll(data);
      }
      final jsonString = utf8.decode(dataStore);
      final List<dynamic> jsonList = jsonDecode(jsonString);

      return jsonList.map((j) => ReceiptData.fromJson(j)).toList();
    } catch (e) {
      print("JSON Fetch Error: $e");
      return [];
    }
  }

  // 3. 単件データをクラウドへ反映 (Push & Merge)
  // 保存ボタンを押した時や、画像UP完了時に呼ぶ
  Future<void> syncReceiptToCloud(ReceiptData item) async {
    final api = await _getDriveApi();
    if (api == null) return;

    final rootId = await _getOrCreateFolder(api, _rootFolderName, null);
    if (rootId == null) return;

    // 現在のマスターデータを取得（他端末の変更を取り込むため）
    List<ReceiptData> currentList = await fetchAllFromCloud();

    // リスト内で該当IDを探して更新、なければ追加
    final index = currentList.indexWhere((r) => r.id == item.id);
    if (index != -1) {
      // imagePathはクラウドに関係ないので、item(最新)の情報を使いつつ、
      // 既存のdriveFileIdがitem側でnull、クラウド側でありならクラウド側を維持するなどの配慮も可能だが、
      // 基本は「端末の操作」が最新として上書きする。
      currentList[index] = item;
    } else {
      currentList.add(item);
    }

    // JSON化してアップロード（上書き）
    await _uploadMasterJson(api, rootId, currentList);
  }

  // 4. データ削除の同期 (Delete)
  Future<void> deleteReceiptFromCloud(String id) async {
    final api = await _getDriveApi();
    if (api == null) return;

    final rootId = await _getOrCreateFolder(api, _rootFolderName, null);
    if (rootId == null) return;

    List<ReceiptData> currentList = await fetchAllFromCloud();

    // 該当IDを削除
    currentList.removeWhere((r) => r.id == id);

    await _uploadMasterJson(api, rootId, currentList);
  }

  // 内部メソッド: JSONファイルの上書き保存
  Future<void> _uploadMasterJson(drive.DriveApi api, String parentId, List<ReceiptData> list) async {
    // リストをJSON文字列に変換
    final jsonList = list.map((e) => e.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    final bytes = utf8.encode(jsonString);

    // 既存ファイルがあるか確認
    final existingId = await _getMasterFileId(api);

    final fileMetadata = drive.File()
      ..name = _masterFileName
      ..parents = (existingId == null) ? [parentId] : null; // 新規なら親指定

    final media = drive.Media(Stream.value(bytes), bytes.length);

    if (existingId != null) {
      // 更新 (update)
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    } else {
      // 新規作成 (create)
      await api.files.create(fileMetadata, uploadMedia: media);
    }
    print("Master JSON Updated.");
  }

  // 5. 【アプリ起動時】同期実行用ヘルパー
  Future<void> performFullSync() async {
    print("Starting Full Sync...");
    final cloudItems = await fetchAllFromCloud();
    if (cloudItems.isNotEmpty) {
      await DatabaseHelper.instance.mergeReceipts(cloudItems);
      print("Full Sync Completed: Merged ${cloudItems.length} items.");
    }
  }
}