import 'dart:math';

/// A new request id for a callable that acts once per id
/// (`sendAnnouncement`, `sendSupportReply`): 20 random letters and digits.
String newRequestId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}
