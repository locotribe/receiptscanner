import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ヘルプ・使い方'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            '1. レシートのスキャン',
            const Icon(Icons.camera_alt, color: Colors.blue),
            [
              'ホーム画面右下のカメラアイコンからスキャンを開始します。',
              '「カメラで撮影」または「ギャラリーから選択」が選べます。',
              'OCR（文字認識）により、以下の項目を自動で読み取ります。',
              '・日付、時刻\n・合計金額\n・店名（電話番号から検索）\n・インボイス登録番号（T+13桁）\n・税率ごとの対象額（10%/8%）',
              '※インボイス番号は「T」が読み取れなかった場合や、「B→8」「S→5」のような誤認識も自動補正して検出します。',
            ],
          ),
          _buildSection(
            context,
            '2. 内容の確認と修正',
            const Icon(Icons.edit, color: Colors.green),
            [
              'スキャン後、編集画面が表示されます。',
              '【重要】税額の入力について',
              '消費税額（10%/8%）は直接入力しません。「対象計（税込）」を入力すると、自動的に税額が計算されます。',
              '・合計金額（税込）を入力し、内訳がある場合は各税率の「対象計」欄に入力してください。',
              '・保存ボタンを押すと、画像から検索用PDFを生成して保存します（処理中は画面に「保存中」と表示されます）。',
            ],
          ),
          _buildSection(
            context,
            '3. 一覧画面と選択モード',
            const Icon(Icons.list, color: Colors.orange),
            [
              '月ごとのタブでレシートを表示します。',
              '画面下部に、表示中の月の「合計金額」が表示されます。',
              '【複数選択モード】',
              '・リストを長押しすると選択モードになります。',
              '・月（タブ）を切り替えても選択状態は維持されます。複数の月にまたがってレシートを選択し、一括で操作できます。',
              '・「全選択」ボタンは、現在表示されている月のレシートのみを全て選択（または解除）します。',
            ],
          ),
          _buildSection(
            context,
            '4. クラウド同期とアイコン',
            const Icon(Icons.cloud_sync, color: Colors.purple),
            [
              'レシートの保存状態はアイコンで確認できます。',
              '🟢 緑チェック: 端末とクラウドの両方に保存済み（安全）',
              '🔵 青雲アイコン: クラウドのみに保存（タップして画像をダウンロード可能）',
              '☁️ グレー雲アイコン: 端末のみに保存（未アップロード）',
              '⚠️ オレンジ: どちらにも画像が見つからない状態',
              'スワイプ操作で「保存（アップロード）」や「削除」が行えます。',
            ],
          ),
          _buildSection(
            context,
            '5. 検索機能',
            const Icon(Icons.search, color: Colors.red),
            [
              'ホーム画面右上の虫眼鏡アイコンから検索ができます。',
              '期間（開始日〜終了日）や、金額の範囲（最小〜最大）を指定してレシートを絞り込めます。',
              '絞り込み中はアイコンが赤く点灯します。',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, Icon icon, List<String> contents) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: ExpansionTile(
        leading: icon,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contents.map((text) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    text,
                    style: const TextStyle(height: 1.5, fontSize: 14),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}