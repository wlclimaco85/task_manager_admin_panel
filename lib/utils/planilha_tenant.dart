import 'planilha_formula.dart';
import 'planilha_tabela.dart';
import 'tenant_context.dart';

const String kColunaEmpresa = 'empresa_id';
const String kColunaParceiro = 'parceiro_id';

bool ehColunaDeTenant(String titulo) {
  final t = titulo.trim().toLowerCase();
  return t == kColunaEmpresa || t == kColunaParceiro;
}

/// Empresa e parceiro do login salvo no aparelho.
class SessaoTenant {
  final int? empresa;
  final int? parceiro;

  /// So o MASTER pode alterar os campos de empresa e parceiro.
  final bool master;

  const SessaoTenant({this.empresa, this.parceiro, this.master = false});

  factory SessaoTenant.doLogin() => SessaoTenant(
      empresa: TenantContext.empresaId, parceiro: TenantContext.parceiroId, master: TenantContext.isMaster);

  Map<String, String> get valores => {
        if (empresa != null) kColunaEmpresa: '$empresa',
        if (empresa != null && parceiro != null) kColunaParceiro: '$parceiro',
      };
}

/// Colunas (indice) cujo titulo na linha 1 e' empresa_id ou parceiro_id.
Map<int, String> colunasDeTenant(Map<String, String> celulas) {
  final saida = <int, String>{};
  for (final e in celulas.entries) {
    final p = posicao(e.key);
    if (p != null && p.$1 == 0 && ehColunaDeTenant(e.value)) saida[p.$2] = e.value.trim().toLowerCase();
  }
  return saida;
}

/// Planilha nova: so os titulos de empresa e parceiro (A1, B1).
Map<String, String> cabecalhosDoTenant(SessaoTenant sessao) {
  var c = 0;
  return {for (final nome in sessao.valores.keys) endereco(0, c++): nome};
}

/// Nada alem dos titulos de empresa e parceiro: importar pode substituir sem perguntar.
bool soCabecalhosDoTenant(Map<String, String> celulas) {
  final colunas = colunasDeTenant(celulas);
  return celulas.keys.every((ref) {
    final p = posicao(ref);
    return p != null && p.$1 == 0 && colunas.containsKey(p.$2);
  });
}

/// Mesma regra do servidor (PlanilhaTenant): as colunas existem sempre (as que faltam entram no fim, sem deslocar
/// formulas) e toda linha com dados leva o valor do login. O MASTER so tem os campos VAZIOS preenchidos.
/// Sem parceiro no login, uma coluna parceiro_id que ja exista nao e' tocada.
Map<String, String> fixarTenant(Map<String, String> celulas, SessaoTenant sessao) {
  final saida = Map<String, String>.of(celulas)..removeWhere((_, v) => v.isEmpty);
  final valores = sessao.valores;
  if (saida.isEmpty || valores.isEmpty) return saida;

  final colunas = colunasDeTenant(saida);
  var ultima = -1;
  for (final ref in saida.keys) {
    final p = posicao(ref);
    if (p != null && p.$2 > ultima) ultima = p.$2;
  }
  for (final nome in valores.keys) {
    if (!colunas.containsValue(nome) && ultima + 1 < kPlanilhaMaxColunas) {
      ultima++;
      saida[endereco(0, ultima)] = nome;
      colunas[ultima] = nome;
    }
  }

  final citadas = <int>{}, comDados = <int>{};
  for (final ref in saida.keys) {
    final p = posicao(ref);
    if (p == null || p.$1 == 0) continue;
    citadas.add(p.$1);
    if (!colunas.containsKey(p.$2)) comDados.add(p.$1);
  }
  for (final coluna in colunas.entries) {
    final valor = valores[coluna.value];
    if (valor == null) continue;
    for (final linha in citadas) {
      final ref = endereco(linha, coluna.key);
      if (comDados.contains(linha)) {
        if (!sessao.master || !saida.containsKey(ref)) saida[ref] = valor;
      } else if (!sessao.master || saida[ref] == valor) {
        saida.remove(ref);
      }
    }
  }
  return saida;
}

/// Ao criar tela a partir de planilha: empresa e parceiro nao viram campos editaveis (a tela os tem bloqueados).
TabelaDaPlanilha semColunasDeTenant(TabelaDaPlanilha t) {
  final manter = [
    for (var i = 0; i < t.colunas.length; i++)
      if (!ehColunaDeTenant(t.colunas[i])) i
  ];
  if (manter.length == t.colunas.length) return t;
  return TabelaDaPlanilha(
    [for (final i in manter) t.colunas[i]],
    [
      for (final l in t.linhas)
        if (manter.any((i) => l[i].isNotEmpty)) [for (final i in manter) l[i]]
    ],
    t.ignoradas,
    t.comErro,
  );
}
