import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('操作説明 / ヘルプ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- トップバーのアイコン説明 ---
          _buildSectionTitle('画面右上のアイコン (通常時)'),
          _buildIconExplanation(
            icon: Icons.search,
            color: Colors.black87,
            title: '検索 / 絞り込み',
            description: '日付の範囲や、金額の範囲を指定してレシートを検索・絞り込み表示します。',
          ),
          _buildIconExplanation(
            icon: Icons.camera_alt,
            color: Colors.black87,
            title: 'レシート撮影',
            description: 'カメラを起動して新しいレシートをスキャンします。\nスキャン画面からギャラリー（写真フォルダ）の画像を選択することも可能です。',
          ),

          const Divider(height: 40),

          // --- リストアイコンの説明 ---
          _buildSectionTitle('リストのアイコン (左側)'),
          _buildIconExplanation(
            icon: Icons.cloud_upload,
            color: Colors.grey,
            title: '未バックアップ',
            description: 'この端末で登録し、まだクラウドに保存していません。\nデータも画像もこの端末にしかありません。',
          ),
          _buildIconExplanation(
            icon: Icons.check_circle,
            color: Colors.green,
            title: 'バックアップ済み (端末にあり)',
            description: 'クラウドへの保存が完了しており、この端末にも画像がある状態です。\n安全に管理されています。',
          ),
          _buildIconExplanation(
            icon: Icons.cloud_download,
            color: Colors.blue,
            title: 'バックアップ済み (端末になし)',
            description: '画像はクラウドにあり、端末からは削除して容量を節約している状態です。\nタップすると再ダウンロードできます。',
          ),
          // 【追加】他端末ローカル状態の説明
          _buildIconExplanation(
            icon: Icons.warning,
            color: Colors.orange,
            title: '画像未アップロード',
            description: '他の端末でデータ登録されましたが、まだ画像がクラウドにアップロードされていません。\n金額などの確認はできますが、画像のダウンロードはできません。',
          ),

          const Divider(height: 40),

          // --- 複数選択モードの説明 ---
          _buildSectionTitle('複数選択モード (長押し後)'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text('レシートを長押しすると画面が切り替わり、画面右上に以下のボタンが表示されます。', style: TextStyle(fontSize: 14)),
          ),
          _buildIconExplanation(
            icon: Icons.select_all,
            color: Colors.black87,
            title: '全選択 / 解除',
            description: '表示中の月のレシートを全て選択状態にします。\nもう一度押すと選択を解除します。',
          ),
          _buildIconExplanation(
            icon: Icons.cloud_upload,
            color: Colors.black87,
            title: '一括保存',
            description: 'チェックを入れたレシートをまとめてGoogleドライブへアップロードします。',
          ),
          _buildIconExplanation(
            icon: Icons.delete,
            color: Colors.black87,
            title: '一括削除',
            description: 'チェックを入れたレシートをまとめて削除します。\nバックアップ済みデータが含まれる場合は、容量確保のための画像削除を行うか確認が入ります。',
          ),
          _buildIconExplanation(
            icon: Icons.close,
            color: Colors.black87,
            title: 'モード終了 (×ボタン)',
            description: '複数選択モードを終了して、通常の画面に戻ります（画面左上）。',
          ),

          const Divider(height: 40),

          // --- 基本操作 ---
          _buildSectionTitle('基本操作'),
          _buildTextItem('右にスワイプ', '個別にGoogleドライブへアップロード（保存）します。'),
          _buildTextItem('左にスワイプ', '個別にレシートを削除します。'),
          _buildTextItem('タップ', '編集画面を開きます。\n画像がない場合はダウンロードの確認画面が出ます。'),
          _buildTextItem('長押し', '複数選択モードになります。\nまとめて「保存」や「削除」が可能です。'),

          const Divider(height: 40),

          // --- 便利な機能 ---
          _buildSectionTitle('便利な機能'),
          _buildTextItem('自動同期', 'レシートを保存したタイミングや、アプリ起動時に自動的にクラウド上の台帳と同期します。'),
          _buildTextItem('容量の節約', 'バックアップ済みのレシートを削除すると、リスト（文字データ）だけ残して画像ファイルが消去され、スマホの容量を節約できます。'),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 下線付きのタイトルを作成するメソッド
  Widget _buildSectionTitle(String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey, width: 1)),
      ),
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildIconExplanation({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.black87, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('● $title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Padding(
            padding: const EdgeInsets.only(left: 18.0, top: 4),
            child: Text(description, style: const TextStyle(height: 1.4)),
          ),
        ],
      ),
    );
  }
}