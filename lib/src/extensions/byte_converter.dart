extension ByteConverter on int {
  double get toMB => this / (1024 * 1024);
}
