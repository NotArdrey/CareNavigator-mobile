class PageRequest {
  const PageRequest({this.limit = 20, this.cursor}) : assert(limit > 0);

  final int limit;
  final String? cursor;
}

class PageResult<T> {
  const PageResult({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
