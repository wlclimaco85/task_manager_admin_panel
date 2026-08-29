import '../../services/network_caller.dart';
import 'field_config.dart';
import 'generic_grid_screen.dart';

/// Fabrica um `optionsLoader` de [FieldConfig] para dropdowns de FK remota
/// (Aplicativo/Parceiro/Empresa/Setor etc.). A funcao retornada recebe o
/// [NetworkCaller] ja existente do form chamador (nunca cria um proprio),
/// faz `GET url`, reutiliza [GenericGridScreen.extractRows] (evita duplicar
/// a normalizacao de `data`/`dados`/`content`) e mapeia cada linha para uma
/// [DropdownOption].
Future<List<DropdownOption>> Function(NetworkCaller) remoteDropdownSource({
  required String url,
  required String valueKey,
  required String Function(Map<String, dynamic> row) labelBuilder,
}) {
  return (NetworkCaller caller) async {
    final response = await caller.getRequest(url);
    if (!response.isSuccess) return const [];
    final rows = GenericGridScreen.extractRows(response.body);
    return rows
        .map((row) => DropdownOption(
              value: row[valueKey],
              label: labelBuilder(row),
            ))
        .toList();
  };
}
