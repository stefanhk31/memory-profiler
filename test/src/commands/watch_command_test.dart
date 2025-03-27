import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:memory_profiler/src/command_runner.dart';
import 'package:memory_profiler/src/commands/commands.dart';
import 'package:memory_profiler/src/extensions/extensions.dart';
import 'package:memory_repository/memory_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

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

    setUpAll(() {
      registerFallbackValue(AllocationProfile());
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
      when(() => memoryRepository.fetchAllocationProfile(isolateId)).thenAnswer(
        (_) async => _TestData.allocationProfile(
          _TestData.defaultMemoryUsage,
        ),
      );

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

    group('outputs memory data', () {
      test(
        'at default interval when none is provided',
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
            verify(
              () => logger.info(
                any(
                  that: contains(
                    _TestData.defaultMemoryUsage.heapUsage!.bytesToMb
                        .toString(),
                  ),
                ),
              ),
            ).called(3);

            stdInController.add([113]);
            async.elapse(Duration.zero);
          });
        },
      );

      test(
        'at default interval when invalid interval is provided',
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
            verify(
              () => logger.info(
                any(
                  that: contains(
                    _TestData.defaultMemoryUsage.heapUsage!.bytesToMb
                        .toString(),
                  ),
                ),
              ),
            ).called(3);
            stdInController.add([113]);
            async.elapse(Duration.zero);
          });
        },
      );

      test('at custom interval when provided', () async {
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
          verify(
            () => logger.info(
              any(
                that: contains(
                  _TestData.defaultMemoryUsage.heapUsage!.bytesToMb.toString(),
                ),
              ),
            ),
          ).called(3);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      });
    });

    group('outputs detailed snapshot', () {
      const snapshot = 'snapshot';
      setUp(() {
        when(
          () => memoryRepository.getDetailedMemorySnapshot(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => snapshot);
      });

      test('at default threshold when no threshold is provided', () async {
        fakeAsync((async) {
          when(() => memoryRepository.fetchAllocationProfile(any())).thenAnswer(
            (_) async => _TestData.allocationProfile(
              MemoryUsage(
                heapUsage: 101.mbToBytes,
                heapCapacity: 102.mbToBytes,
              ),
            ),
          );

          commandRunner.run([
            '--verbose',
            'watch',
            '--uri=http://uri.com',
            '--library=path',
          ]).ignore();

          async.elapse(const Duration(milliseconds: defaultFetchInterval));
          verify(
            () => logger.info(snapshot),
          ).called(1);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      });

      test('at default threshold when invalid threshold is provided', () async {
        fakeAsync((async) {
          when(() => memoryRepository.fetchAllocationProfile(any())).thenAnswer(
            (_) async => _TestData.allocationProfile(
              MemoryUsage(
                heapUsage: 101.mbToBytes,
                heapCapacity: 102.mbToBytes,
              ),
            ),
          );

          commandRunner.run([
            '--verbose',
            'watch',
            '--uri=http://uri.com',
            '--library=path',
            '--threshold=invalid',
          ]).ignore();

          async.elapse(const Duration(milliseconds: defaultFetchInterval));
          verify(
            () => logger.info(snapshot),
          ).called(1);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      });

      test('at custom threshold when provided', () async {
        fakeAsync((async) {
          when(() => memoryRepository.fetchAllocationProfile(any())).thenAnswer(
            (_) async => _TestData.allocationProfile(
              MemoryUsage(
                heapUsage: 501.mbToBytes,
                heapCapacity: 502.mbToBytes,
              ),
            ),
          );

          const threshold = 500;

          commandRunner.run([
            '--verbose',
            'watch',
            '--uri=http://uri.com',
            '--library=path',
            '--threshold=$threshold',
          ]).ignore();

          async.elapse(const Duration(milliseconds: defaultFetchInterval));
          verify(
            () => logger.info(snapshot),
          ).called(1);

          stdInController.add([113]);
          async.elapse(Duration.zero);
        });
      });
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

abstract class _TestData {
  static final defaultMemoryUsage = MemoryUsage(
    externalUsage: 5000,
    heapUsage: 2000000,
    heapCapacity: 5000000,
  );

  static AllocationProfile allocationProfile(MemoryUsage memoryUsage) =>
      AllocationProfile(
        memoryUsage: memoryUsage,
      );
}
