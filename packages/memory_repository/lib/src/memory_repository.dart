import 'package:memory_repository/src/exceptions/vm_service_not_initialized_exception.dart';
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

  /// Fetches current memory usage given a particular [isolateId].
  Future<MemoryUsage> fetchMemoryData(String isolateId) async {
    if (_vmService == null) {
      throw VmServiceNotInitializedException();
    }

    final vmService = _vmService!;

    final allocationProfile = await vmService.getAllocationProfile(isolateId);
    return allocationProfile.memoryUsage ?? MemoryUsage();
  }

  /// Fetches a detailed snapshot of memory usage given an [allocationProfile],
  /// and extracts [ClassHeapStats] of members in the given [libraryPath]
  Future<String> getDetailedMemorySnapshot(
    AllocationProfile allocationProfile,
    String libraryPath,
  ) async {
    final sb = StringBuffer()..write('Detailed Memory Snapshot: ');

    final members = allocationProfile.members ?? <ClassHeapStats>[];

    final libMembers = members
        .where(
          (m) =>
              (m.classRef?.library?.uri?.contains(libraryPath) ?? false) &&
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

    return sb.toString();
  }
}
