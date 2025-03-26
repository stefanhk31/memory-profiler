import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
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
    late Stdin stdin;
    late StreamController<List<int>> stdInController;
    const isolateId = 'isolateId';
    const memoryData = 'data';

    setUpAll(() {
      stdin = _MockStdIn();
      stdInController = StreamController<List<int>>();
      addTearDown(stdInController.close);
      when(() => stdin.hasTerminal).thenReturn(true);
      when(() => stdin.echoMode).thenReturn(false);
      when(() => stdin.lineMode).thenReturn(false);

      when(
        () => stdin.listen(
          any(),
          onError: any(named: 'onError'),
          onDone: any(named: 'onDone'),
          cancelOnError: any(named: 'cancelOnError'),
        ),
      ).thenAnswer(
        (invocation) => stdInController.stream.listen(
          invocation.positionalArguments.first as void Function(List<int>),
          onError: invocation.namedArguments[#onError] as Function?,
          onDone: invocation.namedArguments[#onDone] as void Function()?,
          cancelOnError: invocation.namedArguments[#cancelOnError] as bool?,
        ),
      );
    });

    setUp(() {
      logger = _MockLogger();
      memoryRepository = _MockMemoryRepository();

      when(() => logger.info(any())).thenAnswer((_) {});
      when(() => memoryRepository.initialize(any())).thenAnswer((_) async {});
      when(() => memoryRepository.getMainIsolateId())
          .thenAnswer((_) async => isolateId);
      when(() => memoryRepository.fetchMemoryData(isolateId))
          .thenAnswer((_) async => memoryData);

      commandRunner = MemoryProfilerCommandRunner(
        logger: logger,
        memoryRepository: memoryRepository,
        stdinOpt: stdin,
      );
    });

    group('can be instantiated', () {
      test('with custom stdIn', () {
        expect(
          WatchCommand(
            logger: logger,
            memoryRepository: memoryRepository,
            stdInput: stdin,
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

    test(
      'fetches memory data at default interval '
      'when none is provided',
      () async {
        fakeAsync((async) {
          commandRunner.run([
            '--verbose',
            'watch',
            '--uri=http://uri.com',
            '--library=path',
          ]).ignore();

          async
            ..elapse(const Duration(milliseconds: defaultFetchInterval))
            ..elapse(const Duration(milliseconds: defaultFetchInterval))
            ..elapse(const Duration(milliseconds: defaultFetchInterval));
          verify(() => logger.info(memoryData)).called(3);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      },
    );

    test(
      'fetches memory data at default interval '
      'when invalid interval is provided',
      () async {
        fakeAsync((async) {
          commandRunner.run([
            '--verbose',
            'watch',
            '--uri=http://uri.com',
            '--library=path',
            '--interval=invalid',
          ]).ignore();

          async
            ..elapse(const Duration(milliseconds: defaultFetchInterval))
            ..elapse(const Duration(milliseconds: defaultFetchInterval))
            ..elapse(const Duration(milliseconds: defaultFetchInterval));
          verify(() => logger.info(memoryData)).called(3);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      },
    );

    test('fetches memory data at custom interval when provided', () async {
      fakeAsync((async) {
        const interval = 5000;

        commandRunner.run([
          '--verbose',
          'watch',
          '--uri=http://uri.com',
          '--library=path',
          '--interval=$interval',
        ]).ignore();

        async
          ..elapse(const Duration(milliseconds: interval))
          ..elapse(const Duration(milliseconds: interval))
          ..elapse(const Duration(milliseconds: interval));
        verify(() => logger.info(memoryData)).called(3);

        stdInController.add([113]);
        async.elapse(Duration.zero);
      });
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
        stdinOpt: stdin,
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
