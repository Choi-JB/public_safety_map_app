import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// grid_id: {version, updated_at}, grid/infra 등 데이터 타입별 로컬 동기화 버전
class StaticDataVersion {
  const StaticDataVersion({required this.version, required this.updatedAt});
  final String version;
  final String updatedAt;
}

/// 격자·인프라 정적 데이터 로컬 저장소 (`static_map.db`).
/// 컬럼명을 API JSON 키와 동일하게 둬서 GridItem/InfrastructureItem.fromJson을 그대로 재사용한다.
class StaticDataLocalStore {
  StaticDataLocalStore._();
  static final StaticDataLocalStore instance = StaticDataLocalStore._();

  Database? _db;

  Future<Database> get _database async {
    final db = _db;
    if (db != null) return db;
    final dir = await getDatabasesPath();
    final opened = await openDatabase(
      '$dir/static_map.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meta (
            data_type TEXT PRIMARY KEY,
            version TEXT,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE grids (
            grid_id INTEGER PRIMARY KEY,
            lat REAL,
            lng REAL,
            infra_count INTEGER,
            safety_grade TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_grids_lat ON grids(lat)');
        await db.execute('CREATE INDEX idx_grids_lng ON grids(lng)');
        await db.execute('''
          CREATE TABLE infrastructures (
            id INTEGER PRIMARY KEY,
            type TEXT,
            address TEXT,
            lat REAL,
            lng REAL
          )
        ''');
        await db.execute('CREATE INDEX idx_infra_lat ON infrastructures(lat)');
        await db.execute('CREATE INDEX idx_infra_lng ON infrastructures(lng)');
        await db.execute('CREATE INDEX idx_infra_type ON infrastructures(type)');
      },
    );
    _db = opened;
    return opened;
  }

  Future<void> init() async {
    await _database;
  }

  Future<Map<String, StaticDataVersion>> getVersions() async {
    final db = await _database;
    final rows = await db.query('meta');
    return {
      for (final r in rows)
        r['data_type'] as String: StaticDataVersion(
          version: r['version'] as String? ?? '',
          updatedAt: r['updated_at'] as String? ?? '',
        ),
    };
  }

  Future<List<GridItem>> queryGridsInBounds({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'grids',
      where: 'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
      whereArgs: [swLat, neLat, swLng, neLng],
    );
    return rows.map(GridItem.fromJson).toList();
  }

  /// bbox(위경도 델타)로 1차 필터 후, 호출 측에서 distKm으로 2차 정밀 반경 필터를 적용한다.
  Future<List<InfrastructureItem>> queryInfraNear({
    required double lat,
    required double lng,
    required int radiusM,
    String? type,
  }) async {
    final db = await _database;
    // 1도 ≈ 111km. 반경보다 넉넉하게 bbox를 잡아 SQL에서 1차로만 좁힌다.
    final deltaDeg = (radiusM / 111000) * 1.5;
    final where = StringBuffer(
      'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
    );
    final args = <Object?>[
      lat - deltaDeg,
      lat + deltaDeg,
      lng - deltaDeg,
      lng + deltaDeg,
    ];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type);
    }
    final rows = await db.query(
      'infrastructures',
      where: where.toString(),
      whereArgs: args,
    );
    return rows.map(InfrastructureItem.fromJson).toList();
  }

  /// 격자 3.4만 건, 인프라 25만 건급 덤프를 감당하기 위해 배치를 쪼개서 커밋한다.
  static const int _batchChunkSize = 1000;

  Future<void> replaceGrids(
    List<Map<String, dynamic>> rows, {
    required String version,
    required String updatedAt,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('grids');
      for (var i = 0; i < rows.length; i += _batchChunkSize) {
        final end =
            (i + _batchChunkSize < rows.length) ? i + _batchChunkSize : rows.length;
        final batch = txn.batch();
        for (final row in rows.sublist(i, end)) {
          batch.insert('grids', {
            'grid_id': row['grid_id'],
            'lat': row['lat'],
            'lng': row['lng'],
            'infra_count': row['infra_count'],
            'safety_grade': row['safety_grade'],
          });
        }
        await batch.commit(noResult: true);
      }
      await txn.insert(
        'meta',
        {'data_type': 'grid', 'version': version, 'updated_at': updatedAt},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> replaceInfrastructures(
    List<Map<String, dynamic>> rows, {
    required String version,
    required String updatedAt,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('infrastructures');
      for (var i = 0; i < rows.length; i += _batchChunkSize) {
        final end =
            (i + _batchChunkSize < rows.length) ? i + _batchChunkSize : rows.length;
        final batch = txn.batch();
        for (final row in rows.sublist(i, end)) {
          batch.insert('infrastructures', {
            'id': row['id'],
            'type': row['type'],
            'address': row['address'],
            'lat': row['lat'],
            'lng': row['lng'],
          });
        }
        await batch.commit(noResult: true);
      }
      await txn.insert(
        'meta',
        {'data_type': 'infra', 'version': version, 'updated_at': updatedAt},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
