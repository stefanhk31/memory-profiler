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

  /// Retrieves the ID of the main running isolate.
  Future<String> getMainIsolateId() async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;

    final vm = await vmService.getVM();
    final isolates = vm.isolates ?? <IsolateRef>[];
    final mainIsolate = isolates.firstWhere(
      (i) => i.name == 'main',
      orElse: () {
        throw Exception('Main isolate not found');
      },
    );

    if (mainIsolate.id == null) {
      throw Exception('Main Isolate ID cannot be null');
    }

    return mainIsolate.id!;
  }

  /// Fetches current memory allocation profile given a particular [isolateId].
  Future<AllocationProfile> fetchAllocationProfile(String isolateId) async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;

    return vmService.getAllocationProfile(isolateId);
  }

  /// Fetches a detailed snapshot of memory usage given an [allocationProfile],
  /// and extracts [ClassHeapStats] of members in the given [libraryPath]
  Future<String> getDetailedMemorySnapshot(
    AllocationProfile allocationProfile,
    String libraryPath,
  ) async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;
    final vm = await vmService.getVM();
    final isolates = vm.isolates ?? <IsolateRef>[];
    final mainIsolate = isolates.firstWhere(
      (i) => i.name == 'main',
      orElse: () {
        throw Exception('Main isolate not found');
      },
    );

    final snapshot =
        await HeapSnapshotGraph.getSnapshot(vmService, mainIsolate);

    final result = NativeRuntime.writeHeapSnapshotToFile(
      '${DateTime.now()}_snapshot.json',
    );

    final sb = StringBuffer()..write('Detailed Memory Snapshot: ');

    // final classes =
    //     snapshot.classes.where((c) => c.libraryUri.path.contains(libraryPath));

    // for (final heapSnapshotClass in classes) {
    //   print('Gathering retained size of ${heapSnapshotClass.name}...');
    //   final objects =
    //       snapshot.objects.where((o) => o.classId == heapSnapshotClass.classId);

    //   var retainedSize = 0;

    //   for (final obj in objects) {
    //     retainedSize += _getObjSizeInBatches(obj);
    //   }

    //   sb.write('\n Class: ${heapSnapshotClass.name} '
    //       '\nRetained Size: ${retainedSize.bytesToMb} MB');
    // }

    return sb.toString();
  }

  int _getObjSizeInBatches(HeapSnapshotObject obj, {int batchSize = 100}) {
    var size = 0;
    final visited = <HeapSnapshotObject, bool>{};
    final queue = [obj];

    while (queue.isNotEmpty) {
      var processedInBatch = 0;
      var batchTotal = 0;

      while (queue.isNotEmpty && processedInBatch < batchSize) {
        final currentObj = queue.removeAt(0);
        if (visited[currentObj] != null && visited[currentObj]!) continue;
        visited[currentObj] = true;

        batchTotal += currentObj.shallowSize;

        queue.addAll(currentObj.successors);

        processedInBatch++;
      }

      size += batchTotal;
      print('total size is now ${size.bytesToMb} MB');
    }

    return size;
  }
}
