import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/automacao_fiscal_screen.dart';

/// Card automacao-fiscal-pastas (2026-09-10) -- tela Sistema > Automacao
/// Fiscal. NetworkCaller usa as funcoes top-level de package:http
/// diretamente (sem client injetavel), entao a chamada de rede em si nao e
/// testavel aqui sem infraestrutura adicional (mesmo padrao documentado em
/// produto_impostos_tab_test.dart) -- por isso os mapeamentos de rotulo
/// (origem/tipo de documento) foram extraidos em funcoes puras e sao
/// testados diretamente.
void main() {
  group('origemLabel', () {
    test('mapeia os 3 valores conhecidos do backend', () {
      expect(origemLabel('BOLETO'), 'Boletos');
      expect(origemLabel('SPED'), 'SPED');
      expect(origemLabel('SINTEGRA'), 'Sintegra');
    });

    test('valor desconhecido ou nulo cai no fallback', () {
      expect(origemLabel('OUTRO'), 'OUTRO');
      expect(origemLabel(null), '-');
    });
  });

  group('tipoDocumentoLabel', () {
    test('mapeia todos os tipos reconhecidos pelo classificador do backend', () {
      expect(tipoDocumentoLabel('BOLETO_FORNECEDOR'), 'Boleto Fornecedor');
      expect(tipoDocumentoLabel('FGTS'), 'FGTS');
      expect(tipoDocumentoLabel('DAE_ICMS'), 'DAE ICMS');
      expect(tipoDocumentoLabel('DARF_FEDERAL'), 'DARF Federal');
      expect(tipoDocumentoLabel('GUIA_ISS_MUNICIPAL'), 'Guia ISS');
      expect(tipoDocumentoLabel('COMPROVANTE_PAGAMENTO'), 'Comprovante de Pagamento');
    });

    test('nulo vira traco, tipo desconhecido vira "Não identificado"', () {
      expect(tipoDocumentoLabel(null), '-');
      expect(tipoDocumentoLabel('DESCONHECIDO'), 'Não identificado');
    });
  });
}
