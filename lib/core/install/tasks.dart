typedef TaskProgress = void Function(double p01, String message);

abstract class InstallTask {
  String get name;
  Future<void> run(TaskProgress progress);
}

class TaskQueue {
  final List<InstallTask> _tasks = [];
  void add(InstallTask task) => _tasks.add(task);

  Future<void> run(TaskProgress progress) async {
    final total = _tasks.isEmpty ? 1 : _tasks.length;
    for (int i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      final base = i / total;
      final slice = 1.0 / total;
      await task.run((p, msg) {
        final pp = (base + slice * p).clamp(0.0, 1.0);
        progress(pp, msg);
      });
    }
  }
}

class FnTask implements InstallTask {
  @override
  final String name;
  final Future<void> Function(TaskProgress progress) _fn;
  FnTask(this.name, this._fn);

  @override
  Future<void> run(TaskProgress progress) => _fn(progress);
}

