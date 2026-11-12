/// Where an editor of the panel stands.
enum EditorStatus {
  loading,
  loadFailed,
  editing,
  saving,

  /// The last save went through.
  saved,

  /// The document changed since it was loaded; saving is refused until the
  /// editor reloads it.
  changedSinceLoaded,
  saveFailed,
}
