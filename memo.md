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

## ansible.cfg

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

## 任意のコマンドを使う
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

## タスク

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

## モジュール
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

## 変数

https://docs.ansible.com/ansible/2.9_ja/user_guide/playbooks_variables.html

- varsを使う
- ダブルクォートで囲む

```
vars:
  filename: /etc/hoge.txt
  dest: {{ filename }}   # syntax error
  dest: "{{ filename }}" # ok!
```

## テンプレート

設定ファイルのためのテンプレートエンジンとして[Jinra2][jinja2]を採用してる。  
`templates/`ディレクトリに配置する。

```
# 例
templates/index.html.j2
```

## ハンドラ

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

## tools
- [その他のツールおよびプログラム &mdash; Ansible Documentation](https://docs.ansible.com/ansible/2.9_ja/community/other_tools_and_programs.html)
- [fboender/ansible-cmdb](https://github.com/fboender/ansible-cmdb)

<!-- link -->
[jinja2]: https://jinja.palletsprojects.com/en/3.1.x/

