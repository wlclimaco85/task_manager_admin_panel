/// Nomes (minusculos) dos parametros :nome do SELECT. Empresa e parceiro vem do login, entao ficam de fora.
List<String> parametrosDoSelect(String sql) => {
      for (final m in RegExp(r'(?<![:\w]):([A-Za-z_]\w*)').allMatches(sql)) m[1]!.toLowerCase()
    }.where((p) => p != 'empresaid' && p != 'parceiroid').toList();

/// Coluna de relatorio/dashboard preenchida por SELECT: cada :parametro vem de outra coluna da mesma linha.
class CampoCalculado {
  final String coluna;
  final String sql;

  /// Parametro do SELECT -> nome da coluna do resultado.
  final Map<String, String> parametros;

  const CampoCalculado({required this.coluna, required this.sql, this.parametros = const {}});

  factory CampoCalculado.fromJson(Map<String, dynamic> j) => CampoCalculado(
        coluna: '${j['coluna'] ?? ''}',
        sql: '${j['sql'] ?? ''}',
        parametros: {for (final e in ((j['parametros'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      );

  Map<String, dynamic> toJson() => {'coluna': coluna, 'sql': sql, 'parametros': parametros};

  static List<CampoCalculado> lista(Object? j) =>
      [for (final c in (j as List?) ?? const []) CampoCalculado.fromJson(c as Map<String, dynamic>)];
}
