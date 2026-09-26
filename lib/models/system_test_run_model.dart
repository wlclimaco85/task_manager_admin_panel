class SystemTestRunModel {
  final String runId, marker, environment, status;
  final String? currentStep, lastError;
  final int progressPercent, totalOperations, completedOperations;
  final int successCount, failureCount, cleanedCount, residueCount;

  const SystemTestRunModel(
      {required this.runId,
      required this.marker,
      required this.environment,
      required this.status,
      this.currentStep,
      required this.progressPercent,
      required this.totalOperations,
      required this.completedOperations,
      required this.successCount,
      required this.failureCount,
      required this.cleanedCount,
      required this.residueCount,
      this.lastError});

  factory SystemTestRunModel.fromJson(Map<String, dynamic> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;
    return SystemTestRunModel(
        runId: json['runId']?.toString() ?? '',
        marker: json['marker']?.toString() ?? '',
        environment: json['environment']?.toString() ?? '',
        status: json['status']?.toString() ?? 'PENDING',
        currentStep: json['currentStep']?.toString(),
        progressPercent: number('progressPercent'),
        totalOperations: number('totalOperations'),
        completedOperations: number('completedOperations'),
        successCount: number('successCount'),
        failureCount: number('failureCount'),
        cleanedCount: number('cleanedCount'),
        residueCount: number('residueCount'),
        lastError: json['lastError']?.toString());
  }
  bool get isActive =>
      const {'PENDING', 'RUNNING', 'CLEANING'}.contains(status);
}

class SystemTestEventModel {
  final int sequence;
  final String step, level, message;
  const SystemTestEventModel(
      {required this.sequence,
      required this.step,
      required this.level,
      required this.message});
  factory SystemTestEventModel.fromJson(Map<String, dynamic> json) =>
      SystemTestEventModel(
          sequence: (json['eventSequence'] as num?)?.toInt() ?? 0,
          step: json['stepName']?.toString() ?? '',
          level: json['level']?.toString() ?? 'INFO',
          message: json['message']?.toString() ?? '');
}
