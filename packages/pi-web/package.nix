{
  lib,
  stdenv,
  stdenvNoCC,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  curl,
  cacert,
}: let
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "agegr";
    repo = "pi-web";
    tag = "v${version}";
    sha256 = "sha256-XJm2SKqG6T6mGmKDw3eKkPP+iywXA8ehBu5Y1W/dFNw=";
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

  notoSansMonoFonts =
    stdenvNoCC.mkDerivation {
      pname = "noto-sans-mono-woff2";
      version = "v37";
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

    npmDepsHash = "sha256-j6KF0HnjNw7dCyuPJN24FNl2f2hLbwPCkCC0xsLRSVc=";

    # devDependencies 里的 playwright 带 postinstall（会下载浏览器），
    # 故所有依赖脚本先一律跳过；node-pty 的原生编译在 postBuild 定点补回。
    npmFlags = ["--ignore-scripts"];

    nativeBuildInputs = [python3]; # node-gyp（node-pty）

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
      # npmConfigHook 的 npm ci / npm rebuild 都带 --ignore-scripts，node-pty 的
      # 原生模块没被编译。node-gyp 由 buildNpmPackage 通过 npm_config_node_gyp
      # 注入，无需自己链进 .bin。放在 build 之后是因为 next.config.ts 把
      # node-pty 列进 serverExternalPackages，webpack 不打包它，构建期用不到。
      npm rebuild node-pty

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

    meta = {
      description = "Web UI for the pi coding agent";
      homepage = "https://github.com/agegr/pi-web";
      license = lib.licenses.mit;
      mainProgram = "pi-web";
      platforms = lib.platforms.unix;
    };
  }
