{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  python3,
}: let
  version = "0.90.1";
in
  buildNpmPackage {
    pname = "pi-web-ui";
    version = "0.90.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-web-ui/-/pi-web-ui-${version}.tgz";
    hash = "sha256-h+ekK3DJDz8WJsvHPGOiXW9QBeaD+t1Vc9uHbK6sGZs=";
  };

  # npm pack 的 tarball 不含 package-lock.json —— 从同版本 GitHub tag 补齐
  postPatch = ''
    cp ${fetchurl {
      url = "https://raw.githubusercontent.com/xing-shuyin/pi-web-ui/v${version}/package-lock.json";
      hash = "sha256-bERP/alrWdNO5vQpkneezIu3IhXYCVoK3QjRt4Gj0p4=";
    }} package-lock.json

    # 上游 lockfile 中 5 个 @earendil-works 嵌套依赖缺 integrity 字段，
    # 会导致 fetchNpmDeps panic（non-git dependencies should have
    # associated integrity）。这里按 registry tarball 的 sha512 SRI 补齐。
    sed -i \
      -e 's|"resolved": "https://registry.npmjs.org/@earendil-works/chord/-/chord-0.85.1.tgz"|"resolved": "https://registry.npmjs.org/@earendil-works/chord/-/chord-0.85.1.tgz",\n      "integrity": "sha512-VDlkEC3dhCzQ5fcyH1OhG19dq+6jCn+rqc/iXFivwDYGR5anwo2RCiXij9PpHhqNR5GuhhE+Er69Zi1Sn4eY6w=="|' \
      -e 's|"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.85.1.tgz"|"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.85.1.tgz",\n      "integrity": "sha512-hIXIP3eAWueAYiAl8aMvWCvvZ8Q5gT3Dip5bE5uJyIGh4+YlWRjtMLI4BaeoXoSs93zndjue61u1B/vhefLnuA=="|' \
      -e 's|"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.85.1.tgz"|"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.85.1.tgz",\n      "integrity": "sha512-+VgVIJDkDO2efYJKEEqvPTH4zmnIaXdAppGbO+vKFA9qy5PdhFiAenuFAkU+oiCSfOC4dMHDyrjdQeL4ZoC5CQ=="|' \
      -e 's|"resolved": "https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-0.85.1.tgz"|"resolved": "https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-0.85.1.tgz",\n      "integrity": "sha512-Bg/YN6kA7Swja/NQxka8xFdecb4E/auIEGF2G5A25EaQXhRnPj300/7/KpgsDDMYUzHTDAv4RyUxaQPJKW81Rw=="|' \
      -e 's|"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.85.1.tgz"|"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.85.1.tgz",\n      "integrity": "sha512-OIzw9efInmO4WOBnD4TxcTdBjmzvYJpzslkgoUro946nEGoYWg5rwv1p4fDt3/JvMx9QybryUCUwlm7j8Dreig=="|' \
      package-lock.json
  '';

  npmDepsHash = "sha256-BCJVLgB/FvojwarCsltW0WU0aF3Mdp5nzrY3MyEI7nw=";

  # fetch-npm-deps 产出的缓存条目 time=0，npm 10 视为过期需要重验证；
  # 只读 store 缓存无法写入会导致 ENOTCACHED，故复制为可写缓存
  makeCacheWritable = true;

  # tarball 已预构建（dist/ web/dist/ 齐全），不跑上游构建；node-pty 由 rebuild 阶段编译
  dontNpmBuild = true;

  nodejs = nodejs_22;
  nativeBuildInputs = [ python3 ]; # node-gyp 需要

  meta = {
    description = "Browser cockpit for AI coding agents (pi / DSH): chat, code, files, terminal, Git in one tab";
    homepage = "https://github.com/xing-shuyin/pi-web-ui";
    license = lib.licenses.mit;
    mainProgram = "pi-web-ui";
    platforms = lib.platforms.unix;
  };
}
