import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../logic/auth_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: StreamBuilder<GoogleSignInAccount?>(
        stream: AuthService.instance.userStream,
        // 【重要】ここを追加：現在の状態を初期値として渡す
        initialData: AuthService.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          final isSignedIn = user != null;

          // デバッグ用ログ
          if (isSignedIn) {
            print('AppDrawer: ログイン済み - ${user.displayName}');
          } else {
            print('AppDrawer: 未ログイン');
          }

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                accountName: Text(
                  isSignedIn ? (user.displayName ?? 'ユーザー') : '未連携',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                accountEmail: Text(
                  isSignedIn ? user.email : 'Googleドライブにバックアップできます',
                ),
                currentAccountPicture: isSignedIn
                    ? CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  onBackgroundImageError: (_, __) {},
                  child: (user.photoUrl == null)
                      ? Text(
                    user.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                    style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                      : null,
                )
                    : const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, color: Colors.grey),
                ),
              ),
              if (!isSignedIn)
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('Googleアカウントと連携する'),
                  onTap: () async {
                    Navigator.pop(context); // ドロワーを閉じる
                    await AuthService.instance.signIn();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('ログアウト / 連携解除'),
                  onTap: () async {
                    Navigator.pop(context); // ドロワーを閉じる
                    await AuthService.instance.signOut();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}