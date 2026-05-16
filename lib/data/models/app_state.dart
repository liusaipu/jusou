class AppState {
  final String currentRoute;
  final String? currentQuery;
  final bool isLoggedIn;

  const AppState({
    this.currentRoute = 'home',
    this.currentQuery,
    this.isLoggedIn = false,
  });
}
