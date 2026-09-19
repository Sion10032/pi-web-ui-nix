{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs_22,
  python3,
}: let
  version = "0.90.1";

  src = fetchFromGitHub {
    owner = "xing-shuyin";
    repo = "pi-web-ui";
    tag = "v${version}";
    sha256 = "sha256-NcT4tmNLFHiF/efwuKVvnfJQW2QJMh9qAmzHMcJtDvw=";
  };
in
  # 为什么用 pnpm 而不是 buildNpmPackage：
  # @earendil-works/pi-coding-agent 发布的 tarball 内嵌 npm-shrinkwrap.json，
  # 其中 5 个 @earendil-works/* 依赖缺 integrity，npm 解析时会整树继承该状态
  # （fresh npm install 也复现），导致 fetchNpmDeps panic。pnpm 不解析依赖内嵌的
  # shrinkwrap，不存在此问题。
  #
  # pnpm-lock.yaml 由上游同版本 tag 的 package-lock.json 经 `pnpm import` 转译：
  # 版本忠实保留，缺失的 integrity 由 registry 元数据自动补齐。升级时需重新生成，
  # 见 README 的升级流程。
  stdenv.mkDerivation (finalAttrs: {
    pname = "pi-web-ui";
    inherit version src;

    postPatch = ''
      cp ${./pnpm-lock.yaml} pnpm-lock.yaml
      # pnpm ≥11 用 allowBuilds 映射批准依赖的构建脚本（onlyBuiltDependencies 已废弃）；
      # 键名来自 ERR_PNPM_IGNORED_BUILDS 提示，上游依赖变化时按新提示更新（见 README 升级流程）
      cat > pnpm-workspace.yaml <<'YAML'
      allowBuilds:
        "@google/genai": true
        electron-winstaller: true
        esbuild: true
        node-pty: true
        protobufjs: true
      YAML
    '';

    pnpmDeps = fetchPnpmDeps {
      pname = finalAttrs.pname;
      inherit (finalAttrs) src;
      inherit (finalAttrs) postPatch;
      fetcherVersion = 4;
      # pnpm ≥ 12 默认启用 minimumReleaseAge 供应链策略，会拒绝发布不足 N 小时的包；
      # 本项目依赖上游发布当天即打包，而 pnpm-lock.yaml 是 git 内版本冻结、经
      # review 的产物，策略针对的浮动解析风险不适用，故显式关闭。
      prePnpmInstall = ''
        pnpm config set minimum-release-age 0
      '';
      hash = "sha256-amb9CcAj4VqVudJBtyUC1eMekjXu5RleeiiYld4zjdc=";
    };

    nativeBuildInputs = [
      pnpm
      pnpmConfigHook
      nodejs_22 # build 脚本内部链式调用 npm run build:web 等
      python3 # node-gyp（node-pty 原生编译）
    ];

    # GitHub tag 不含 dist/ web/dist/ 构建产物（只存在于 npm tarball），
    # 必须真跑上游构建；node-pty 由 pnpm rebuild 阶段编译
    buildPhase = ''
      runHook preBuild
      # node-pty 的 install 脚本以 `node-gyp` 命令行调用编译；node-gyp 不在其自身
      # 依赖里，把 lock 钉住的树内 node-gyp 暴露到 .bin 并加入 PATH
      mkdir -p node_modules/.bin
      ln -sf $PWD/node_modules/.pnpm/node-gyp@*/node_modules/node-gyp/bin/node-gyp.js node_modules/.bin/node-gyp
      export PATH="$PWD/node_modules/.bin:$PATH"
      pnpm rebuild --pending
      pnpm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      # 清理 buildPhase 注入的绝对路径符号链接（指向 /build，复制进 $out 会悬空）
      rm -f node_modules/.bin/node-gyp
      mkdir -p $out/lib/node_modules/pi-web-ui $out/bin
      cp -a . $out/lib/node_modules/pi-web-ui/
      patchShebangs $out/lib/node_modules/pi-web-ui/bin/pi-web-ui.mjs
      ln -s ../lib/node_modules/pi-web-ui/bin/pi-web-ui.mjs $out/bin/pi-web-ui
      runHook postInstall
    '';

    meta = {
      description = "Browser cockpit for AI coding agents (pi / DSH): chat, code, files, terminal, Git in one tab";
      homepage = "https://github.com/xing-shuyin/pi-web-ui";
      license = lib.licenses.mit;
      mainProgram = "pi-web-ui";
      platforms = lib.platforms.unix;
    };
  })
