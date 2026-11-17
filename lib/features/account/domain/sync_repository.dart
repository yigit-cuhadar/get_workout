/// Whether this device's writes have reached the server.
abstract interface class SyncRepository {
  /// True while every write made on this device is on the server, false
  /// while some wait to be sent; again on every change.
  Stream<bool> watchBackedUp();
}
