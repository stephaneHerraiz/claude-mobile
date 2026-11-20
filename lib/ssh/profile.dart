/// Where and as whom to connect. The private key is stored separately.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.user,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    user: j['user'] as String,
  );

  final String id;
  final String name;
  final String host;
  final int port;
  final String user;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'user': user,
  };
}
