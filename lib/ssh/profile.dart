/// An SSH server to go through to reach a host it alone can see.
class JumpHost {
  const JumpHost({required this.host, required this.port, required this.user});

  factory JumpHost.fromJson(Map<String, dynamic> j) => JumpHost(
    host: j['host'] as String,
    port: j['port'] as int,
    user: j['user'] as String,
  );

  final String host;
  final int port;
  final String user;

  Map<String, dynamic> toJson() => {'host': host, 'port': port, 'user': user};
}

/// Where and as whom to connect. The private key is stored separately.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    this.jump,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    user: j['user'] as String,
    jump: j['jump'] == null
        ? null
        : JumpHost.fromJson(j['jump'] as Map<String, dynamic>),
  );

  final String id;
  final String name;
  final String host;
  final int port;
  final String user;

  /// When set, [host] is reached from this server, with the same key.
  final JumpHost? jump;

  /// `user@host:port`, followed by the jump host when there is one.
  String get address =>
      '$user@$host:$port${jump == null ? '' : ' via ${jump!.host}'}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'user': user,
    'jump': ?jump?.toJson(),
  };
}
