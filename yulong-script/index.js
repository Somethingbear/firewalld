// 御龙 替换中转域名为catsboy.site
const dataArr = [
  {
    id: 459829,
    serverName: "科进-1-美国-加利福尼亚-洛杉矶-A1",
    serverId: 1,
    ip: "38.84.88.221",
    channelName: "御龙网络",
    protocol: "vmess",
    nodeTag: "38.84.88.221-御龙网络-31125-in",
    status: 1,
    expireTime: "2026-09-02T12:03:45.000+08:00",
    closeTime: null,
    ipInfo:
      "vmess://ewogICAgInYiOiIyIiwKICAgICJwcyI6IjM4Ljg0Ljg4LjIyMSIsCiAgICAiYWRkIjoiMzguODQuODguMjIxIiwKICAgICJwb3J0IjoiMzExMjUiLAogICAgImlkIjoiMGU0MWJjMDQtZjYxYi00MzBiLTg5YzktZmFiYmQxMmIwMWZmIiwKICAgICJhaWQiOiIwIiwKICAgICJzY3kiOiJhdXRvIiwKICAgICJuZXQiOiJ0Y3AiLAogICAgInR5cGUiOiJub25lIiwKICAgICJob3N0IjoiIiwKICAgICJwYXRoIjoiIiwKICAgICJ0bHMiOiIiLAogICAgInNuaSI6IiIsCiAgICAiYWxwbiI6IiIKfQ==",
    ipInfoWithSpeed:
      "vmess://ewogICAgInYiOiIyIiwKICAgICJwcyI6Iue+juWbvS0zOC44NC44OC4yMjEiLAogICAgImFkZCI6ImNhdHNib3kub25saW5lIiwKICAgICJwb3J0IjoiMjE5MTkiLAogICAgImlkIjoiMGU0MWJjMDQtZjYxYi00MzBiLTg5YzktZmFiYmQxMmIwMWZmIiwKICAgICJhaWQiOiIwIiwKICAgICJzY3kiOiJhdXRvIiwKICAgICJuZXQiOiJ0Y3AiLAogICAgInR5cGUiOiJub25lIiwKICAgICJob3N0IjoiIiwKICAgICJwYXRoIjoiIiwKICAgICJ0bHMiOiIiLAogICAgInNuaSI6IiIsCiAgICAiYWxwbiI6IiIKfQ==",
    trafficOrderId: null,
    trafficRegularId: null,
    speedIp: "103.181.165.240",
    speedPort: 21919,
    deleteTime: null,
    orderNo: "20260803985895460150979340",
  },
];
copy(
  dataArr
    .map((item) => {
      let vmStr = `vmess://${btoa(JSON.stringify({ ...JSON.parse(atob(item.ipInfoWithSpeed.split("//")[1])), add: "catsboy.site" }))}`;
      let str = `${item.serverName.split("-").slice(2).join("-")},${item.ip},${vmStr}`;
      return str;
    })
    .join("\n"),
);
