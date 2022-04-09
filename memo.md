# Ansible memo

## local(Mac)
```bash
❯ pip3 --version
pip 21.1.3 from /usr/local/lib/python3.9/site-packages/pip (python 3.9)

❯ pip3 install ansible

❯ ansible --version
ansible [core 2.12.3]
  config file = None
...
  python version = 3.9.6 (default, Jun 29 2021, 05:25:02) [Clang 12.0.5 (clang-1205.0.22.9)]
  jinja version = 3.0.3
  libyaml = True
```

## リモートサーバー(Centos7)
```bash
@mac
❯ grep -v -e '#' -e '^\s*$' Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.hostname = "centos7.sample.co.jp"
end

❯ basename $(pwd)
centos7

❯ vagrant ssh-config
Host default
  HostName 127.0.0.1
  User vagrant
  Port 2222
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /Users/kwatabiki/ansible/centos7/.vagrant/machines/default/virtualbox/private_key
  IdentitiesOnly yes
  LogLevel FATAL

❯ vagrant up

# ssh接続できるようにする
❯ vagrant ssh-config --host centos7.sample.co.jp >> ~/.ssh/config

# ssh接続できることを確認
❯ ssh -A centos7.sample.co.jp
[vagrant@centos7 ~]$
```

## ansibleコマンドで接続できるか確認

```bash
@mac
❯ cat hosts
testserver ansible_ssh_host=centos7.sample.co.jp

# OK!
❯ ansible testserver -i hosts -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

## 基礎

### ansible.cfg

インベントリファイルに記載するのではなく設定ファイルに記載することでデフォルトで設定することができる。  
設定できるものは[ここ](https://docs.ansible.com/ansible/2.9_ja/reference_appendices/config.html#ansible-configuration-settings)を参照

```bash
@mac
❯ cat ansible.cfg
[defaults]
inventory = hosts

❯ cat hosts
testserver ansible_ssh_host=centos7.sample.co.jp

❯ ansible testserver -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}

# 全てのサーバーに対して実行する場合はallとする
❯ ansible all -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

### 任意のコマンドを使う
commandモジュールと`-a`オプションで任意のコマンドを実行することが可能

```bash
❯ ansible testserver -m command -a uptime
testserver | CHANGED | rc=0 >>
 07:38:14 up 28 min,  2 users,  load average: 0.00, 0.01, 0.02

❯ ansible testserver -m command -a "tail -n 5 /var/log/dmesg"
testserver | CHANGED | rc=0 >>
[    3.000978] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    3.102363] alg: No test for __gcm-aes-aesni (__driver-gcm-aes-aesni)
[    3.113798] alg: No test for __generic-gcm-aes-aesni (__driver-generic-gcm-aes-aesni)
[    3.145639] Adding 2097148k swap on /swapfile.  Priority:-2 extents:1 across:2097148k FS
[    3.218571] intel_pmc_core:  initialized

# -bフラグを渡すとsudoしてrootになる
❯ ansible testserver -a "ls /root"
testserver | FAILED | rc=2 >>
ls: cannot open directory /root: Permission deniednon-zero return code

❯ ansible testserver -b -a "ls /root"
testserver | CHANGED | rc=0 >>
anaconda-ks.cfg
original-ks.cfg
```

### タスク

基本的なタスク

```yaml
# nameはなくても問題ないが指定しておくのが良い
# --start-at-task [タスク名]で途中からタスクを実行できる
- name: install nginx
  yum: name=nginx update_cache=yes
```

複数行で書く場合

```yaml
- name: install nginx
  apt: >
    name=nginx
    update_cache=yes
```

### モジュール
Ansibleに同梱されているスクリプト群のこと

- [yum](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yum_module.html)
- [template](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [copy](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [service](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)など

ドキュメントを見る

```bash
# serviceモジュールの場合
❯ ansible-doc service
```

### 変数

https://docs.ansible.com/ansible/2.9_ja/user_guide/playbooks_variables.html

- varsを使う
- ダブルクォートで囲む

```
vars:
  filename: /etc/hoge.txt
  dest: {{ filename }}   # syntax error
  dest: "{{ filename }}" # ok!
```

### テンプレート

設定ファイルのためのテンプレートエンジンとして[Jinra2][jinja2]を採用してる。  
`templates/`ディレクトリに配置する。

```
# 例
templates/index.html.j2
```

### ハンドラ

https://docs.ansible.com/ansible/2.9_ja/user_guide/playbooks_intro.html#handlers

ハンドラは条件付き処理の一つで、タスクから通知された時のみ実行される。  
例えばnginxでは以下の状況の時に再起動が必要になる。
- TLSの鍵が変更された
- TLSの証明書が変更されたなど

これらの状況が生じた場合にnotify文を使う

```
    - name: copy TLS key
      ansible.builtin.copy:
        src: files/nginx.key
        dest: "{{ key_file }}"
        owner: root
        mode: '0600'
      notify: restart nginx

  handlers:
    - name: restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted

```

ハンドラが実行されるのはタスクが全て実行された後で、通知が複数ある場合も実行されるのは一度限り。  
一般的な利用方法はサービスの再起動とリブートだけとされてる。

## インベントリ
- ホストを記述するデフォルトの方法はインベントリファイルと呼ばれるテキストファイルに記載する
- デフォルトでlocalhostをインベントリに自動的に追加する
- フォーマットは`.ini`になってる

- 複数ホストへの接続

```bash
❯ cat ansible.cfg
[defaults]
inventory = inventory
remote_user = vagrant
private_key_file = ~/.vagrant.d/insecure_private_key
host_key_checking = false

❯ cat inventory
[webservers]
vagrant1 ansible_host=node1.sample.co.jp ansible_port=2222
vagrant2 ansible_host=node2.sample.co.jp ansible_port=2200
vagrant3 ansible_host=node3.sample.co.jp ansible_port=2201

❯ ansible all -m ping
vagrant2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
vagrant1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
vagrant3 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}

# 特定のホストでの実行
❯ ansible vagrant2 -a "ip addr show dev eth0" -b
vagrant2 | CHANGED | rc=0 >>
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 52:54:00:4d:77:d3 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global noprefixroute dynamic eth0
       valid_lft 85324sec preferred_lft 85324sec
    inet6 fe80::5054:ff:fe4d:77d3/64 scope link
       valid_lft forever preferred_lft forever
```

### インベントリパラメータ
ホストに対してパラメータを指定することができる

https://docs.ansible.com/ansible/2.9_ja/user_guide/intro_inventory.html#behavioral-parameters

```ini
vagrant1 ansible_host=node1.sample.co.jp ansible_port=2222
vagrant2 ansible_host=node2.sample.co.jp ansible_port=2200
vagrant3 ansible_host=node3.sample.co.jp ansible_port=2201
```

### グルーピング

```ini
# vagrant1はエイリアス
vagrant1 ansible_host=node1.sample.co.jp ansible_port=2222
vagrant2 ansible_host=node2.sample.co.jp ansible_port=2200
vagrant3 ansible_host=node3.sample.co.jp ansible_port=2201

[vagrant]
vagrant1
vagrant2
vagrant3
```

範囲の指定

```ini
[web]
sample[1:10].example.com

# 0埋め
sample[01:10].example.com

# アルファベット
sample-[a-e].example.com
```

サーバーごとの変数

```ini
sample1.example.com environment=production
sample2.example.com environment=staging
sample3.example.com environment=development
```

グループ変数

```ini
[all:vars]
db_name=db1
db_username=user1

[production:vars]
db_password=hoge
environment=production

[staging:vars]
db_password=foo
environment=staging

[development:vars]
db_password=bar
environment=development
```

### host_vars
ホストごとの変数をファイルにyaml形式で定義する

### group_vars
グループごとの変数をファイルにyaml形式で定義する

```
❯ yq group_vars/all
db:
  user: user1

❯ yq group_vars/production
db:
  password: password
  database: db1
  privary:
    host: privary.example.com
    port: 3306
  replica:
    host: replica.example.com
    port: 3306
rabbitmq:
  host: pennsylvania.example.com
  port: 6379
```

細かく分割する場合

```yaml
❯ ls -1 group_vars/production
db
rabbitmq

❯ yq group_vars/production/db
db:
  user: user1
  password: password
  database: db1
  privary:
    host: privary.example.com
    port: 3306
  replica:
    host: replica.example.com
    port: 3306

❯ yq group_vars/production/rabbitmq
rabbitmq:
  host: pennsylvania.example.com
  port: 6379
```

## 動的インベントリ
https://docs.ansible.com/ansible/2.9_ja/user_guide/intro_dynamic_inventory.html

## 変数とファクト

変数を定義する最もシンプルな方法はplaybookの`vars`セクションに定義すること

```yaml
vars:
  key1: val1
  key2: val2
  key3: val3
```

### ファイルから読み込む

```yaml
vars_files:
  - nginx.yml

# nginx.yml
key1: val1
key2: val2
key3: val3
```

### debug

変数の値を表示する場合は`debug`モジュールを使用する

```yaml
  tasks:
    - name: print vars
      ansible.builtin.debug:
        msg: "key_file={{ key_file }}, cert_file={{ cert_file }}, conf_file={{ conf_file }}, server_name={{ server_name }}"

# output
TASK [print vars] *****************************************************************************************************************************************************
ok: [testserver] => {
    "msg": "key_file=/etc/nginx/ssl/nginx.key, cert_file=/etc/nginx/ssl/nginx.crt, conf_file=/etc/nginx/conf.d/default.conf, server_name=localhost"
}
```

### 変数の登録

`register`を使うと、タスクの結果に基づいて変数の設定をすることができる。

```yaml
  tasks:
    - name: capture output of id command
      command: id -un
      register: login

    - debug: var=login
```

output

```bash
TASK [debug] **********************************************************************************************************************************************************
ok: [testserver] => {
    "login": {
        "changed": true,
        "cmd": [
            "id",
            "-un"
        ],
        "delta": "0:00:00.003296",
        "end": "2022-03-26 07:54:19.878639",
        "failed": false,
        "msg": "",
        "rc": 0,
        "start": "2022-03-26 07:54:19.875343",
        "stderr": "",
        "stderr_lines": [],
        "stdout": "root",
        "stdout_lines": [
            "root"
        ]
    }
}
```

register節を使うとstdoutキーにアクセスできるようになる

```yaml
- name: capture output of id command
  command: id -un
  register: login

- debug: msg="Logged in as user {{ login.stdout }}"
```

モジュールが返したエラーを無視する場合は[ignore_erros](https://docs.ansible.com/ansible/latest/user_guide/playbooks_error_handling.html)を使う

```yaml
- name: capture output of id command
  command: id -un
  register: login
  ignore_errors: True
- debug: msg="Logged in as user {{ login.stdout }}"
```

### ファクト

playbookを実行した時に出力されるこれ

```console
TASK [Gathering Facts] ***********************************************************************************************************************************************************************************************************************
ok: [testserver]
```

ホストに接続しCPU、アーキテクチャ、OSなどのホストに関するあらゆる詳細(ファクト)の収集を実施する。

各サーバーのOSを出力する

```yaml
    - debug: var=ansible_distribution
```

```console
TASK [debug] *********************************************************************************************************************************************************************************************************************************
ok: [testserver] => {
    "ansible_distribution": "CentOS"
}
```

利用できるfactは次のコマンドで確認できる。

```bash
❯ ansible all -m setup | grep ansible_distribution
        "ansible_distribution": "CentOS",
        "ansible_distribution_file_parsed": true,
        "ansible_distribution_file_path": "/etc/redhat-release",
        "ansible_distribution_file_variety": "RedHat",
        "ansible_distribution_major_version": "7",
        "ansible_distribution_release": "Core",
        "ansible_distribution_version": "7.8",
```

filterパラメータで出力を一部に絞ることができる。

```
❯ ansible all -m setup -a 'filter=ansible_default_ipv*'
testserver | SUCCESS => {
    "ansible_facts": {
        "ansible_default_ipv4": {
            "address": "10.0.2.15",
            "alias": "eth0",
            "broadcast": "10.0.2.255",
            "gateway": "10.0.2.2",
            "interface": "eth0",
            "macaddress": "52:54:00:4d:77:d3",
            "mtu": 1500,
            "netmask": "255.255.255.0",
            "network": "10.0.2.0",
            "type": "ether"
        },
        "ansible_default_ipv6": {},
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false
}
```

### ローカルファクト

ホストの`/etc/ansible/facts.d`ディレクトリに下記のファイルを置くと`ansible_local`変数として利用できる。

- .ini
- .json
- 実行可能であり、引数を取らずに標準出力にJSONを出力すること

file

```bash
❯ jq . files/variable.json
{
  "vars": {
    "title": "The first Ansible.",
    "language": "Python",
    "year": 2022
  }
}
```

playbook

```yaml
    - name: create ansible local directory.
      ansible.builtin.file:
        path: "{{ local_vars_dirs }}"
        state: directory
        mode: '0755'

    - name: copy ansible local vars.
      ansible.builtin.copy:
        src: files/variable.fact
        dest: "{{ local_vars_dirs }}/variable.fact"
        mode: '0755'

    - name: print ansible_local
      debug: var=ansible_local

    - name: print language
      debug: msg="{{ ansible_local.variable.vars.language }}"
```

### 組み込み変数

いくつかの変数をplaybookのなかで使えるように定義している。

- hostvars
- inventory_hostname 
- groups_name
- groups
- play_hosts
- ansible_version


#### hostvars

```yaml
    - debug: msg="{{ hostvars['testserver'].ansible_all_ipv4_addresses[0] }}"
```

```bash
$ ansible-playbook main.yml
TASK [debug] *************************************************************************************************************************************************************************************************************************************************************
ok: [testserver] => {
    "msg": "192.168.56.10"
}

PLAY RECAP ***************************************************************************************************************************************************************************************************************************************************************
testserver                 : ok=8    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

#### inventory_hostname

現在のホストに関連づけられた全ての変数を出力できる

```bash
$ cat hosts
[webservers]
testserver ansible_ssh_host=node1.sample.co.jp
```

### コマンドライン上で変数を設定する

```yaml
# greet.yml
- name: pass a message on the command line
  hosts: development
  vars:
    greeting: "you didn't specify a message"
  tasks:
    - name: output a message
      debug: msg="{{ greeting }}"
```

```bash
$ ansible-playbook greet.yml
TASK [output a message] **************************************************************************************************************************************************************************************************************************************************
ok: [testserver1] => {
    "msg": "you didn't specify a message"
}

PLAY RECAP ***************************************************************************************************************************************************************************************************************************************************************
testserver1                : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

変数を設定する場合

```bash
$ ansible-playbook greet.yml -e greeting=こんにちは
TASK [output a message] **************************************************************************************************************************************************************************************************************************************************
ok: [testserver1] => {
    "msg": "こんにちは"
}

PLAY RECAP ***************************************************************************************************************************************************************************************************************************************************************
testserver1                : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

空白を使う場合

```bash
$ ansible-playbook greet.yml -e 'greeting="Hello Warp!"'
TASK [output a message] **************************************************************************************************************************************************************************************************************************************************
ok: [testserver1] => {
    "msg": "Hello Warp!"
}

PLAY RECAP ***************************************************************************************************************************************************************************************************************************************************************
testserver1                : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

ファイルから渡す場合

```yaml
$ yq . greetvars.yml
greeting: HELLO
```

```bash
$ ansible-playbook greet.yml -e @greetvars.yml
TASK [output a message] **************************************************************************************************************************************************************************************************************************************************
ok: [testserver1] => {
    "msg": "HELLO"
}

PLAY RECAP ***************************************************************************************************************************************************************************************************************************************************************
testserver1                : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### 優先順位
- コマンドラインから渡す(ansible-playbook -e var=value)
- インベントリファイル
- ファクト
- ロール(defaults/main.yml)

## tools
- [その他のツールおよびプログラム &mdash; Ansible Documentation](https://docs.ansible.com/ansible/2.9_ja/community/other_tools_and_programs.html)
- [fboender/ansible-cmdb](https://github.com/fboender/ansible-cmdb)

## 参考
- [初めてのAnsible][oreilly_ansible]
- [Ansible Best Practices][ansible_best_practices]

<!-- link -->
[jinja2]: https://jinja.palletsprojects.com/en/3.1.x/
[ansible_best_practices]: https://aap2.demoredhat.com/decks/ansible_best_practices.pdf
[oreilly_ansible]: https://www.oreilly.co.jp/books/9784873117652/
