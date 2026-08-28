/// Modelo de sessao do Painel do Dono — versao enxuta e propria deste app
/// (nao copiada do LoginModel do cliente, que tem dezenas de campos
/// especificos de academia/parceiro). Contem so o necessario para a Fase 1:
/// identidade do login, token JWT, empresa e roles.
class EmpresaRef {
  final int id;
  final String? nome;

  const EmpresaRef({required this.id, this.nome});

  factory EmpresaRef.fromJson(Map<String, dynamic> json) => EmpresaRef(
        id: (json['id'] as num).toInt(),
        nome: json['nome'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, if (nome != null) 'nome': nome};
}

class RoleRef {
  final int id;
  final String? nome;

  const RoleRef({required this.id, this.nome});

  factory RoleRef.fromJson(Map<String, dynamic> json) => RoleRef(
        id: (json['id'] as num).toInt(),
        nome: json['nome'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, if (nome != null) 'nome': nome};
}

class LoginInfo {
  final int id;
  final String? email;
  final String? nome;
  final String? tipoLogin;
  final EmpresaRef? empresa;
  final List<RoleRef>? roles;

  const LoginInfo({
    required this.id,
    this.email,
    this.nome,
    this.tipoLogin,
    this.empresa,
    this.roles,
  });

  factory LoginInfo.fromJson(Map<String, dynamic> json) => LoginInfo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String?,
        nome: json['nome'] as String?,
        tipoLogin: json['tipoLogin'] is Map
            ? (json['tipoLogin'] as Map)['name'] as String?
            : json['tipoLogin'] as String?,
        empresa: json['empresa'] is Map
            ? EmpresaRef.fromJson(Map<String, dynamic>.from(json['empresa']))
            : null,
        roles: (json['roles'] as List?)
            ?.map((r) => RoleRef.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (email != null) 'email': email,
        if (nome != null) 'nome': nome,
        if (tipoLogin != null) 'tipoLogin': tipoLogin,
        if (empresa != null) 'empresa': empresa!.toJson(),
        if (roles != null) 'roles': roles!.map((r) => r.toJson()).toList(),
      };
}

class LoginModel {
  final String? status;
  final String? token;
  final LoginInfo? login;

  const LoginModel({this.status, this.token, this.login});

  factory LoginModel.fromJson(Map<String, dynamic> json) => LoginModel(
        status: json['status'] as String?,
        token: json['token'] as String?,
        login: json['login'] is Map
            ? LoginInfo.fromJson(Map<String, dynamic>.from(json['login']))
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (token != null) 'token': token,
        if (login != null) 'login': login!.toJson(),
      };
}
