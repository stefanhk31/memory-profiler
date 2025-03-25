import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:memory_repository/memory_repository.dart';

/// Default interval at which a fetch of memory usage is made.
const defaultFetchInterval = 60000;

/// {@template watch_command}
///
/// `memory_profiler watch --uri=<uri> --library=<library>`
/// A [Command] to watch a currently running Flutter app.
/// {@endtemplate}
class WatchCommand extends Command<int> {
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
      ..addOption('interval');
  }

  @override
  String get description => 'A command to watch a currently running '
      'Flutter app to capture memory usage';

  @override
  String get name => 'watch';

  final Logger _logger;
  final MemoryRepository _memoryRepository;
  final Stdin _stdin;

  @override
  Future<int> run() async {
    Timer? timer;
    try {
      final appUri = argResults?['uri'] as String;
      final interval = argResults?['interval'] as String?;
      // TODO(stefanhk31): Remove linter ignore when detailed snapshot
      // is implemented
      // https://github.com/stefanhk31/memory-profiler/issues/8
      // ignore: unused_local_variable
      final library = argResults?['library'] as String;
      final uri = Uri.parse(appUri);
      final wsUri = uri.replace(scheme: 'ws');

      await _memoryRepository.initialize(wsUri.toString());

      final mainIsolateId = await _memoryRepository.getMainIsolateId();

      _logger.info('Connected to VM at $appUri. Monitoring memory usage. '
          'Press "q" to quit.');

      _stdin
        ..lineMode = false
        ..echoMode = false;

      timer = Timer.periodic(
          Duration(
            milliseconds: interval != null
                ? int.tryParse(interval) ?? defaultFetchInterval
                : defaultFetchInterval,
          ), (_) async {
        _logger.info('Fetching current memory usage...');
        final memoryData =
            await _memoryRepository.fetchMemoryData(mainIsolateId);
        _logger.info(memoryData);
      });

      await for (final codePoints in stdin) {
        for (final codePoint in codePoints) {
          if (codePoint == 113) {
            // 113 is the ASCII code for 'q'
            _logger.info('Exiting...');
            timer.cancel();
            exit(0);
          }
        }
      }
    } on Exception catch (e) {
      _logger.err('Watch failed: $e');
    } finally {
      _stdin
        ..lineMode = true
        ..echoMode = true;
    }

    return ExitCode.success.code;
  }
}
