extension ParseIntOrDefault on String? {
  int parseIntOrDefault(int defaultValue) {
    return this == null ? defaultValue : int.tryParse(this!) ?? defaultValue;
  }
}
