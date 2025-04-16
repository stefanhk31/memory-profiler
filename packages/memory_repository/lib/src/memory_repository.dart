import 'dart:collection';
import 'dart:developer';
import 'package:memory_repository/src/exceptions/vm_service_not_initialized_exception.dart';
import 'package:memory_repository/src/extensions/extensions.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Type to simplify injecting VM service.
typedef VmServiceProvider = Future<VmService> Function(String);

/// {@template memory_repository}
/// Repository encapsulating the logic
/// for profiling memory using the Dart VM.
/// {@endtemplate}
class MemoryRepository {
  /// {@macro memory_repository}
  MemoryRepository({VmServiceProvider? vmServiceProvider})
      : _vmServiceProvider = vmServiceProvider ?? vmServiceConnectUri;

  final VmServiceProvider _vmServiceProvider;

  VmService? _vmService;

  /// Getting for the current instance of the VM service.
  /// Only used for testing.
  VmService? get currentVmInstance => _vmService;

  /// Initializes a VM service attached to the given [uri].
  Future<void> initialize(String uri) async {
    _vmService = await _vmServiceProvider(uri);
  }

  /// Retrieves an [IsolateRef] for the main running isolate.
  Future<IsolateRef> getMainIsolate() async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;

    final vm = await vmService.getVM();
    final isolates = vm.isolates ?? <IsolateRef>[];

    return isolates.firstWhere(
      (i) => i.name == 'main',
      orElse: () {
        throw Exception('Main isolate not found');
      },
    );
  }

  /// Retrieves the ID of the main running isolate.
  Future<String> getMainIsolateId() async {
    final mainIsolate = await getMainIsolate();

    if (mainIsolate.id == null) {
      throw Exception('Main Isolate ID cannot be null');
    }

    return mainIsolate.id!;
  }

  /// Fetches current memory allocation profile given a particular [isolateId].
  Future<MemoryUsage> fetchMemoryUsage(String isolateId) async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;

    return vmService.getMemoryUsage(isolateId);
  }

  /// Fetches a detailed snapshot of memory usage given an [allocationProfile],
  /// and extracts [ClassHeapStats] of members in the given [libraryPath]
  Future<String> getDetailedMemorySnapshot(
    String libraryPath,
  ) async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;
    final mainIsolate = await getMainIsolate();

    final snapshot = await HeapSnapshotGraph.getSnapshot(
      vmService,
      mainIsolate,
      calculateReferrers: false,
      decodeExternalProperties: false,
      decodeIdentityHashCodes: false,
      decodeObjectData: false,
    );

    final sb = StringBuffer()..write('Detailed Memory Snapshot: ');

    final classes =
        snapshot.classes.where((c) => c.libraryUri.path.contains(libraryPath));

    for (final heapSnapshotClass in classes) {
      final objects =
          snapshot.objects.where((o) => o.classId == heapSnapshotClass.classId);

      var retainedSize = 0;
      var objectsTraversed = 0;

      for (final obj in objects) {
        retainedSize += _getObjSizeInBatches(obj);
        objectsTraversed++;
        print(
            '${heapSnapshotClass.name}: $objectsTraversed objects out of ${objects.length} traversed');
      }

      // print('\n Class: ${heapSnapshotClass.name} '
      //     '\nRetained Size: ${retainedSize.bytesToMb} MB');

      sb.write('\n Class: ${heapSnapshotClass.name} '
          '\nRetained Size: ${retainedSize.bytesToMb} MB');
    }

    return sb.toString();
  }

  int _getObjSizeInBatches(HeapSnapshotObject obj, {int batchSize = 100}) {
    var size = 0;
    final visited = <int>{};
    final queue = Queue<HeapSnapshotObject>()..add(obj);

    while (queue.isNotEmpty) {
      var processedInBatch = 0;
      var batchTotal = 0;

      while (queue.isNotEmpty && processedInBatch < batchSize) {
        final currentObj = queue.removeFirst();
        if (currentObj.klass.name == 'StreamingMediaPlayerBloc') {
          print('CURRENT OBJECT ${currentObj.klass.name}: '
              '\n size: ${currentObj.shallowSize} '
              '\n successors: ${currentObj.successors.map((s) => s.klass.name)}, ');
        }

        if (visited.contains(currentObj.identityHashCode)) continue;
        visited.add(currentObj.identityHashCode);

        batchTotal += currentObj.shallowSize;

        queue.addAll(currentObj.successors);

        processedInBatch++;
      }

      size += batchTotal;
    }

    return size;
  }
}
