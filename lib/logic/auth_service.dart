import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();

  factory AuthService() => instance;

  AuthService._internal() {
    // プラグインからの通知も拾えるようにリッスン開始
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _userController.add(account);
    });
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  // 【追加】外部ライブラリ（Drive API）からインスタンスを利用できるようにするgetter
  GoogleSignIn get googleSignIn => _googleSignIn;

  // 自前で管理するストリームコントローラーを作成
  final StreamController<GoogleSignInAccount?> _userController = StreamController<GoogleSignInAccount?>.broadcast();

  // 外部にはこの自前のストリームを公開
  Stream<GoogleSignInAccount?> get userStream => _userController.stream;

  // 現在のユーザー情報
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  // サイレントサインイン
  Future<void> signInSilently() async {
    try {
      print("[AuthService] Silent Sign-in: 開始");
      final account = await _googleSignIn.signInSilently();
      // 明示的に通知
      _userController.add(account);

      if (account != null) {
        print("[AuthService] Silent Sign-in: 成功 - ${account.email}");
      } else {
        print("[AuthService] Silent Sign-in: 保存されたユーザーはいません");
      }
    } catch (e) {
      print('[AuthService] Silent Sign-in Error: $e');
    }
  }

  // サインイン（認証画面表示）
  Future<GoogleSignInAccount?> signIn() async {
    try {
      print("[AuthService] Interactive Sign-in: 開始");
      final account = await _googleSignIn.signIn();
      // 明示的に通知
      _userController.add(account);

      if (account == null) {
        print("[AuthService] Sign-in: キャンセルされました");
      } else {
        print("[AuthService] Sign-in: 成功 - ${account.email}");
      }
      return account;
    } catch (e) {
      print('[AuthService] Sign-in CRITICAL Error: $e');
      return null;
    }
  }

  // サインアウト
  Future<void> signOut() async {
    try {
      print("[AuthService] Sign-out: 開始");
      await _googleSignIn.disconnect();
      // 明示的にnull（ログアウト状態）を通知
      _userController.add(null);
      print("[AuthService] Sign-out: 完了");
    } catch (e) {
      print('[AuthService] Sign-out Error: $e');
    }
  }
}