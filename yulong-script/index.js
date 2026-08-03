// 御龙 替换中转域名为catsboy.site
const dataArr = [

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
