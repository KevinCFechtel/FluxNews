import 'package:sqflite/sqflite.dart';

const int fluxNewsDatabaseVersion = 12;

Future<void> createFluxNewsDatabaseIndexes(Database db) async {
  const statements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_news_published '
        'ON news(publishedAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_news_status_published '
        'ON news(status, publishedAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_news_feed_status_published '
        'ON news(feedID, status, publishedAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_news_starred_published '
        'ON news(starred, publishedAt DESC)',
    'CREATE INDEX IF NOT EXISTS idx_news_sync_status '
        'ON news(syncStatus, status)',
    'CREATE INDEX IF NOT EXISTS idx_attachments_news '
        'ON attachments(newsID)',
    'CREATE INDEX IF NOT EXISTS idx_attachments_url '
        'ON attachments(attachmentURL)',
    'CREATE INDEX IF NOT EXISTS idx_feeds_category '
        'ON feeds(categoryID)',
  ];

  for (final statement in statements) {
    await db.execute(statement);
  }
}
