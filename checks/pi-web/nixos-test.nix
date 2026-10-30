{
  pkgs,
  self,
}:
pkgs.testers.nixosTest {
  name = "pi-web";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ self.nixosModules.pi-web ];

      users.users.alice = {
        isNormalUser = true;
        home = "/home/alice";
      };

      services.pi-web = {
        enable = true;
        user = "alice";
        port = 30141;
        # 走一次非默认的 env 注入路径：password 应出现在服务环境里
        # （选项描述已注明明文可见性，这里正向验证同一事实）
        password = "test";
      };
    };

  # 终端 API（node-pty 运行期的 spawn）不在本 VM 冒烟范围内：机器里没有浏览器，
  # 上游 e2e（npm run test:terminal / test:e2e）覆盖浏览器面。首验时人工跑一次
  # 终端面板即可，不在此编造未知端点。
  testScript = ''
    machine.wait_for_unit("pi-web.service")
    machine.wait_for_open_port(30141)
    machine.succeed("curl -fsS http://127.0.0.1:30141/ >/dev/null")
    machine.succeed("systemctl show pi-web --property=User --value | grep alice")
    # ExecStart 拼接：端口走 -p flag，且固定 --no-open（无人值守服务场景）
    machine.succeed("systemctl cat pi-web | grep -- '--no-open'")
    machine.succeed("systemctl cat pi-web | grep -- '-p 30141'")
    # env 映射：host 默认值、password 透传
    machine.succeed("systemctl show pi-web --property=Environment | grep 'PI_WEB_HOSTNAME=127.0.0.1'")
    machine.succeed("systemctl show pi-web --property=Environment | grep 'PI_WEB_PASSWORD=test'")
  '';
}
