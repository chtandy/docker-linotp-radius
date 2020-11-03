# 主要整合LinOTP + Radius 與 LDAP 做 MFA 登入驗證
### 注意事項
- 必須要有AD 相關設定才能完成
- OS 環境為`CentOS7` 或是 `AWS Amazon Linux 2`
- 需要有SSL憑證
- DB 若已經有主機提供服務,則可以忽略安裝`mariadb-server`


### 安裝LinOTP 和DB
- 安裝流程
```
# 取得LinOTP repo
yum localinstall http://linotp.org/rpm/el7/linotp/x86_64/Packages/LinOTP_repos-1.1-1.el7.x86_64.rpm -y

# 啟用 EPEL 儲存庫
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y

yum update -y
# MariaDB
yum install mariadb-server -y
systemctl enable mariadb
systemctl start mariadb
mysql_secure_installation  # 會設定root密碼等相關DB設定 ,請參閱最後的注意事項

# LinOTP
yum install LinOTP LinOTP_mariadb -y

# Lock python-repoze-who version
yum install yum-plugin-versionlock -y
yum versionlock python-repoze-who

# install apache and vhost config
yum install LinOTP_apache -y
```
### 以下為DB新增LinOTP user ,paswd , db的流程
### dbuser為linotp ,dbuser passwd為mySecret ,linotp DB為L2demo
```
mysql -u root -p # DB於本地端
mysql -u root -p -h {DB IP} 
create database LinOTP;
grant all privileges on LinOTP.* to 'linotp'@'%' identified by 'mySecret';
flush privileges;
quit;
```

### 以下為修改相關設定
```
mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.back
cp /etc/httpd/conf.d/ssl_linotp.conf.template /etc/httpd/conf.d/ssl_linotp.conf
cp /etc/linotp2/linotp.ini.example /etc/linotp2/linotp.ini

# 修改/etc/linotp2/linotp.ini中的
`sqlalchemy.url = mysql://linotp2:1234@localhost/LinOTP2` 替換為上述設定的
`sqlalchemy.url = mysql://linotp:mySecret@localhost/LinOTP`

# 新增DB加密金鑰,以下兩個擇一即可
dd if=/dev/urandom of=/etc/linotp2/encKey bs=1 count=96
linotp-create-enckey -f /etc/linotp2/linotp.ini

# create the linotp database tables
paster setup-app /etc/linotp2/linotp.ini
```
- 備註：
  - `linotp-create-enckey -f /etc/linotp2/linotp.ini`會針對`/etc/linotp2/linotp.ini` 檔案中的DB訊息產生一隻檔案`encKey`
  - 官方設定檔文件表示,若遺失這把key，會導致LinOTP重產一把,且LinOTP的配置無法使用,所以要備份
  ```
  ## Encrytion key:
  ## --------------
  ## The encryption key is used to encrypt the token seeds before storing them
  ## in the Token database.
  ##
  ## Caution: Be careful with this key - losing it, will render your token and
  ## LinOTP configuration useless
  linotpSecretFile = %(here)s/encKey
  ```


### 設定linopt admin 密碼
```
htdigest /etc/linotp2/admins "LinOTP2 admin area" admin
```

###  測試安裝是否成功,執行命令後看5001 port
```
paster serve /etc/linotp2/linotp.ini
```
- http://{IP}:5001
  - 帳號為admin
  - 密碼為 linopt admin 密碼
### 調整資料夾權限
```
chown -R linotp /var/log/linotp
chown linotp /var/log/linotp/linotp.log
chown -R linotp /etc/linotp2
```

### 啟動linotp httpd的服務
```
systemctl enable httpd
systemctl start httpd
```
### 沒有憑證會噴錯誤訊息,可先用自簽憑證
```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.crt
# 以下為需要填的項目
Country Name (2 letter code) [XX]:
State or Province Name (full name) []:
Locality Name (eg, city) [Default City]:
Organization Name (eg, company) [Default Company Ltd]:
Organizational Unit Name (eg, section) []:
Common Name (eg, your name or your server's hostname) []:
Email Address []:

# 啟動linotp httpd的服務
systemctl start httpd
```


### google chrome 會顯示非安全網站,可以在網頁內輸入
```
thisisunsafe
```
### LinOTP 設定
### 主要設定去問哪個AD主機
- LinOTP配置 > 用戶ID解析器 > 新建 > LDAP
```
解析器名稱:  {idapresover name}
服務器連接:  ldap://{IP}, ldap://{IP}
基本DN:      dc={dc},dc={dc},dc={dc}
綁定DN:      cn={cm},ou={ou},dc={dc},dc={dc},dc={dc}
綁定密碼:    
超時:        30
長度限制:    1000

```
- LinOTP 新增`域` ,這裡的`域` 設定會在Radius 設定的 `/etc/linotp2/rlm_perl.ini` 中的`REALM=<your-realm>` 需同一個值
  - 通常會與`用戶ID解析器`的值一樣  
- Linotp > LinOTP配置 > 域
### 導入OTP policy ,啟用用戶使用MFA
- 導入 policy.txt
```
[Limit_to_one_token]
realm = *
name = Limit_to_one_token
action = maxtoken=1
client = *
user = *
time = * * * * * *;
active = True
scope = enrollment
[OTP_to_authenticate]
realm = *
name = OTP_to_authenticate
action = otppin = token_pin
client = *
user = *
time = * * * * * *;
active = True
scope = authentication
[Default_Policy]
realm = *
name = Default_Policy
action = "enrollTOTP, reset, resync, setOTPPIN, disable,delete "
client = *
user = *
time = * * * * * *;
active = True
scope = selfservice
```
  - 在策略頁籤中,選擇導策略
  - 選擇policy.txt檔案 > 導入策略檔案
  
- 或是直接新增也可以,需新增三個
  - Default_Policy
  ```
  策略名称	   Default_Policy     
  范围         selfservice         
  行为         enrollTOTP, reset, resync, setOTPPIN, disable,delete  
  用户	     *
  域           *
  客户         *	
  时间         * * * * * *;
  ```
  - Limit_to_one_token
  ```
  策略名称	   Limit_to_one_token     
  范围         enrollment         
  行为         maxtoken=1 
  用户	     *
  域           *
  客户         *	
  时间         * * * * * *;
  ```
  - OTP_to_authenticate
  ```
  策略名称	   OTP_to_authenticate     
  范围         authentication         
  行为         otppin = token_pin 
  用户	     *
  域           *
  客户         *	
  时间         * * * * * *;
  ```

### 注意事項
- 主要設定檔
  - 設定httpd的密碼
  ```
  htdigest /etc/linotp2/admins "LinOTP2 admin area" admin
  ```
  - 設定DB帳號,密碼,主機位址,資料庫名稱
    - `/etc/linotp2/linotp.ini`
  - https ssl 憑證位址
    - `/etc/httpd/conf.d/ssl_linotp.conf`
    
- 驗證設定檔是否正確
  - `paster serve /etc/linotp2/linotp.ini`
    - http://{IP}:5001
- 驗證Token 是否正確
  ```
  curl -k 'https://localhost/validate/check?user={username}&pass={Token-From-Google-Authenticator}'
  ```
  - 成功訊息
  ```
  {
   	"version": "LinOTP 2.11.2",
   	"jsonrpc": "2.0802",
   	"result": {
          "status": true,
      	  "value": true
     },
     "id": 0
  }   
  ```
  
### 到此LinOTP 已經安裝並啟用完成
---




### 安裝Radius
```
yum install git cpanminus freeradius freeradius-perl freeradius-utils perl-App-cpanminus perl-LWP-Protocol-https perl-Try-Tiny -y
cpanm Config::File
```
### 以下為設定流程
- 重新命名舊的設定
```
mv /etc/raddb/clients.conf /etc/raddb/clients.conf.back
mv /etc/raddb/users /etc/raddb/users.back
mv /etc/raddb/mods-available/perl /etc/raddb/mods-available/perl.bak
```
- 新增新設定 vim `/etc/raddb/clients.conf` ,視情況修改成實際資料
- 此設定是誰可以來問,sso 是Direct Service 來問
```
client localhost {
        ipaddr  = 127.0.0.1
        netmask = 32
        secret  = 'SECRET'
}

client adconnector {
        ipaddr  = {Direct Service subnet}
        netmask = 24
        secret  = 'Core3366'
}

client adconnector {
        ipaddr  = {Direct Service subnet}
        netmask = 24
        secret  = 'Core3366'
}
```
```
client localhost {
        ipaddr  = 127.0.0.1
        netmask = 32
        secret  = 'SECRET'
}

client adconnector {
        ipaddr  = 0.0.0.0
        netmask = 0
        secret  = 'Core3366'
}
```

- 下載linotp perl module
```
git clone https://github.com/LinOTP/linotp-auth-freeradius-perl.git /usr/share/linotp/linotp-auth-freeradius-perl
```

- 新增linotp perl module 的設定, vim `/etc/raddb/mods-available/perl`
```
perl {
     filename = /usr/share/linotp/linotp-auth-freeradius-perl/radius_linotp.pm
}
```

- Activate perl
```
ln -s /etc/raddb/mods-available/perl /etc/raddb/mods-enabled/perl
```
- 新增linotp perl config ,vim `/etc/linotp2/rlm_perl.ini`, 其中`<your-realm>`要改成linotp `域`的值
```
URL=https://localhost/validate/simplecheck
REALM=<your-realm>
Debug=True
SSL_CHECK=False
```
- 移除沒用到的config
```
rm -f /etc/raddb/sites-enabled/inner-tunnel
rm -f /etc/raddb/sites-enabled/default
rm -f /etc/raddb/mods-enabled/eap
```

- 新增freeradius linotp virtual host 的設定, vim `/etc/raddb/sites-available/linotp`
```
server default {

listen {
	type = auth
	ipaddr = *
	port = 0

	limit {
	      max_connections = 16
	      lifetime = 0
	      idle_timeout = 30
	}
}

listen {
	ipaddr = *
	port = 0
	type = acct
}



authorize {
        preprocess
        IPASS
        suffix
        ntdomain
        files
        expiration
        logintime
        update control {
                Auth-Type := Perl
        }
        pap
}

authenticate {
	Auth-Type Perl {
		perl
	}
}


preacct {
	preprocess
	acct_unique
	suffix
	files
}

accounting {
	detail
	unix
	-sql
	exec
	attr_filter.accounting_response
}


session {

}


post-auth {
	update {
		&reply: += &session-state:
	}

	-sql
	exec
	remove_reply_message_if_eap
}
}
```
- 設定軟連結
```
ln -s /etc/raddb/sites-available/linotp /etc/raddb/sites-enabled/linotp
```

### 測試radiusd 設定檔
```
radiusd -X
```

### 啟用radiusd 服務
```
systemctl enable radiusd
systemctl start radiusd
```

### 到此Radius 已安裝完成
---

### 注意事項
- 以下是 `mysql_secure_installation` 的流程
1 # 輸入 root 的密碼，如果沒有設定過，直接按 Enter 鍵即可
Enter current password for root (enter for none):

2 # 設定 root 的密碼
Set root password? [Y/n] y

3 # 移除 anonymous 使用者
Remove anonymous users? [Y/n] y

4 # 取消 root 遠端登入
Disallow root login remotely? [Y/n] y

5 # 移除 test 資料表
Remove test database and access to it? [Y/n] y

6 # 重新載入資料表權限
Reload privilege tables now? [Y/n] y






### ec2 在private 的做法
- 先在public env 把服務架起來後,最後將ssm 服務加入proxy,這樣才能用ssm登入
  - ssm proxy 設定方式
    - `systemctl edit amazon-ssm-agent`, proxy的設定每個環境不相同,須參考實際的設定
    ```
    [Service]
    Environment="http_proxy=http://{proxy ip}:{proxy port}"
    Environment="https_proxy=http://{proxy ip}:{proxy port}"
    Environment="no_proxy=169.254.169.254"
    ```
    - `sudo systemctl daemon-reload`
    - `systemctl restart amazon-ssm-agent`
- 在ec2上create image
- launch image 在private subnet,iam role 要選擇ssm
- privata ec2 好之後,驗證網頁ssm 能否執行
- 建立ACM,並在route53上驗證
- 建立provate alb, acm ,選擇https,憑證指到上述建立的acm,ec2選擇上述launch 起來的ec2
- route53 建立一筆cname紀錄,指到上述建立的private alb
- 測試結果,private ec2 不需要設定proxy,只需設定ssm proxy設定即可

### 注意事項
- 主要設定檔
  - 設定誰可以來訪問和使用LinOTP的域
    - `/etc/linotp2/rlm_perl.ini`
    
- 驗證設定檔是否正確
  - `radiusd -X`

- 驗證Radius驗證OTP
  ```
  radtest {username} {token-from-google-authenticator} localhost 0 SECRET
  ```
  -  成功訊息
  ```
  # Success result
  Sent Access-Request Id 19 from 0.0.0.0:50410 to 127.0.0.1:1812 length 81
	User-Name = "<username>"
	User-Password = "375937"
	NAS-IP-Address = 127.0.0.1
	NAS-Port = 0
	Message-Authenticator = 0x00
	Cleartext-Password = "375937"
  Received Access-Accept Id 19 from 127.0.0.1:1812 to 0.0.0.0:0 length 43
	Reply-Message = "LinOTP access granted"
  ```


### 補充 可用網頁驗證LinOTP服務正不正常
```
https://[IPAddressofRADIUS]/validate/check?user=USERNAME&pass=PINOTP
```
成功畫面
```
{
   "version": "LinOTP 2.10.1", 
   "jsonrpc": "2.0802", 
   "result": {
      "status": true, 
      "value": true
   }, 
   "id": 0
}
```



















### 備註
- ploicy version 2
```
[Limit_to_one_token]
realm = *
name = Limit_to_one_token
action = maxtoken=1
client = *
user = *
time = * * * * * *;
active = True
scope = enrollment
[OTP_to_authenticate]
realm = *
name = OTP_to_authenticate
action = otppin = token_pin
client = *
user = *
time = * * * * * *;
active = True
scope = authentication
[Require_MFA_at_Self_Service_Portal]
realm = *
name = Require_MFA_at_Self_Service_Portal
active = False
client = *
user = *
time = * * * * * *;
action = mfa_login
scope = selfservice
[Default_Policy]
realm = *
name = Default_Policy
active = True
client = *
user = *
time = * * * * * *;
action = "enrollTOTP, reset, resync, setOTPPIN, disable"
scope = selfservice
```
