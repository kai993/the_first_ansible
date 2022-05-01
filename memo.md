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

## 高速化

### SSHマルチプレキシングの有効化

- OpenSSHは一般的なSSHの実装
  - SSHマルチプレキシング・ControlPeersistと呼ばれる最適化の仕組みをサポートしている
  - SSHマルチプレキシングは同一ホストへの複数のSSHセッションは同じTCPの接続を共有するため、TCP接続のネゴシエーションが行われるのは1度だけ

マルチプレキシングを有効にするとSSHの動作は次になる
- 初回のSSH接続の際にOpenSSHはマスターの接続を開始
- 接続先のホストに関連づけられたUnixのドメインソケット(コントロールソケット)を生成
- 次回からの接続は新しいTCP接続を生成せず、コントロールソケットを使って通信を行う

SSHマルチプレキシングを有効化する

```conf
Host node1.sample.co.jp
  ControlMaster auto       # SSHマルチプレキシングを有効化
  ControlPath /tmp/%r%h:%p # Unixドメインソケットファイルの置き場所
  ControlPersist 10m       # マスター接続が維持される時間
```

マスター接続がオープンになってるか

```bash
$ ssh -O check vagrant1
Master running (pid=11682)

# コントロールマスタープロセス
$ ps 11682
  PID   TT  STAT      TIME COMMAND
11682   ??  Ss     0:00.00 ssh: /Users/kwatabiki/.ssh/165120199516114 [mux]

# マスター接続の終了
$ ssh -O exit vagrant1
```

時間の計測

```bash
# 初回
$ time ssh vagrant1 /bin/true
ssh vagrant1 /bin/true  0.01s user 0.01s system 7% cpu 0.219 total

# 2回目
$ time ssh vagrant1 /bin/true
ssh vagrant1 /bin/true  0.00s user 0.00s system 29% cpu 0.019 total
```

### 並列処理
並列度はデフォルトで5になっていて、パラメータを変更する方法は2つある

```bash
# ANSIBLE_FORKSの設定
$ export ANSIBLE_FORKS=1

# ansible.cfgで設定
$ cat ansible.cfg
[defalts]
forks = 1

# forks=1
$ time ansible-playbook -i hosts greet.yml
...
ansible-playbook -i hosts greet.yml  1.05s user 0.41s system 49% cpu 2.969 total

# forks=50
$ time ansible-playbook -i hosts greet.yml
ansible-playbook -i hosts greet.yml  1.04s user 0.41s system 64% cpu 2.268 total
```

## カスタムモジュール

### カスタムモジュール

`library/`ディレクトリに配置する

Ansibleがモジュールを呼び出す流れは次

- スタンドアローンのPythonスクリプトを引数付きで生成
- モジュールをホストにコピー
- 引数ファイルをホスト上で生成(非Pythonモジュールの場合)
- 引数ファイルを引数として渡し、ホスト上でモジュールを呼び出す
- モジュールの標準出力への出力をパース

AnsibleモジュールはJSONを出力しないといけない

- changed : 論理型の変数。モジュールの実行によってホストの状態が変化したかを示す。
- failed : 失敗した場合、`failed=true`を返す。
- msg : 失敗した理由を説明するメッセージを追加する。

library/greet

```python
#!/usr/bin/python

from ansible.module_utils.basic import *

def main():
    module = AnsibleModule(
                argument_spec=dict(
                    word=dict(default="World!"),
                ),
                supports_check_mode=True
             )

    # checkモードでは何も処理を行わない
    # change=Falseを返す
    if module.check_mode:
        module.exit_json(changed=False)

    word = "Hello " + module.params['word'] + "!"
    module.exit_json(greet=word, changed=False)

if __name__ == '__main__':
    main()
```

playbook

```yaml
    - name: run greet module
      greet: word="Python"
      register: greet

    - name: debug greet
      debug:
        var: greet
```

実行

```bash
❯ ansible-playbook -i hosts greet.yml
...
TASK [run greet module] **********************************************************************************************************************************************************************************************************************
ok: [node1.sample.co.jp]
TASK [debug greet] ***************************************************************************************************************************************************************************************************************************
ok: [node1.sample.co.jp] => {
    "greet": {
        "changed": false,
        "failed": false,
        "greet": "Hello Python!"
    }
}
```

### スクリプトモジュール

`scripts/`ディレクトリに配置する

```bash
❯ cat scripts/greet.sh
#!/bin/bash
arg=$1

if [ -z "$arg" ]; then
  arg="script"
fi

echo "Hello $arg!"
```

playbook

```yaml
    - name: custom script
      script: scripts/greet.sh {{ ansible_hostname }}
      register: greet

    - name: debug greet
      debug:
        var: greet.stdout_lines
```

実行

```bash
❯ ansible-playbook -i hosts greet.yml
...
TASK [custom script] *************************************************************************************************************************************************************************************************************************
changed: [node1.sample.co.jp]

TASK [debug greet] ***************************************************************************************************************************************************************************************************************************
ok: [node1.sample.co.jp] => {
    "greet.stdout_lines": [
        "Hello node1!"
    ]
}
```

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

## memo
ロケール追加

```bash
# エラーが出る
$ vagrant ssh vagrant1
Last login: Fri Apr 29 03:18:03 2022 from 10.0.2.2
-bash: warning: setlocale: LC_CTYPE: cannot change locale (UTF-8): No such file or directory

# ja_JPがない
[vagrant@node1 ~]$ locale -a | grep -i utf
locale: Cannot set LC_CTYPE to default locale: No such file or directory
en_AG.utf8
en_AU.utf8
en_BW.utf8
en_CA.utf8
en_DK.utf8
en_GB.utf8
en_HK.utf8
en_IE.utf8
en_IN.utf8
en_NG.utf8
en_NZ.utf8
en_PH.utf8
en_SG.utf8
en_US.utf8
en_ZA.utf8
en_ZM.utf8
en_ZW.utf8

# ロケール追加
[vagrant@node1 ~]$ sudo localedef -f UTF-8 -i ja_JP ja_JP

[vagrant@node1 ~]$ sudo localectl list-locales | grep -i ja
ja_JP
ja_JP.utf8

# ロケール変更
[vagrant@node1 ~]$ sudo localectl set-locale LANG=ja_JP.utf8

[vagrant@node1 ~]$ localectl status
localectl status
   System Locale: LANG=ja_JP.utf8
       VC Keymap: us
      X11 Layout: n/a

[vagrant@node1 ~]$ source /etc/locale.conf

[vagrant@node1 ~]$ exit

$ vagrant ssh vagrant1
```
