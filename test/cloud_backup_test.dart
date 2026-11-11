// Google Drive backup: the encrypted file, and the service that uploads and
// restores it (against a fake Drive, so nothing touches the network).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gellsoft_rentpro/data/cloud_backup.dart';
import 'package:gellsoft_rentpro/subscription/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDrive implements DriveApi {
  final files = <String, ({String name, Uint8List bytes, DateTime when})>{};
  int _n = 0;
  DateTime Function() clock = DateTime.now;
  Object? error;
  String? email;
  final deleted = <String>[];

  @override
  Future<List<DriveFile>> list() async {
    if (error != null) throw error!;
    final all = [
      for (final e in files.entries)
        DriveFile(
          id: e.key,
          name: e.value.name,
          size: e.value.bytes.length,
          modified: e.value.when,
        ),
    ]..sort((a, b) => b.modified.compareTo(a.modified));
    return all;
  }

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    if (error != null) throw error!;
    files['id${_n++}'] = (name: name, bytes: bytes, when: clock());
  }

  @override
  Future<Uint8List> download(String id, {required int maxBytes}) async {
    if (error != null) throw error!;
    return files[id]!.bytes;
  }

  @override
  Future<void> delete(String id) async {
    if (error != null) throw error!;
    deleted.add(id);
    files.remove(id);
  }

  @override
  Future<String?> accountEmail() async => email;
}

class FakeAuth implements DriveAuth {
  DriveToken? quiet = const DriveToken('tok');
  DriveToken? asked = const DriveToken('tok', email: 'krishna@example.com');
  int quietCalls = 0;
  int askedCalls = 0;
  final forgotten = <String>[];

  @override
  Future<DriveToken?> token({required bool interactive}) async {
    if (interactive) {
      askedCalls++;
      return asked;
    }
    quietCalls++;
    return quiet;
  }

  @override
  Future<void> forget(String accessToken) async => forgotten.add(accessToken);
}

void main() {
  final plain = Uint8List.fromList(utf8.encode('{"shop":"Krishna Stores"}'));

  group('BackupCrypto', () {
    test('seals and opens, and hides the content', () async {
      final sealed = await BackupCrypto.seal(plain, 'a@b.com');
      expect(
        utf8.decode(sealed, allowMalformed: true),
        isNot(contains('shop')),
      );
      expect(await BackupCrypto.open(sealed, 'a@b.com'), plain);
    });

    test('the email is not case sensitive', () async {
      final sealed = await BackupCrypto.seal(plain, 'A@B.com');
      expect(await BackupCrypto.open(sealed, ' a@b.COM '), plain);
    });

    test('another account cannot open it', () async {
      final sealed = await BackupCrypto.seal(plain, 'a@b.com');
      expect(
        () => BackupCrypto.open(sealed, 'someone@else.com'),
        throwsFormatException,
      );
    });

    test('a changed file is refused', () async {
      final sealed = await BackupCrypto.seal(plain, 'a@b.com');
      sealed[sealed.length - 20] ^= 1;
      expect(() => BackupCrypto.open(sealed, 'a@b.com'), throwsFormatException);
    });

    test('something that is not a backup is refused', () {
      expect(
        () => BackupCrypto.open(Uint8List.fromList([1, 2, 3]), 'a@b.com'),
        throwsFormatException,
      );
      expect(
        () => BackupCrypto.open(Uint8List(100), 'a@b.com'),
        throwsFormatException,
      );
    });

    test('two seals of the same data differ (fresh nonce)', () async {
      final a = await BackupCrypto.seal(plain, 'a@b.com');
      final b = await BackupCrypto.seal(plain, 'a@b.com');
      expect(a, isNot(b));
    });
  });

  group('CloudBackupService', () {
    late FakeDrive drive;
    late FakeAuth auth;
    late DateTime now;
    Uint8List? applied;
    var current = plain;

    CloudBackupService make() => CloudBackupService(
      auth: auth,
      apiFor: (_) => drive,
      makeBackup: () async => current,
      applyBackup: (d) async => applied = d,
      clock: () => now,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({
        AccountStore.emailKey: 'krishna@example.com',
      });
      drive = FakeDrive()..clock = () => now;
      auth = FakeAuth();
      now = DateTime(2026, 1, 1, 10);
      applied = null;
      current = plain;
    });

    Future<CloudBackupService> connected() async {
      final s = make();
      expect((await s.connect()).result, CloudResult.done);
      return s;
    }

    test('connect needs a signed-in account', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await make().connect()).result, CloudResult.notSignedIn);
    });

    test(
      'connect turns it on; cancelling or the wrong account does not',
      () async {
        final s = make();
        auth.asked = null;
        expect((await s.connect()).result, CloudResult.cancelled);
        expect((await s.status()).on, isFalse);

        auth.asked = const DriveToken('tok', email: 'other@example.com');
        expect((await s.connect()).result, CloudResult.wrongAccount);
        expect((await s.status()).on, isFalse);

        auth.asked = const DriveToken('tok', email: 'Krishna@Example.com');
        expect((await s.connect()).result, CloudResult.done);
        expect((await s.status()).on, isTrue);
      },
    );

    test('a backup is uploaded encrypted and remembered', () async {
      final s = await connected();
      final r = await s.backupNow();
      expect(r.ok, isTrue);
      expect(drive.files, hasLength(1));
      final f = drive.files.values.single;
      expect(CloudBackupService.isBackupName(f.name), isTrue);
      expect(
        utf8.decode(f.bytes, allowMalformed: true),
        isNot(contains('shop')),
      );
      expect((await s.status()).last, now);
    });

    test('only the newest versions are kept', () async {
      final s = await connected();
      for (var i = 0; i < 8; i++) {
        now = now.add(const Duration(days: 1));
        expect((await s.backupNow()).ok, isTrue);
      }
      expect(drive.files, hasLength(CloudBackupService.keepVersions));
      final newest = (await drive.list()).first;
      expect(newest.modified, now);
    });

    test('restore opens the newest backup and hands it to the app', () async {
      final s = await connected();
      current = Uint8List.fromList(utf8.encode('first'));
      await s.backupNow();
      now = now.add(const Duration(days: 1));
      current = Uint8List.fromList(utf8.encode('second'));
      await s.backupNow();

      final v = await s.versions();
      expect(v.outcome.ok, isTrue);
      expect(v.files, hasLength(2));
      expect((await s.restore(v.files.first)).ok, isTrue);
      expect(utf8.decode(applied!), 'second');
      expect((await s.restore(v.files.last)).ok, isTrue);
      expect(utf8.decode(applied!), 'first');
    });

    test(
      'a backup from another account is refused, nothing is applied',
      () async {
        final other = await BackupCrypto.seal(
          gzip.encode(plain),
          'someone@else.com',
        );
        await drive.upload('backup-1.gbk', other);
        final s = await connected();
        final v = await s.versions();
        final r = await s.restore(v.files.single);
        expect(r.result, CloudResult.badBackup);
        expect(r.message, isNotEmpty);
        expect(applied, isNull);
      },
    );

    test('an empty Drive says so', () async {
      final s = await connected();
      expect((await s.versions()).outcome.result, CloudResult.notFound);
    });

    test('files that are not ours are left alone', () async {
      await drive.upload('notes.txt', Uint8List(3));
      final s = await connected();
      await s.backupNow();
      final v = await s.versions();
      expect(v.files.map((f) => f.name), everyElement(startsWith('backup-')));
      await s.disconnect(deleteBackups: true);
      expect(drive.files.values.map((f) => f.name), ['notes.txt']);
    });

    test('quiet backup never shows a screen; a tap may', () async {
      final s = await connected();
      auth.quiet = null;
      expect((await s.backupNow()).result, CloudResult.notConnected);
      expect(auth.askedCalls, 1); // only the one from connect()
      expect((await s.backupNow(interactive: true)).ok, isTrue);
      expect(auth.askedCalls, 2);
    });

    test('a backup to the wrong Drive is not made', () async {
      final s = await connected();
      auth.quiet = const DriveToken('tok'); // account not told by Google...
      drive.email = 'other@example.com'; // ...but Drive says so
      expect((await s.backupNow()).result, CloudResult.wrongAccount);
      expect(drive.files, isEmpty);
    });

    test(
      'Drive refusing the token asks the person to turn it on again',
      () async {
        final s = await connected();
        drive.error = const DriveAuthRejected();
        expect((await s.backupNow()).result, CloudResult.notConnected);
        expect(auth.forgotten, ['tok']);
      },
    );

    test('full Drive and no internet are told apart', () async {
      final s = await connected();
      drive.error = const DriveFull();
      expect((await s.backupNow()).result, CloudResult.driveFull);
      drive.error = const DriveUnavailable('x');
      expect((await s.backupNow()).result, CloudResult.offline);
    });

    test('turning off keeps the Drive copies unless asked', () async {
      final s = await connected();
      await s.backupNow();
      expect((await s.disconnect()).ok, isTrue);
      expect(drive.files, hasLength(1));
      expect((await s.status()).on, isFalse);
      expect((await s.status()).last, isNull);
    });

    test(
      'turning off with delete removes them, and stays on if that fails',
      () async {
        final s = await connected();
        await s.backupNow();
        drive.error = const DriveUnavailable('x');
        expect((await s.disconnect(deleteBackups: true)).ok, isFalse);
        expect((await s.status()).on, isTrue);
        drive.error = null;
        expect((await s.disconnect(deleteBackups: true)).ok, isTrue);
        expect(drive.files, isEmpty);
        expect((await s.status()).on, isFalse);
      },
    );

    group('automatic backup', () {
      test('does nothing until Drive backup is on', () async {
        expect(await make().autoBackupIfDue(), isFalse);
        expect(drive.files, isEmpty);
      });

      test('runs once a day', () async {
        final s = await connected();
        expect(await s.autoBackupIfDue(), isTrue);
        expect(drive.files, hasLength(1));

        now = now.add(const Duration(hours: 5));
        expect(await s.autoBackupIfDue(), isFalse);
        expect(drive.files, hasLength(1));

        now = now.add(const Duration(hours: 20));
        expect(await s.autoBackupIfDue(), isTrue);
        expect(drive.files, hasLength(2));
      });

      test('can be switched off', () async {
        final s = await connected();
        await s.setAuto(false);
        expect(await s.autoBackupIfDue(), isFalse);
        expect(drive.files, isEmpty);
        // the manual button still works
        expect((await s.backupNow()).ok, isTrue);
      });

      test('a failure waits an hour before trying again', () async {
        final s = await connected();
        drive.error = const DriveUnavailable('x');
        expect(await s.autoBackupIfDue(), isFalse);

        drive.error = null;
        now = now.add(const Duration(minutes: 30));
        expect(await s.autoBackupIfDue(), isFalse);
        expect(drive.files, isEmpty);

        now = now.add(const Duration(minutes: 40));
        expect(await s.autoBackupIfDue(), isTrue);
      });

      test('stays quiet when the permission is gone', () async {
        final s = await connected();
        auth.quiet = null;
        expect(await s.autoBackupIfDue(), isFalse);
        expect(auth.askedCalls, 1); // never opens a Google screen
      });
    });
  });
}
