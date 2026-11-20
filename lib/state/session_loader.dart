import '../core/session_listing.dart';
import '../ssh/ssh_service.dart';

/// Lists the server's sessions, newest first. Titles and working directories
/// are read for the newest [headLimit] only: each costs one remote command.
Future<List<SessionInfo>> loadSessions(
  SshService ssh,
  DateTime now, {
  int headLimit = 30,
}) async {
  final sessions = parseListing(await ssh.run(listSessionsCommand), now);
  return [
    for (final (i, s) in sessions.indexed)
      if (i < headLimit) withHead(s, await ssh.run(headCommand(s.path))) else s,
  ];
}
