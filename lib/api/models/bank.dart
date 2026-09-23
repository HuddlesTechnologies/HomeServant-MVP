class Bank {
  const Bank({required this.name, required this.code});

  final String name;
  final String code;

  factory Bank.fromApi(Map<String, dynamic> json) => Bank(
    name: json['name'] as String,
    code: json['code'] as String,
  );
}
