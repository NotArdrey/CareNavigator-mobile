sealed class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class AuthenticationFailure extends RepositoryFailure {
  const AuthenticationFailure(super.message, {super.cause});
}

final class PermissionFailure extends RepositoryFailure {
  const PermissionFailure(super.message, {super.cause});
}

final class ValidationFailure extends RepositoryFailure {
  const ValidationFailure(super.message, {super.cause});
}

final class ContractUnavailableFailure extends RepositoryFailure {
  const ContractUnavailableFailure(super.message, {super.cause});
}

final class UnexpectedRepositoryFailure extends RepositoryFailure {
  const UnexpectedRepositoryFailure(super.message, {super.cause});
}
