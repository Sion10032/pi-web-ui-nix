{
  lib,
  stdenv,
  stdenvNoCC,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  autoPatchelfHook,
  curl,
  cacert,
}:
let
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "agegr";
    repo = "pi-web";
    tag = "v${version}";
    sha256 = "sha256-46agQfK0336I4FbrOCnwd3dQ348IN1QiRvWqe+zcfW0=";
  };

  # next/font/google 在构建期从 fonts.googleapis.com 取字体 CSS、再从
  # fonts.gstatic.com 取各子集 woff2；nix 沙箱里没有网络，上游构建因此会在
  # `next build` 阶段失败。Next 为此留了官方钩子
  # NEXT_FONT_GOOGLE_MOCKED_RESPONSES（其自身 e2e 用它在离线环境跑）：
  # 置为 JS 模块路径后，CSS 与该 CSS 引用的字体文件都从本地读取。
  #
  # 这里用一个 FOD 把"Google 当时返回的 CSS + 它引用的 7 个 woff2 子集"
  # 原样抓进 store，构建期再把 CSS 里的 gstatic URL 重写成 store 内路径，
  # 于是产物里的字体与联网构建同源（不是用替身字体糊过去）。
  # 字体版本或上游 font 配置变动时，本 FOD 的 hash 或 mock 的 URL 键会失配
  # 并让构建硬失败，需要人工重新固定。
  notoFontsCssUrl = "https://fonts.googleapis.com/css2?family=Noto+Sans+Mono:wght@100..900&display=swap";

  notoSansMonoFonts = stdenvNoCC.mkDerivation {
    pname = "noto-sans-mono-woff2";
    version = "0.16.0";
    # 递归 hash：输出是一个目录（CSS + 若干 woff2），不是单个文件
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-x33I3s8poqNn/eB0tze/ej1fZS9ikj8YS+M/DDSCKJ8=";

    nativeBuildInputs = [
      curl
      cacert
    ];

    # 固定 Chrome 的 UA：Google 按 UA 决定返回的字体格式，只有现代 UA 才给 woff2
    buildCommand = ''
      mkdir -p $out
      curl -fsSL \
        -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36' \
        '${notoFontsCssUrl}' -o $out/fonts.css
      grep -o 'https://fonts\.gstatic\.com/[^)]*' $out/fonts.css | sort -u | while IFS= read -r url; do
        curl -fsSL "$url" -o "$out/$(basename "$url")"
      done
      [ "$(find $out -name '*.woff2' | wc -l)" -gt 0 ]
    '';
  };
in
# 为什么这里走 npm（pi-web-ui 被迫走 pnpm）：pi-web 锁的 @earendil-works/pi-*
# 1.4.0 树内 integrity 完整，fetchNpmDeps 不会 panic。上游 tag 自带
# package-lock.json，仓库内不存 lock 副本：升级只需改 tag + 迭代 hash，没有
# lock 转译环节（见 dev/pi-web/upgrade.sh）。
buildNpmPackage {
  pname = "pi-web";
  inherit version src;
  nodejs = nodejs_22;

  npmDepsHash = "sha256-eXfQPNaJkgnKX73LwmLJNeNTpmaKVluiscrftVonINY=";

  # devDependencies 里的 playwright 带 postinstall（会下载浏览器），故所有
  # 依赖脚本一律跳过。node-pty 1.2.0-beta.15 的 tarball 自带
  # prebuilds/<platform>/pty.node（node-gyp-build 运行时加载），无需编译；
  # 若上游某版停发 prebuilds 或新平台缺 prebuilds，需改用
  # `npm rebuild node-pty --ignore-scripts=false` 定点编译并补回 python3
  # （npm rebuild 默认读 npmConfigHook 写入 .npmrc 的 ignore-scripts，
  # 不带该 flag 时是 no-op——实测本包的 pty.node 全部来自 prebuilds，
  # 产物中无 build/Release）。
  npmFlags = [ "--ignore-scripts" ];

  # node-pty 1.2.0-beta.15 的 tarball 自带六平台 prebuilds（含 linux），
  # --ignore-scripts 下没有本地编译，pty.node 是上游 CI 预编译的 ELF：
  # rpath 为空，裸 ldd 报 libstdc++.so.6 not found，运行期靠 node 进程
  # 自带的 libstdc++ 搭便车（dlopen 复用同 soname 已加载的库）。
  # autoPatchelfHook 把本环境 libstdc++ 的 store 路径写进 rpath，让
  # pty.node 自洽，不再依赖宿主 node 链接的符号版本（上游换新工具链
  # 编出的 GLIBCXX 符号若超出 nixpkgs node 的 libstdc++ 就会运行期炸）。
  #
  # 必须 gate 在 Linux：autoPatchelfHook 的 hook 无平台判断
  # （`postFixupHooks+=(autoPatchelfPostFixup)`），它在 darwin 上也会扫
  # $out，而产物里躺着 node-pty / pi-tui 的 **linux** prebuilds（真 ELF）。
  # macOS 上 patchelf 不存在，于是报 `patchelf: command not found`，随后
  # 尝试打开 ELF 的 interpreter 而抛 `ELFError: Magic number does not
  # match`，整个构建硬失败（CI 的 macos-15 job 就是这么挂的）。
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  # @earendil-works/pi-tui 也带预编译 ELF（native/…/linux-platform-x11.node，
  # 链接 libxcb）：那是 pi 终端 TUI 的 X11 后端，Web 服务场景不会加载，
  # 为它引入整棵 X11 依赖树不值得，故显式忽略（与 pi-web-ui 既有姿态
  # 一致：它的 pi-tui 同样未 patch，一直靠不加载过关）。
  autoPatchelfIgnoreMissingDeps = lib.optionals stdenv.hostPlatform.isLinux [ "libxcb.so.1" ];

  env.NEXT_TELEMETRY_DISABLED = "1";

  postPatch = ''
    # 把 Next 的字体请求全部指到本地：CSS 内容取自 FOD 里 Google 的原样响应，
    # 只把 gstatic URL 换成同目录下的文件名（fetchFontFile 在 mock 模式下对
    # 以 / 开头的 URL 直接 fs.readFileSync）。
    cat > mocked-google-fonts.js <<EOF
    const fs = require("node:fs");
    const css = fs
      .readFileSync("${notoSansMonoFonts}/fonts.css", "utf8")
      .replace(/https:\/\/fonts\.gstatic\.com\/[^)]*\/([^/)]+\.woff2)/g, (_, file) => "${notoSansMonoFonts}/" + file);
    module.exports = { "${notoFontsCssUrl}": css };
    EOF
    export NEXT_FONT_GOOGLE_MOCKED_RESPONSES="$PWD/mocked-google-fonts.js"
  '';

  postBuild = ''
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # --ignore-scripts 跳过了上游 postinstall（bin/prepare-terminal.js），
      # 它唯一的职责是给 macOS 的 spawn-helper 补执行位；这里等价复刻。
      for dir in node_modules/node-pty/build/Release node_modules/node-pty/build/Debug node_modules/node-pty/prebuilds/darwin-*; do
        if [ -f "$dir/spawn-helper" ]; then
          chmod +x "$dir/spawn-helper"
        fi
      done
    ''}
  '';

  # 只保留本平台的预编译产物：node-pty 的 tarball 带六平台 prebuilds，pi-tui 带
  # native/{darwin,linux,win32}；node-gyp-build 运行期按 process.platform /
  # process.arch 选目录，其余全是死重量（实测 win32 的两个 pty.node 各 12MB，
  # 占 566M 产物里的 24M）。除了体积，它们还会踩到平台专属的 hook：
  #   - 在 macOS 上，linux 的 ELF 让 audit-tmpdir 逐个调用不存在的 patchelf
  #     （纯噪音，不失败）；
  #   - 在 Linux 上，auto-patchelf 会给永远不会加载的 aarch64 ELF 写入 x86_64
  #     的 rpath（无害但荒谬）。
  # 先例：nixpkgs 的 pi-coding-agent 包同样在 darwin 上删除 Linux 二进制。
  #
  # 挂在 postInstall 而非 postFixup 是有意的：audit-tmpdir 在 fixupPhase 的
  # fixupOutputHooks 里运行，删除必须早于它（npmInstallHook 的 installPhase
  # 会 runHook postInstall）。
  postInstall =
    let
      inherit (stdenv.hostPlatform) isDarwin isAarch64;
      keepPty = "${if isDarwin then "darwin" else "linux"}-${if isAarch64 then "arm64" else "x64"}";
      keepTui = if isDarwin then "darwin" else "linux";
      drop = keep: all: builtins.filter (p: p != keep) all;
      rmLine = rel: ''rm -rf "$nm/${rel}"'';
    in
    ''
      nm="$out/lib/node_modules/@agegr/pi-web/node_modules"
      ${lib.concatMapStringsSep "\n" rmLine (
        map (p: "node-pty/prebuilds/${p}") (
          drop keepPty [
            "darwin-arm64"
            "darwin-x64"
            "linux-arm64"
            "linux-x64"
            "win32-arm64"
            "win32-x64"
          ]
        )
      )}
      ${lib.concatMapStringsSep "\n" rmLine (
        map (p: "@earendil-works/pi-tui/native/${p}") (
          drop keepTui [
            "darwin"
            "linux"
            "win32"
          ]
        )
      )}
    '';

  meta = {
    description = "Web UI for the pi coding agent";
    homepage = "https://github.com/agegr/pi-web";
    license = lib.licenses.mit;
    mainProgram = "pi-web";
    platforms = lib.platforms.unix;
  };
}
