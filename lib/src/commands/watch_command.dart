import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:memory_repository/memory_repository.dart';

/// Default interval at which a fetch of memory usage is made.
const defaultFetchInterval = 60000;

/// Default memory threshold (in MB) at which a snapshot is taken.
const defaultThreshold = 100;

/// {@template watch_command}
///
/// `memory_profiler watch --uri=<uri> --library=<library> '
/// 'interval=<interval> --threshold=<threshold>`
/// A [Command] to watch a currently running Flutter app.
/// {@endtemplate}
class WatchCommand extends Command<int> {
  final Logger _logger;

  final MemoryRepository _memoryRepository;

  final Stdin _stdin;

  Timer? _timer;

  /// {@macro watch_command}
  WatchCommand({
    required Logger logger,
    required MemoryRepository memoryRepository,
    Stdin? stdInput,
  })  : _logger = logger,
        _memoryRepository = memoryRepository,
        _stdin = stdInput ?? stdin {
    argParser
      ..addOption('uri')
      ..addOption('library')
      ..addOption('interval')
      ..addOption('threshold');
  }
  @override
  String get description => 'A command to watch a currently running '
      'Flutter app to capture memory usage';
  @override
  String get name => 'watch';

  @override
  Future<int> run() async {
    try {
      final appUri = argResults?['uri'] as String;
      final interval = argResults?['interval'] as String?;
      final library = argResults?['library'] as String;
      final threshold = argResults?['threshold'] as String?;
      final uri = Uri.parse(appUri);
      final wsUri = uri.replace(scheme: 'ws');

      await _memoryRepository.initialize(wsUri.toString());

      final mainIsolateId = await _memoryRepository.getMainIsolateId();

      _logger.info('Connected to VM at $appUri. Monitoring memory usage. '
          'Press "q" to quit.');

      _stdin
        ..lineMode = false
        ..echoMode = false;

      _timer = Timer.periodic(
          Duration(
            milliseconds: interval.parseIntOrDefault(defaultFetchInterval),
          ), (_) async {
        _logger.info('Fetching current memory usage...');
        final allocationProfile =
            await _memoryRepository.fetchAllocationProfile(mainIsolateId);
        final memoryUsage = allocationProfile.memoryUsage;
        _logger.info('Memory Usage: '
            '\nHeap Usage: ${memoryUsage?.heapUsage?.bytesToMb} MB '
            '\nHeap Capacity: ${memoryUsage?.heapCapacity?.bytesToMb} MB'
            '\nExternal Usage: ${memoryUsage?.externalUsage?.bytesToMb} MB');

        final thresholdVal = threshold.parseIntOrDefault(defaultThreshold);

        if (memoryUsage?.heapUsage != null &&
            memoryUsage!.heapUsage!.bytesToMb >= thresholdVal) {
          _logger.info('Memory usage exceeded threshold of $thresholdVal. '
              'Taking snapshot... ');
          final snapshot = await _memoryRepository.getDetailedMemorySnapshot(
            allocationProfile,
            library,
          );
          _logger.info(snapshot);
        }
      });

      await for (final codePoints in _stdin) {
        for (final codePoint in codePoints) {
          if (codePoint == 113) {
            // 113 is the ASCII code for 'q'
            _logger.info('Exiting...');
            _timer?.cancel();
            _stdin
              ..lineMode = true
              ..echoMode = true;
            return ExitCode.success.code;
          }
        }
      }
    } on Exception catch (e) {
      _logger.err('Watch failed: $e');
      _stdin
        ..lineMode = true
        ..echoMode = true;
    }
    return ExitCode.software.code;
  }
}
