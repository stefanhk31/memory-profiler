// ignore_for_file: prefer_const_constructors
import 'package:memory_repository/memory_repository.dart';
import 'package:memory_repository/src/exceptions/vm_service_not_initialized_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

void main() {
  group('MemoryRepository', () {
    late VmService vmService;
    late MemoryRepository memoryRepository;

    setUp(() {
      vmService = _MockVmService();
      memoryRepository = MemoryRepository(
        vmServiceProvider: (_) async => vmService,
      );
    });

    group('can be instantiated', () {
      test('with a vmServiceProvider', () {
        expect(
          MemoryRepository(
            vmServiceProvider: (_) async => vmService,
          ),
          isNotNull,
        );
      });

      test('without a vmServiceProvider', () {
        expect(MemoryRepository(), isNotNull);
      });
    });

    group('initialize', () {
      test('can initialize vm Service', () async {
        await memoryRepository.initialize('uri');
        expect(memoryRepository.currentVmInstance, isNotNull);
      });
    });

    group('getMainIsolateId', () {
      test(
        'throws VmServiceNotInitializedException '
        'when vm Service has not been initialized',
        () async {
          expect(
            () async => memoryRepository.getMainIsolateId(),
            throwsA(
              isA<VmServiceNotInitializedException>(),
            ),
          );
        },
      );

      test('throws exception when main isolate is not found', () async {
        when(() => vmService.getVM()).thenAnswer((_) async => VM());
        await memoryRepository.initialize('uri');
        expect(
          () async => memoryRepository.getMainIsolateId(),
          throwsException,
        );
      });

      test('throws exception when main isolate id is null', () async {
        when(() => vmService.getVM())
            .thenAnswer((_) async => VM(isolates: [IsolateRef(name: 'main')]));
        await memoryRepository.initialize('uri');
        expect(
          () async => memoryRepository.getMainIsolateId(),
          throwsException,
        );
      });

      test('returns main isolate id when available', () async {
        const isolateId = 'id';
        when(() => vmService.getVM()).thenAnswer(
          (_) async => VM(isolates: [IsolateRef(name: 'main', id: isolateId)]),
        );
        await memoryRepository.initialize('uri');
        final result = await memoryRepository.getMainIsolateId();
        expect(
          result,
          equals(isolateId),
        );
      });
    });

    group('fetchAllocaitonProfile', () {
      const isolateId = 'id';
      test(
        'throws VmServiceNotInitializedException '
        'when vm Service has not been initialized',
        () async {
          expect(
            () async => memoryRepository.fetchAllocationProfile(isolateId),
            throwsA(
              isA<VmServiceNotInitializedException>(),
            ),
          );
        },
      );

      test('returns memory usage', () async {
        when(() => vmService.getAllocationProfile(isolateId)).thenAnswer(
          (_) async => _TestData.allocationProfile,
        );

        await memoryRepository.initialize('uri');
        final result = await memoryRepository.fetchAllocationProfile(isolateId);
        expect(
          result,
          equals(_TestData.allocationProfile),
        );
      });
    });

    group('getDetailedMemorySnapshot', () {
      test('returns sorted memory data for classes in given library path',
          () async {
        final result = await memoryRepository.getDetailedMemorySnapshot(
          _TestData.allocationProfile,
          'path',
        );
        expect(
          result,
          contains(_TestData.classInPath.classRef?.name),
        );
        expect(
          result,
          contains(_TestData.classInPath.bytesCurrent.toString()),
        );
        expect(
          result,
          contains(_TestData.secondClassInPath.classRef?.name),
        );
        expect(
          result,
          contains(_TestData.secondClassInPath.bytesCurrent.toString()),
        );
        expect(
          result.indexOf(
            _TestData.secondClassInPath.classRef!.name!,
          ),
          lessThan(result.indexOf(_TestData.classInPath.classRef!.name!)),
        );
        expect(
          result,
          isNot(
            contains(_TestData.classNotInPath.classRef?.name),
          ),
        );
        expect(
          result,
          isNot(
            contains(_TestData.classNotInPath.bytesCurrent.toString()),
          ),
        );
      });
    });
  });
}

abstract class _TestData {
  static final classInPath = ClassHeapStats(
    classRef: ClassRef(
      id: 'classId',
      name: 'classInPath',
      library: LibraryRef(id: 'libraryId', uri: 'path'),
    ),
    bytesCurrent: 100,
  );

  static final secondClassInPath = ClassHeapStats(
    classRef: ClassRef(
      id: 'classId',
      name: 'secondClassInPath',
      library: LibraryRef(id: 'libraryId', uri: 'path'),
    ),
    bytesCurrent: 50,
  );

  static final classNotInPath = ClassHeapStats(
    classRef: ClassRef(
      id: 'classId',
      name: 'classNotInPath',
      library: LibraryRef(id: 'libraryId', uri: 'other'),
    ),
    bytesCurrent: 200,
  );

  static final memoryUsage = MemoryUsage(
    externalUsage: 5000,
    heapUsage: 2000000,
    heapCapacity: 5000000,
  );

  static final allocationProfile = AllocationProfile(
    members: [
      classInPath,
      secondClassInPath,
      classNotInPath,
    ],
    memoryUsage: memoryUsage,
  );
}
