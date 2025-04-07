import 'dart:async';
import 'dart:isolate';

import 'package:memory_repository/src/exceptions/vm_service_not_initialized_exception.dart';
import 'package:memory_repository/src/extensions/extensions.dart';
import 'package:vm_service/vm_service.dart' hide Isolate;
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

    final sb = StringBuffer()..write('Detailed Memory Snapshot: ');

    final classes =
        snapshot.classes.where((c) => c.libraryUri.path.contains(libraryPath));

    for (final heapSnapshotClass in classes) {
      print('Gathering retained size of ${heapSnapshotClass.name}...');
      final objects =
          snapshot.objects.where((o) => o.classId == heapSnapshotClass.classId);

      var retainedSize = 0;

      for (final obj in objects) {
        retainedSize += await _getObjSizeInBatches(obj);
      }

      sb.write('\n Class: ${heapSnapshotClass.name} '
          '\nRetained Size: ${retainedSize.bytesToMb} MB');
    }

    return sb.toString();
  }

  Future<void> _processBatch(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is BatchProcessMessage) {
        print('current batch has ${message.objects.length} objects');
        var batchTotal = 0;
        final newVisitedIds = <int>{};
        final newObjects = <HeapSnapshotObject>[];

        for (final obj in message.objects) {
          if (!message.visitedIds.contains(obj.hashCode) &&
              !newVisitedIds.contains(obj.hashCode)) {
            batchTotal += obj.shallowSize;
            print('batch Total is now $batchTotal}');
            newVisitedIds.add(obj.hashCode);
            newObjects.addAll(obj.successors);
          }
        }

        sendPort.send(
          BatchResult(
            batchSize: batchTotal,
            newVisitedIds: newVisitedIds,
            newObjects: newObjects,
          ),
        );
      } else if (message == 'close') {
        print('closing receive port');
        receivePort.close();
        break;
      }
    }
  }

  Future<int> _getObjSizeInBatches(
    HeapSnapshotObject obj, {
    int batchSize = 10000,
    int numIsolates = 4,
  }) async {
    var size = 0;
    final visitedIds = <int>{};
    var queue = [obj];

    final isolates = <Isolate>[];
    final receivePortList = <ReceivePort>[];
    final sendPortList = <SendPort>[];

    for (var i = 0; i < numIsolates; i++) {
      final receivePort = ReceivePort();
      receivePortList.add(receivePort);

      print('spawning new isolate $i with receive port');
      final isolate = await Isolate.spawn(_processBatch, receivePort.sendPort);
      isolates.add(isolate);

      final sendPort = receivePortList[i].sendPort;
      sendPortList.add(sendPort);
    }

    while (queue.isNotEmpty) {
      final batches = <List<HeapSnapshotObject>>[];

      for (var i = 0; i < numIsolates && queue.isNotEmpty; i++) {
        final batchObjects = queue.take(batchSize).toList();
        queue = queue.skip(batchSize).toList();
        batches.add(batchObjects);
      }

      final batchFutures = <Future<BatchResult>>[];
      for (var i = 0; i < batches.length; i++) {
        final completer = Completer<BatchResult>();
        batchFutures.add(completer.future);

        receivePortList[i].listen((message) {
          if (message is BatchResult && !completer.isCompleted) {
            print('completing batch with size ${message.batchSize}');
            completer.complete(message);
          }
        });

        print('sending new batch to isolate $i with ${batches[i].length}');
        sendPortList[i].send(
          BatchProcessMessage(
            objects: batches[i],
            visitedIds: Set<int>.from(visitedIds),
          ),
        );
      }

      final results = await Future.wait(batchFutures);

      for (final result in results) {
        size += result.batchSize;
        visitedIds.addAll(result.newVisitedIds);
        queue.addAll(
          result.newObjects.where((obj) => !visitedIds.contains(obj.hashCode)),
        );
      }

      print('total size is now ${size.bytesToMb} MB');
    }
    for (var i = 0; i < numIsolates; i++) {
      sendPortList[i].send('close');
      receivePortList[i].close();
      isolates[i].kill();
    }

    return size;
  }
}

class BatchProcessMessage {
  const BatchProcessMessage({
    required this.objects,
    required this.visitedIds,
  });

  final List<HeapSnapshotObject> objects;
  final Set<int> visitedIds;
}

class BatchResult {
  const BatchResult({
    required this.batchSize,
    required this.newVisitedIds,
    required this.newObjects,
  });

  final int batchSize;
  final Set<int> newVisitedIds;
  final List<HeapSnapshotObject> newObjects;
}
