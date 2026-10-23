import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/class_item.dart';

class DatabaseHelper extends ChangeNotifier {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'class_schedule.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            room TEXT NOT NULL,
            professor TEXT NOT NULL,
            day INTEGER NOT NULL,
            start_minutes INTEGER NOT NULL,
            end_minutes INTEGER NOT NULL,
            CHECK (day BETWEEN 1 AND 7),
            CHECK (start_minutes BETWEEN 0 AND 1439),
            CHECK (end_minutes BETWEEN 1 AND 1440),
            CHECK (end_minutes > start_minutes),
            CHECK (length(trim(subject)) > 0),
            CHECK (length(trim(room)) > 0),
            CHECK (length(trim(professor)) > 0)
          )
        ''');
        await _createValidationTriggers(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Do not rebuild or delete the existing table: users' saved classes
        // must survive upgrades. Triggers apply validation to legacy databases.
        if (oldVersion < 2) {
          await _createValidationTriggers(db);
        }
        // Version 3: the placeholder room is now "Room to confirm" everywhere.
        if (oldVersion < 3) {
          await db.execute(
            "UPDATE classes SET room = 'Room to confirm' "
            "WHERE lower(trim(room)) = 'unknown room'",
          );
        }
      },
    );
  }

  Future<void> _createValidationTriggers(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS classes_validate_insert
      BEFORE INSERT ON classes
      BEGIN
        SELECT CASE WHEN length(trim(NEW.subject)) < 2
          THEN RAISE(ABORT, 'Subject must contain at least 2 characters') END;
        SELECT CASE WHEN length(trim(NEW.room)) < 1
          THEN RAISE(ABORT, 'Room is required') END;
        SELECT CASE WHEN length(trim(NEW.professor)) < 2
          THEN RAISE(ABORT, 'Professor must contain at least 2 characters') END;
        SELECT CASE WHEN NEW.day < 1 OR NEW.day > 7
          THEN RAISE(ABORT, 'Day must be between 1 and 7') END;
        SELECT CASE WHEN NEW.start_minutes < 0 OR NEW.start_minutes >= 1440
          THEN RAISE(ABORT, 'Start time is invalid') END;
        SELECT CASE WHEN NEW.end_minutes < 1 OR NEW.end_minutes > 1440 OR NEW.end_minutes <= NEW.start_minutes
          THEN RAISE(ABORT, 'End time must be after start time and within the day') END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS classes_validate_update
      BEFORE UPDATE ON classes
      BEGIN
        SELECT CASE WHEN length(trim(NEW.subject)) < 2
          THEN RAISE(ABORT, 'Subject must contain at least 2 characters') END;
        SELECT CASE WHEN length(trim(NEW.room)) < 1
          THEN RAISE(ABORT, 'Room is required') END;
        SELECT CASE WHEN length(trim(NEW.professor)) < 2
          THEN RAISE(ABORT, 'Professor must contain at least 2 characters') END;
        SELECT CASE WHEN NEW.day < 1 OR NEW.day > 7
          THEN RAISE(ABORT, 'Day must be between 1 and 7') END;
        SELECT CASE WHEN NEW.start_minutes < 0 OR NEW.start_minutes >= 1440
          THEN RAISE(ABORT, 'Start time is invalid') END;
        SELECT CASE WHEN NEW.end_minutes < 1 OR NEW.end_minutes > 1440 OR NEW.end_minutes <= NEW.start_minutes
          THEN RAISE(ABORT, 'End time must be after start time and within the day') END;
      END
    ''');
  }

  // CREATE
  Future<int> insert(ClassItem c) async {
    validateClass(c);
    final db = await _database;
    final id = await db.transaction((txn) async {
      await _validateSchedule(txn, [c]);
      return txn.insert('classes', c.toMap());
    });
    notifyListeners();
    return id;
  }

  static void validateClass(ClassItem c) {
    if (c.subject.trim().length < 2) {
      throw ArgumentError('Subject must contain at least 2 characters.');
    }
    if (c.room.trim().isEmpty) throw ArgumentError('Room is required.');
    if (c.professor.trim().length < 2) {
      throw ArgumentError('Professor must contain at least 2 characters.');
    }
    if (c.day < 1 || c.day > 7) throw ArgumentError('Day must be 1–7.');
    if (c.startMinutes < 0 || c.startMinutes >= 1440) {
      throw ArgumentError('Start time is invalid.');
    }
    if (c.endMinutes <= c.startMinutes || c.endMinutes > 1440) {
      throw ArgumentError(
        'End time must be after start time and within the day.',
      );
    }
  }

  static void validateNoOverlaps(Iterable<ClassItem> classes) {
    final ordered = classes.toList()
      ..sort((a, b) {
        final day = a.day.compareTo(b.day);
        return day == 0 ? a.startMinutes.compareTo(b.startMinutes) : day;
      });
    var day = 0;
    var latestEnd = 0;
    var latestClass = '';
    for (final item in ordered) {
      if (item.day != day) {
        day = item.day;
        latestEnd = item.endMinutes;
        latestClass = item.subject;
      } else if (item.startMinutes < latestEnd) {
        throw ArgumentError('${item.subject} overlaps $latestClass.');
      } else if (item.endMinutes > latestEnd) {
        latestEnd = item.endMinutes;
        latestClass = item.subject;
      }
    }
  }

  Future<List<ClassItem>> _readAll(DatabaseExecutor executor) async {
    final rows = await executor.query('classes', orderBy: 'day, start_minutes');
    return rows.map(ClassItem.fromMap).toList();
  }

  Future<void> _validateSchedule(
    DatabaseExecutor executor,
    Iterable<ClassItem> additions, {
    Set<int> excludedIds = const {},
  }) async {
    final candidates = additions.toList();
    validateNoOverlaps(candidates);
    final existing = await _readAll(executor);
    for (final candidate in candidates) {
      for (final item in existing) {
        if (excludedIds.contains(item.id) || item.day != candidate.day) {
          continue;
        }
        if (candidate.startMinutes < item.endMinutes &&
            item.startMinutes < candidate.endMinutes) {
          throw ArgumentError('${candidate.subject} overlaps ${item.subject}.');
        }
      }
    }
  }

  // READ
  Future<List<ClassItem>> getAll() async {
    final db = await _database;
    return _readAll(db);
  }

  Future<List<ClassItem>> getByDay(int day) async {
    final db = await _database;
    final rows = await db.query(
      'classes',
      where: 'day = ?',
      whereArgs: [day],
      orderBy: 'start_minutes',
    );
    return rows.map(ClassItem.fromMap).toList();
  }

  /// Inserts all imported classes atomically. If any insert fails, none are saved.
  Future<int> insertMany(List<ClassItem> classes) async {
    if (classes.isEmpty) return 0;
    for (final item in classes) {
      validateClass(item);
    }
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await _validateSchedule(txn, classes);
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap());
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  /// Replaces the full schedule in one transaction after validating every row.
  /// Used by explicit JSON restore; a failed import leaves the current data intact.
  Future<int> replaceAll(List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    validateNoOverlaps(classes);
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await txn.delete('classes');
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..remove('id'));
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  /// Removes selected saved classes and imports replacements atomically.
  Future<int> replaceSelected(List<int> ids, List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await _validateSchedule(txn, classes, excludedIds: ids.toSet());
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.delete(
          'classes',
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
      }
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..remove('id'));
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  // UPDATE
  Future<int> update(ClassItem c) async {
    validateClass(c);
    if (c.id == null) {
      throw ArgumentError('Cannot update a class without an ID.');
    }
    final db = await _database;
    final changed = await db.transaction((txn) async {
      await _validateSchedule(txn, [c], excludedIds: {c.id!});
      return txn.update(
        'classes',
        c.toMap(),
        where: 'id = ?',
        whereArgs: [c.id],
      );
    });
    if (changed > 0) notifyListeners();
    return changed;
  }


  /// Restores a recently deleted class with its original ID. Validation is
  /// repeated because another class may have been added during the undo window.
  Future<int> restoreDeleted(ClassItem c) async {
    validateClass(c);
    if (c.id == null) {
      throw ArgumentError('Cannot restore a class without its original ID.');
    }
    final db = await _database;
    final restored = await db.transaction((txn) async {
      await _validateSchedule(txn, [c]);
      return txn.insert('classes', c.toMap());
    });
    notifyListeners();
    return restored;
  }

  // DELETE
  Future<int> delete(int id) async {
    final db = await _database;
    final deleted = await db.delete(
      'classes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted > 0) notifyListeners();
    return deleted;
  }
}
