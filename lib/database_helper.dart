import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath = await getDatabasesPath();
    String path = join(dbPath, 'iot_lab.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE device_status(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device TEXT,
        status TEXT,
        timestamp TEXT
      )
    ''');
  }

  // Thêm dữ liệu
  Future<int> insertStatus(Map<String, dynamic> row) async {
    Database db = await database;
    return await db.insert('device_status', row);
  }

  // Lấy tất cả dữ liệu
  Future<List<Map<String, dynamic>>> getAllStatus() async {
    Database db = await database;
    return await db.query('device_status', orderBy: 'id DESC');
  }
}
