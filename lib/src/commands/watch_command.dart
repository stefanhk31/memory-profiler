import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vm_service/vm_service.dart';

/// Type to simplify providing VM service to the `WatchCommand`.
typedef VmServiceProvider = Future<VmService> Function(String);

/// {@template watch_command}
///
/// `memory_profiler watch --uri`
/// A [Command] to watch a currently running Flutter app
/// {@endtemplate}
class WatchCommand extends Command<int> {
  /// {@macro watch_command}
  WatchCommand({
    required Logger logger,
    required VmServiceProvider vmServiceProvider,
  })  : _logger = logger,
        _vmServiceProvider = vmServiceProvider {
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
  final VmServiceProvider _vmServiceProvider;

  @override
  Future<int> run() async {
    try {
      final appUri = argResults?['uri'] as String;
      final library = argResults?['library'] as String;
      final uri = Uri.parse(appUri);
      final wsUri = uri.replace(scheme: 'ws');

      final vmService = await _vmServiceProvider(wsUri.toString());

      final vm = await vmService.getVM();
      final isolates = vm.isolates!;

      _logger.info('Current isolates: ${isolates.map((i) => i.name)} ');

      final mainIsolate = isolates.firstWhere(
        (i) => i.name == 'main',
        orElse: () => throw Exception('Main isolate not found'),
      );

      _logger.info('Connected to VM at $appUri. Press spacebar to get memory '
          'usage, or "q" to quit.');

      stdin.lineMode = false;
      stdin.echoMode = false;

      await for (final codePoints in stdin) {
        for (final codePoint in codePoints) {
          if (codePoint == 32) {
            // 32 is the ASCII code for spacebar
            _logger.info('Retrieving current memory stats...');
            final sb = StringBuffer();
            final memoryUsage = await vmService.getMemoryUsage(mainIsolate.id!);
            sb.write('\nMemory Usage: '
                '\nHeap Usage: ${memoryUsage.heapUsage} bytes '
                '\nHeap Capacity: ${memoryUsage.heapCapacity} bytes'
                '\nExternal Usage: ${memoryUsage.externalUsage} bytes '
                '\nDetails: ');

            final allocationProfile =
                await vmService.getAllocationProfile(mainIsolate.id!);

            final members = allocationProfile.members ?? <ClassHeapStats>[];

            final libMembers = members
                .where(
                  (m) =>
                      (m.classRef?.library?.uri?.contains(library) ?? false) &&
                      (m.bytesCurrent != null && m.bytesCurrent! > 0),
                )
                .toList()
              ..sort(
                (a, b) => (a.bytesCurrent ?? 0).compareTo(b.bytesCurrent ?? 0),
              );

            for (final member in libMembers) {
              sb.write('\n Class: ${member.classRef?.name} '
                  '\nCurrent Bytes: ${member.bytesCurrent}');
            }

            _logger.info(sb.toString());
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
      stdin.lineMode = true;
      stdin.echoMode = true;
    }

    return ExitCode.success.code;
  }
}
