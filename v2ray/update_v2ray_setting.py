import re
import json
import uuid
import base64
import paramiko

# /usr/bin/python3 /Users/jizheshuaishuai/Documents/update_v2ray_setting.py

server_info = '160.25.75.85:4433:root:S*FkZyCGs5#F*m8'
# server_info = '38.54.96.53:22:root:a12152205.A'
# server_info = '117.18.124.158:22:root:J!b!!Xq1ec89'
command_type = 'add'
# command_type = 'update'

channel = '9cloud.vip'


def connect_server():
    # 配置连接信息
    hostname, port, username, password = server_info.split(":")

    # 创建SSH客户端
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    # 使用私钥连接服务器
    ssh_client.connect(hostname, int(port), username, password)

    return ssh_client


def main():
    ssh_client = connect_server()

    user_name = '9cloud.vip'
    passwd = str(uuid.uuid4()).split("-")[4]

    vmess_url = ''
    socks_url = ''
    socks_info = ''

    if command_type == 'add':
        commands = [
            'bash <(wget -qO- -o- https://git.io/v2ray.sh)',
            'v2ray a socks auto ' + user_name + ' ' + passwd,
            'v2ray bbr'
        ]
    else:
        clients_id = str(uuid.uuid4())
        commands = [
            # 'v2ray uninstall',
            'v2ray a tcp auto ' + clients_id,
            'v2ray a socks auto ' + user_name + ' ' + passwd
        ]

    # 执行命令并获取输出
    for command in commands:
        stdin, stdout, stderr = ssh_client.exec_command(command)
        # 逐行输出执行结果
        for line in stdout.readlines():
            result = line.strip()
            result = re.sub("\u001B\\[\\d+(;\\d+)*m", "", result)
            print('命令 %s command 执行结果：%s' % (command, result))
            if result.find('vmess://') != -1:
                vmess_url = result
                vmess_infos = vmess_url.split('//')
                vmess_json = json.loads(base64.b64decode(vmess_infos[1]).decode('utf-8'))
                vmess_json['ps'] = channel + '-' + vmess_json['add']
                vmess_url = 'vmess://' + base64.b64encode(json.dumps(vmess_json).encode("utf-8")).decode("utf-8")

            if result.find('socks://') != -1:
                socks_url = result
                socks_url = socks_url.replace('233boy', channel)

                socks_ip_infos = socks_url.split("@")
                socks_info = socks_ip_infos[1].split("#")[0] + ":" + base64.b64decode(
                    socks_ip_infos[0].split('//')[1]).decode('utf-8')

    print('vmess链接：')
    print('%s' % vmess_url)
    print('socks链接：')
    print('%s' % socks_url)
    print('socks信息：')
    print('%s' % socks_info)


if __name__ == '__main__':
    main()
