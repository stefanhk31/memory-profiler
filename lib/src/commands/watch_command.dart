import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:memory_repository/memory_repository.dart';

/// {@template watch_command}
///
/// `memory_profiler watch --uri`
/// A [Command] to watch a currently running Flutter app
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
      ..addOption('library');
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
    try {
      final appUri = argResults?['uri'] as String;
      final library = argResults?['library'] as String;
      final uri = Uri.parse(appUri);
      final wsUri = uri.replace(scheme: 'ws');

      await _memoryRepository.initialize(wsUri.toString());

      final mainIsolateId = await _memoryRepository.getMainIsolateId();

      _logger.info('Connected to VM at $appUri. Press spacebar to get memory '
          'usage, or "q" to quit.');

      _stdin
        ..lineMode = false
        ..echoMode = false;

      await for (final codePoints in stdin) {
        for (final codePoint in codePoints) {
          if (codePoint == 32) {
            // 32 is the ASCII code for spacebar
            _logger.info('Retrieving current memory stats...');
            final memoryData =
                await _memoryRepository.fetchMemoryData(mainIsolateId, library);
            _logger.info(memoryData);
          } else if (codePoint == 113) {
            // 113 is the ASCII code for 'q'
            _logger.info('Exiting...');
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
