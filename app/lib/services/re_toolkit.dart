/// Reverse Engineering Toolkit —— 只负责**生成命令字符串**。
///
/// 本文件不执行任何东西。执行有两条路，都必须先把完整命令展示给用户并得到确认：
///  · 反编译 / 重打包 / 签名：交给内置终端（PRoot + Alpine，见 `terminal_screen.dart`），
///    不再依赖 Termux；
///  · Frida：需要真机 root，沙箱里跑不了，所以仍走 Termux（可选）。
///
/// ## 路径约定
/// 沙箱里看不到手机存储（沙箱不 bind 宿主系统目录），所以输入/输出都放在沙箱内的
/// `/workspace/re`。把文件弄进去的办法：在终端里 `wget -O /workspace/re/app.apk <URL>`。
class ReToolkit {
  ReToolkit._();

  /// 沙箱内的工作目录。
  static const baseDir = '/workspace/re';

  /// 仅 Frida（Termux 路线）使用：Termux 能读到的共享存储目录。
  static const termuxBaseDir = '/storage/emulated/0/Download/HeraclesRE';

  static const defaultApk = '$baseDir/app.apk';
  static const defaultSrcDir = '$baseDir/app_src';
  static const defaultOutApk = '$baseDir/app_patched.apk';
  static const defaultKeystore = '$baseDir/heracles.jks';
  static const defaultScript = '$termuxBaseDir/hook.js';

  /// 为 shell 单引号包裹转义：`it's` -> `'it'\''s'`。
  /// 所有来自用户输入的路径与口令都必须经过这里，不能直接拼接。
  static String q(String s) => "'${s.replaceAll("'", "'\\''")}'";

  static String _dirOf(String p) {
    final i = p.lastIndexOf('/');
    return i <= 0 ? '.' : p.substring(0, i);
  }

  // ---- 0. 准备 ----
  static String prepareFolder() =>
      'mkdir -p ${q(baseDir)} && ls -la ${q(baseDir)}';

  /// 逐个装、逐个报错：某个包不在仓库里时只影响它自己，并打印 [FAILED]。
  /// ⚠️ apktool / jadx 是否在 Alpine 仓库里未经真机验证。
  static String installTools() =>
      'apk update ; for p in openjdk17-jre-headless zip unzip apktool jadx ; '
      'do apk add --no-cache \$p || echo "[FAILED] \$p" ; done';

  // ---- 1. 反编译 ----
  static String apktoolDecode(String apk, String outDir) =>
      'apktool d -f ${q(apk)} -o ${q(outDir)}';

  static String jadxDecode(String apk, String outDir) =>
      'jadx -d ${q(outDir)} ${q(apk)}';

  // ---- 2. 重打包与签名 ----
  static String apktoolBuild(String srcDir, String outApk) =>
      'apktool b ${q(srcDir)} -o ${q(outApk)}';

  /// zipalign 必须在 apksigner 之前执行（v2+ 签名要求 4 字节对齐）。
  static String zipalign(String inApk, String outApk) =>
      'zipalign -f -v 4 ${q(inApk)} ${q(outApk)}';

  /// 内置终端没有 stdin，apksigner 不能交互式问口令，所以走环境变量 `KSPASS`。
  /// ⚠️ 口令会出现在命令回显里，只适合本地测试用的临时 keystore。
  static String apksign(
          String alignedApk, String keystore, String outApk, String pass) =>
      'KSPASS=${q(pass)} apksigner sign --ks ${q(keystore)} '
      '--ks-pass env:KSPASS --out ${q(outApk)} ${q(alignedApk)}';

  /// 同理：`-dname` 避免交互式问姓名，口令走 `-storepass:env`。
  static String keystore(String path, String pass) =>
      'mkdir -p ${q(_dirOf(path))} && KSPASS=${q(pass)} keytool -genkeypair -v '
      '-keystore ${q(path)} -alias heracles -keyalg RSA -keysize 2048 '
      '-validity 10000 -storepass:env KSPASS -keypass:env KSPASS '
      '-dname "CN=Heracles RE"';

  // ---- 3. Frida（需要 root，走 Termux）----
  static String setupStorage() => 'termux-setup-storage';

  static String installFrida() => 'pip install frida-tools';

  static const fridaServerPath = '/data/local/tmp/frida-server';

  /// 在设备上以 root 启动 frida-server，监听本机 27042 端口。
  static String fridaServerStart() => "su -c '$fridaServerPath -D' &";

  /// 通过本机端口连接已运行的 frida-server，并加载脚本。
  static String fridaLoad(String package, String script) =>
      'frida -H 127.0.0.1:27042 -f ${q(package)} -l ${q(script)}';
}
