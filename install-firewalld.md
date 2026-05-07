### 1

cd /etc/yum.repos.d/ && sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-_ && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-_

### 2

yum install firewalld

### 3

systemctl unmask firewalld.service
systemctl enable firewalld.service
systemctl start firewalld.service
firewall-cmd --add-masquerade --permanent

### 4

将我的一个配置文件public.xml 上传到/etc/firewalld/zones/
重启
firewall-cmd --reload
