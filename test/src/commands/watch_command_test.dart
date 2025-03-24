import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:memory_profiler/src/command_runner.dart';
import 'package:memory_profiler/src/commands/commands.dart';
import 'package:memory_repository/memory_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockMemoryRepository extends Mock implements MemoryRepository {}

class _MockStdIn extends Mock implements Stdin {}

void main() {
  group('WatchCommand', () {
    late Logger logger;
    late MemoryRepository memoryRepository;
    late MemoryProfilerCommandRunner commandRunner;
    late Stdin mockStdIn;
    late StreamController<List<int>> stdInController;
    late StreamSubscription<List<int>> stdInSub;

    setUp(() {
      logger = _MockLogger();
      when(() => logger.info(any())).thenAnswer((_) {});
      memoryRepository = _MockMemoryRepository();

      when(() => memoryRepository.initialize(any())).thenAnswer((_) async {});
      when(() => memoryRepository.getMainIsolateId())
          .thenAnswer((_) async => 'isolateId');
      mockStdIn = _MockStdIn();
      when(() => mockStdIn.hasTerminal).thenReturn(true);
      when(() => mockStdIn.echoMode).thenReturn(false);
      when(() => mockStdIn.lineMode).thenReturn(false);

      stdInController = StreamController<List<int>>();
      stdInSub = stdInController.stream.listen((_) {});
      when(
        () => mockStdIn.listen(
          any(),
          onError: any(named: 'onError'),
          onDone: any(named: 'onDone'),
          cancelOnError: any(named: 'cancelOnError'),
        ),
      ).thenAnswer((_) => stdInSub);

      commandRunner = MemoryProfilerCommandRunner(
        logger: logger,
        memoryRepository: memoryRepository,
        stdInput: mockStdIn,
      );
    });

    tearDown(() async {
      await stdInController.close();
      await stdInSub.cancel();
    });

    group('can be instantiated', () {
      test('with custom stdIn', () {
        expect(
          WatchCommand(
            logger: logger,
            memoryRepository: memoryRepository,
            stdInput: mockStdIn,
          ),
          isNotNull,
        );
      });

      test('without custom stdIn', () {
        expect(
          WatchCommand(
            logger: logger,
            memoryRepository: memoryRepository,
          ),
          isNotNull,
        );
      });
    });

    test('fetches memory data at intervals', () async {
      const memoryData = 'data';
      when(() => memoryRepository.initialize(any()))
          .thenAnswer((_) async => memoryData);

      commandRunner.run([
        '--verbose',
        'watch',
        '--uri=http://uri.com',
        '--library=path',
      ]).ignore();

      verify(() => logger.info(memoryData)).called(1);
    });

    // TODO(stefanhk31): Fill in this test once logic is implemented
    // https://github.com/stefanhk31/memory-profiler/issues/8
    test('takes detailed snapshot when threshold is reached', () async {
      const memoryData = 'data';
      when(() => memoryRepository.fetchMemoryData(any()))
          .thenAnswer((_) async => memoryData);

      commandRunner.run([
        '--verbose',
        'watch',
        '--uri=http://uri.com',
        '--library=path',
      ]).ignore();
    });

    test('throws error when exception is hit', () async {
      const errorMessage = 'oops';
      final memoryRepo = _MockMemoryRepository();
      when(() => memoryRepo.initialize(any()))
          .thenThrow(Exception(errorMessage));
      final runner = MemoryProfilerCommandRunner(
        logger: logger,
        memoryRepository: memoryRepo,
        stdInput: mockStdIn,
      );

      runner.run([
        '--verbose',
        'watch',
        '--uri=http://uri.com',
        '--library=path',
      ]).ignore();

      verify(() => logger.err(any())).called(1);
    });
  });
}
