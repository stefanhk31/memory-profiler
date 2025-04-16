import 'dart:typed_data';

import 'package:memory_repository/src/models/retainer_result.dart';
import 'package:vm_service/vm_service.dart';

extension GetRetainersExt on HeapSnapshotGraph {
  RetainersResult get retainers {
    final retainers = Uint32List(objects.length);
    final retainedSizes = Uint32List(objects.length);

    var cut = [1];

    while (cut.isNotEmpty) {
      final nextCut = <int>[];
      for (final index in cut) {
        for (final ref in objects[index].references) {
          if (retainers[ref] != 0) continue;
          retainers[ref] = index;
          retainedSizes[ref] = objects[index].shallowSize;

          addRetainedSize(
            index: ref,
            retainedSizes: retainedSizes,
            retainers: retainers,
            shallowSize: objects[index].shallowSize,
          );
          if (!isWeak(ref)) nextCut.add(ref);
        }
      }
      cut = nextCut;
    }

    return RetainersResult(
      retainers: retainers,
      retainedSizes: retainedSizes,
    );
  }

  Set<int> get weakClasses {
    final weakClassesToFind = <String, String>{
      '_WeakProperty': 'dart:core',
      '_WeakReferenceImpl': 'dart:core',
      'FinalizerEntry': 'dart:_internal',
    };
    final result = <int>{};

    for (final graphClass in classes) {
      if (weakClassesToFind.containsKey(graphClass.name) &&
          weakClassesToFind[graphClass.name] == graphClass.libraryName) {
        result.add(graphClass.classId);
        weakClassesToFind.remove(graphClass.name);
        if (weakClassesToFind.isEmpty) continue;
      }
    }

    return result;
  }

  bool isWeak(int index) {
    final obj = objects[index];
    if (obj.references.isEmpty) return true;
    final classId = obj.classId;
    return weakClasses.contains(classId);
  }
}

void addRetainedSize({
  required int index,
  required Uint32List retainedSizes,
  required Uint32List retainers,
  required int shallowSize,
}) {
  final addedSize = shallowSize;
  retainedSizes[index] = addedSize;

  while (retainers[index] > 0) {
    index = retainers[index];
    retainedSizes[index] += addedSize;
  }
}
