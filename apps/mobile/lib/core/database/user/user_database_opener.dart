import 'dart:io';

import 'package:path/path.dart' as p;

import 'user_database.dart';

class UserDatabaseOpener {
  UserDatabaseOpener({required this.databaseDirectory});

  final Directory databaseDirectory;

  Future<UserDatabase> open() async {
    await databaseDirectory.create(recursive: true);
    return UserDatabase.file(File(p.join(databaseDirectory.path, 'user.db')));
  }
}
