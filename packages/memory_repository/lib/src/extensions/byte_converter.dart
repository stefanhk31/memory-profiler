extension ByteConverter on int {
  double get bytesToMb => this / (1024 * 1024);

  int get mbToBytes => this * (1024 * 1024);
}
