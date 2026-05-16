/// 阿里云盘转存服务预留接口。
///
/// 当前 App 的可用闭环是打开分享链接、复制链接/提取码、收藏和反馈失效。
/// 真正的一键转存需要 OAuth 应用配置、分享 token、文件列表、目标目录和转存状态流。
class AliyunDriveService {
  String? _accessToken;

  bool get isLoggedIn => _accessToken != null;

  bool get isAvailable => false;

  /// 授权登录（OAuth）
  Future<void> login(String authCode) async {
    throw UnsupportedError('阿里云盘 OAuth 尚未接入，当前请使用打开网盘链接。');
  }

  /// 转存分享资源
  /// 返回转存后的文件 ID
  Future<String> saveToDrive({
    required String shareUrl,
    String? sharePwd,
  }) async {
    throw UnsupportedError('阿里云盘一键转存尚未接入，当前请使用打开网盘链接。');
  }

  /// 清除登录状态
  void logout() {
    _accessToken = null;
  }
}
